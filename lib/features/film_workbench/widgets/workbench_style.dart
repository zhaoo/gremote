import 'package:flutter/material.dart';

const workbenchBackground = Color(0xff101214);
const workbenchSurface = Color(0xff1b1e21);
const workbenchGold = Color(0xffd2b577);
const workbenchCream = Color(0xfff0eee5);
const workbenchMuted = Color(0xffa4afa4);

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
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: workbenchCream))),
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
