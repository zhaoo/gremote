import 'package:flutter/material.dart';

const workbenchBackground = Color(0xff0b100d);
const workbenchSurface = Color(0xff19211b);
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
        Text(eyebrow,
            style: const TextStyle(
                color: workbenchGold, fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: workbenchCream))),
          if (action != null) action!
        ]),
        const SizedBox(height: 7),
        Text(subtitle,
            style: const TextStyle(color: workbenchMuted, fontSize: 12)),
      ]));
}

AnimationStyle workbenchSheetAnimation(BuildContext context) =>
    MediaQuery.of(context).disableAnimations
        ? AnimationStyle.noAnimation
        : AnimationStyle(
            duration: const Duration(milliseconds: 280),
            reverseDuration: const Duration(milliseconds: 200));
