import 'dart:async';

import 'package:drift/drift.dart';
import 'package:mixin_bot_sdk_dart/mixin_bot_sdk_dart.dart'
    hide User, Conversation;
import 'package:rxdart/rxdart.dart';

import '../../enum/encrypt_category.dart';
import '../../ui/home/bloc/slide_category_cubit.dart';
import '../../utils/extension/extension.dart';
import '../converter/conversation_status_type_converter.dart';
import '../converter/millis_date_converter.dart';
import '../mixin_database.dart';
import '../util/util.dart';
import 'app_dao.dart';

part 'conversation_dao.g.dart';

@DriftAccessor(tables: [Conversations])
class ConversationDao extends DatabaseAccessor<MixinDatabase>
    with _$ConversationDaoMixin {
  ConversationDao(super.db);

  late Stream<Set<TableUpdate>> updateEvent = db
      .tableUpdates(TableUpdateQuery.onAllTables([
        db.conversations,
        db.users,
        db.messages,
        db.snapshots,
        db.messageMentions,
        db.circleConversations,
      ]))
      .throttleTime(kSlowThrottleDuration, trailing: true);

  late Stream<int> allUnseenIgnoreMuteMessageCountEvent = db
      .tableUpdates(TableUpdateQuery.onAllTables([
        db.conversations,
        db.users,
      ]))
      .asyncMap((event) => allUnseenIgnoreMuteMessageCount().getSingle())
      .where((event) => event != null)
      .map((event) => event!);

  Selectable<int?> allUnseenIgnoreMuteMessageCount() =>
      db.baseUnseenMessageCount(
        (conversation, owner, __) {
          final now = const MillisDateConverter().toSql(DateTime.now());
          final groupExpression =
              conversation.category.equalsValue(ConversationCategory.group) &
                  conversation.muteUntil.isSmallerOrEqualValue(now);
          final userExpression =
              conversation.category.equalsValue(ConversationCategory.contact) &
                  owner.muteUntil.isSmallerOrEqualValue(now);
          return groupExpression | userExpression;
        },
      );

  Future<int> insert(Insertable<Conversation> conversation) =>
      into(db.conversations).insertOnConflictUpdate(conversation);

  Selectable<Conversation?> conversationById(String conversationId) =>
      (select(db.conversations)
        ..where((tbl) => tbl.conversationId.equals(conversationId)));

  OrderBy _baseConversationItemOrder(Conversations conversation) => OrderBy(
        [
          OrderingTerm.desc(conversation.pinTime),
          OrderingTerm.desc(conversation.lastMessageCreatedAt),
          OrderingTerm.desc(conversation.createdAt),
        ],
      );

  Selectable<int> _baseConversationItemCount(
    BaseConversationItemCount$where where,
  ) =>
      db.baseConversationItemCount((conversation, owner, circleConversation) =>
          where(conversation, owner, circleConversation));

  Selectable<ConversationItem> _baseConversationItems(
          Expression<bool> Function(
                  Conversations conversation,
                  Users owner,
                  Messages message,
                  Users lastMessageSender,
                  Snapshots snapshot,
                  Users participant)
              where,
          Limit limit) =>
      db.baseConversationItems(
        (
          Conversations conversation,
          Users owner,
          Messages message,
          Users lastMessageSender,
          Snapshots snapshot,
          Users participant,
          ExpiredMessages em,
        ) =>
            where(
          conversation,
          owner,
          message,
          lastMessageSender,
          snapshot,
          participant,
        ),
        (conversation, _, __, ___, ____, _____, em) =>
            _baseConversationItemOrder(conversation),
        (_, __, ___, ____, ______, _______, em) => limit,
      );

  Expression<bool> _conversationPredicateByCategory(SlideCategoryType category,
      [Conversations? conversation, Users? owner]) {
    final Expression<bool> predicate;
    conversation ??= db.conversations;
    owner ??= db.users;
    switch (category) {
      case SlideCategoryType.chats:
        predicate = conversation.category.isIn(['CONTACT', 'GROUP']);
        break;
      case SlideCategoryType.contacts:
        predicate =
            conversation.category.equalsValue(ConversationCategory.contact) &
                owner.relationship.equalsValue(UserRelationship.friend) &
                owner.appId.isNull();
        break;
      case SlideCategoryType.groups:
        predicate =
            conversation.category.equalsValue(ConversationCategory.group);
        break;
      case SlideCategoryType.bots:
        predicate =
            conversation.category.equalsValue(ConversationCategory.contact) &
                owner.appId.isNotNull();
        break;
      case SlideCategoryType.strangers:
        predicate =
            conversation.category.equalsValue(ConversationCategory.contact) &
                owner.relationship.equalsValue(UserRelationship.stranger) &
                owner.appId.isNull();
        break;
      case SlideCategoryType.circle:
      case SlideCategoryType.setting:
        throw UnsupportedError('Unsupported category: $category');
    }
    return predicate;
  }

  Future<bool> conversationHasDataByCategory(SlideCategoryType category) =>
      _conversationHasData(_conversationPredicateByCategory(category));

  Future<int> conversationCountByCategory(SlideCategoryType category) =>
      _baseConversationItemCount((conversation, owner, circle) =>
              _conversationPredicateByCategory(category, conversation, owner))
          .getSingle();

  Future<List<ConversationItem>> conversationItemsByCategory(
    SlideCategoryType category,
    int limit,
    int offset,
  ) =>
      _baseConversationItems(
        (conversation, owner, message, lastMessageSender, snapshot,
                participant) =>
            _conversationPredicateByCategory(category, conversation, owner),
        Limit(limit, offset),
      ).get();

  Selectable<ConversationItem> unseenConversationByCategory(
          SlideCategoryType category) =>
      _baseConversationItems(
        (conversation, owner, message, lastMessageSender, snapshot,
                participant) =>
            _conversationPredicateByCategory(category, conversation, owner) &
            conversation.unseenMessageCount.isBiggerThanValue(0),
        maxLimit,
      );

  Future<bool> _conversationHasData(Expression<bool> predicate) => db.hasData(
      db.conversations,
      [
        innerJoin(db.users, db.conversations.ownerId.equalsExp(db.users.userId),
            useColumns: false)
      ],
      predicate);

  Selectable<BaseUnseenConversationCountResult> _baseUnseenConversationCount(
          Expression<bool> Function(Conversations conversation, Users owner)
              where) =>
      db.baseUnseenConversationCount((conversation, owner) =>
          conversation.unseenMessageCount.isBiggerThanValue(0) &
          where(conversation, owner));

  Selectable<BaseUnseenConversationCountResult>
      unseenConversationCountByCategory(SlideCategoryType category) =>
          _baseUnseenConversationCount((conversation, owner) =>
              _conversationPredicateByCategory(category, conversation, owner));

  Selectable<ConversationItem> conversationItem(String conversationId) =>
      _baseConversationItems(
        (conversation, _, __, ___, ____, ______) =>
            conversation.conversationId.equals(conversationId),
        Limit(1, null),
      );

  Selectable<ConversationItem> conversationItems() => _baseConversationItems(
        (conversation, _, __, ___, ____, ______) =>
            conversation.category.isIn(['CONTACT', 'GROUP']) &
            conversation.status.equalsValue(ConversationStatus.success),
        maxLimit,
      );

  Selectable<int> conversationsCountByCircleId(String circleId) =>
      _baseConversationItemCount((_, __, circleConversation) =>
          circleConversation.circleId.equals(circleId));

  Selectable<ConversationItem> conversationsByCircleId(
          String circleId, int limit, int offset) =>
      db.baseConversationItemsByCircleId(
        (conversation, o, circleConversation, lm, ls, s, p, em) =>
            circleConversation.circleId.equals(circleId),
        (conversation, _, __, ___, ____, _____, _____i, em) =>
            _baseConversationItemOrder(conversation),
        (_, __, ___, ____, ______, _______, ________, em) =>
            Limit(limit, offset),
      );

  Future<bool> conversationHasDataByCircleId(String circleId) => db.hasData(
      db.circleConversations,
      [
        innerJoin(
          db.conversations,
          db.circleConversations.conversationId
              .equalsExp(db.conversations.conversationId),
          useColumns: false,
        )
      ],
      db.circleConversations.circleId.equals(circleId));

  Selectable<ConversationItem> unseenConversationsByCircleId(String circleId) =>
      db.baseConversationItemsByCircleId(
        (conversation, o, circleConversation, lm, ls, s, p, em) =>
            circleConversation.circleId.equals(circleId) &
            conversation.unseenMessageCount.isBiggerThanValue(0),
        (conversation, _, __, ___, ____, _____, _____i, em) =>
            _baseConversationItemOrder(conversation),
        (_, __, ___, ____, ______, _______, ________, em) => maxLimit,
      );

  Future<int> pin(String conversationId) => (update(db.conversations)
            ..where((tbl) => tbl.conversationId.equals(conversationId)))
          .write(
        ConversationsCompanion(pinTime: Value(DateTime.now())),
      );

  Future<int> unpin(String conversationId) async => (update(db.conversations)
            ..where((tbl) => tbl.conversationId.equals(conversationId)))
          .write(
        const ConversationsCompanion(pinTime: Value(null)),
      );

  Future<int> deleteConversation(String conversationId) =>
      (delete(db.conversations)
            ..where((tbl) => tbl.conversationId.equals(conversationId)))
          .go();

  Future<int> updateConversationStatusById(
      String conversationId, ConversationStatus status) async {
    final already = await db.hasData(
        db.conversations,
        [],
        db.conversations.conversationId.equals(conversationId) &
            db.conversations.status
                .equals(const ConversationStatusTypeConverter().toSql(status))
                .not());
    if (already) return -1;
    return (db.update(db.conversations)
          ..where((tbl) =>
              tbl.conversationId.equals(conversationId) &
              tbl.status
                  .equals(const ConversationStatusTypeConverter().toSql(status))
                  .not()))
        .write(ConversationsCompanion(status: Value(status)));
  }

  Selectable<SearchConversationItem> fuzzySearchConversation(
    String query,
    int limit, {
    bool filterUnseen = false,
    SlideCategoryState? category,
  }) {
    if (category?.type == SlideCategoryType.circle) {
      return db.fuzzySearchConversationInCircle(
        query.trim().escapeSql(),
        category!.id,
        (conversation, owner, message, cc) => filterUnseen
            ? conversation.unseenMessageCount.isBiggerThanValue(0)
            : ignoreWhere,
        (conversation, owner, message, cc) => Limit(limit, null),
      );
    }
    return db.fuzzySearchConversation(query.trim().escapeSql(),
        (Conversations conversation, Users owner, Messages message) {
      Expression<bool> predicate = ignoreWhere;
      switch (category?.type) {
        case SlideCategoryType.contacts:
        case SlideCategoryType.groups:
        case SlideCategoryType.bots:
        case SlideCategoryType.strangers:
          predicate = _conversationPredicateByCategory(
              category!.type, conversation, owner);
          break;

        case SlideCategoryType.circle:
        case SlideCategoryType.setting:
          assert(false, 'Invalid category type: ${category!.type}');
          break;
        case null:
        case SlideCategoryType.chats:
          break;
      }
      if (filterUnseen) {
        predicate &= conversation.unseenMessageCount.isBiggerThanValue(0);
      }
      return predicate;
    },
        (Conversations conversation, Users owner, Messages message) =>
            Limit(limit, null));
  }

  Selectable<String?> announcement(String conversationId) =>
      (db.selectOnly(db.conversations)
            ..addColumns([db.conversations.announcement])
            ..where(db.conversations.conversationId.equals(conversationId))
            ..limit(1))
          .map((row) => row.read(db.conversations.announcement));

  Selectable<ConversationStorageUsage> conversationStorageUsage() =>
      db.conversationStorageUsage();

  Future<void> updateConversation(
      ConversationResponse conversation, String currentUserId) {
    var ownerId = conversation.creatorId;
    if (conversation.category == ConversationCategory.contact) {
      ownerId = conversation.participants
          .firstWhere((e) => e.userId != currentUserId)
          .userId;
    }
    return db.transaction(() async {
      await Future.wait([
        insert(
          ConversationsCompanion(
            conversationId: Value(conversation.conversationId),
            ownerId: Value(ownerId),
            category: Value(conversation.category),
            name: Value(conversation.name),
            iconUrl: Value(conversation.iconUrl),
            announcement: Value(conversation.announcement),
            codeUrl: Value(conversation.codeUrl),
            createdAt: Value(conversation.createdAt),
            status: const Value(ConversationStatus.success),
            muteUntil: Value(DateTime.tryParse(conversation.muteUntil)),
            expireIn: Value(conversation.expireIn),
          ),
        ),
        ...conversation.participants.map(
          (participant) => db.participantDao.insert(
            Participant(
              conversationId: conversation.conversationId,
              userId: participant.userId,
              createdAt: participant.createdAt ?? DateTime.now(),
              role: participant.role,
            ),
          ),
        ),
        ...(conversation.participantSessions ?? [])
            .map((p) => db.participantSessionDao.insert(
                  ParticipantSessionData(
                    conversationId: conversation.conversationId,
                    userId: p.userId,
                    sessionId: p.sessionId,
                    publicKey: p.publicKey,
                  ),
                ))
      ]);
    });
  }

  Future<int> updateCodeUrl(String conversationId, String codeUrl) async {
    final already = await db.hasData(
        db.conversations,
        [],
        db.conversations.conversationId.equals(conversationId) &
            db.conversations.codeUrl.equals(codeUrl));
    if (already) return -1;
    return (update(db.conversations)
          ..where((tbl) => tbl.conversationId.equals(conversationId)))
        .write(ConversationsCompanion(codeUrl: Value(codeUrl)));
  }

  Future<int> updateMuteUntil(String conversationId, String muteUntil) =>
      (update(db.conversations)
            ..where((tbl) => tbl.conversationId.equals(conversationId)))
          .write(ConversationsCompanion(
              muteUntil: Value(DateTime.tryParse(muteUntil))));

  Future<int> updateDraft(String conversationId, String draft) async {
    final already = await db.hasData(
        db.conversations,
        [],
        db.conversations.conversationId.equals(conversationId) &
            db.conversations.draft.equals(draft));

    if (already) return -1;

    return (update(db.conversations)
          ..where((tbl) => tbl.conversationId.equals(conversationId)))
        .write(ConversationsCompanion(draft: Value(draft)));
  }

  Future<bool> hasConversation(String conversationId) => db.hasData(
        db.conversations,
        [],
        db.conversations.conversationId.equals(conversationId),
      );

  Selectable<GroupMinimal> findTheSameConversations(
          String selfId, String userId) =>
      db.findSameConversations(selfId, userId);

  Future<int> updateConversationExpireIn(String conversationId, int expireIn) =>
      (update(db.conversations)
            ..where((tbl) => tbl.conversationId.equals(conversationId)))
          .write(ConversationsCompanion(expireIn: Value(expireIn)));

  Future<EncryptCategory> getEncryptCategory(
      String ownerId, bool isBotConversation) async {
    final app = await db.appDao.findAppById(ownerId);
    if (app != null && app.isEncrypted) {
      return EncryptCategory.encrypted;
    }
    return isBotConversation ? EncryptCategory.plain : EncryptCategory.signal;
  }
}
