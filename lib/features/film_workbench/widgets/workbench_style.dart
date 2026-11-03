export '../../../app/theme/app_palette.dart';

import '../../../app/theme/app_palette.dart';
import 'package:flutter/material.dart';

class WorkbenchHeading extends StatelessWidget {
  const WorkbenchHeading(this.title, this.subtitle, this.eyebrow,
      {super.key, this.action});
  final String title, subtitle, eyebrow;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: context.palette.text))),
          if (action != null) action!
        ]),
      ]));
}

AnimationStyle workbenchSheetAnimation(BuildContext context) =>
    MediaQuery.of(context).disableAnimations
        ? AnimationStyle.noAnimation
        : AnimationStyle(
            duration: const Duration(milliseconds: 280),
            reverseDuration: const Duration(milliseconds: 200));
