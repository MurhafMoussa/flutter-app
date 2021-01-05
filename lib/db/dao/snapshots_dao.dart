import 'package:flutter_app/db/mixin_database.dart';
import 'package:moor/moor.dart';

part 'snapshots_dao.g.dart';

@UseDao(tables: [Snapshots])
class SnapshotsDao extends DatabaseAccessor<MixinDatabase>
    with _$SnapshotsDaoMixin {
  SnapshotsDao(MixinDatabase db) : super(db);
}
