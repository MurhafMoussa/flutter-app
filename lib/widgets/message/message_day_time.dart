import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../brightness_observer.dart';

class MessageDayTime extends StatelessWidget {
  const MessageDayTime({
    Key? key,
    required this.dateTime,
  }) : super(key: key);

  final DateTime dateTime;

  @override
  Widget build(BuildContext context) => Container(
    height: 60,
    alignment: Alignment.center,
    child: Container(
      height: 22,
      width: 90,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: BrightnessData.themeOf(context).dateTime,
      ),
      alignment: Alignment.center,
      child: Text(
        DateFormat.MEd().format(dateTime),
      ),
    ),
  );
}

