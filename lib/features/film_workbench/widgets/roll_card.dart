import 'package:flutter/material.dart';
import '../../../film/model/film_roll.dart';
import 'workbench_style.dart';

class RollCard extends StatelessWidget {
  const RollCard(
      {super.key, required this.roll, required this.onTap, this.cover});
  final FilmRoll roll;
  final VoidCallback onTap;
  final Widget? cover;
  @override
  Widget build(BuildContext context) => Card(
      color: workbenchSurface,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 16),
      child: InkWell(
          onTap: onTap,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (cover != null)
              SizedBox(height: 150, width: double.infinity, child: cover),
            Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(roll.name,
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    color: workbenchCream))),
                        const Icon(Icons.arrow_forward_rounded,
                            size: 20, color: workbenchGold)
                      ]),
                      const SizedBox(height: 10),
                      Text(
                          '${roll.confirmedCount} / ${roll.targetCount} 张 · ${roll.status == FilmRollStatus.open ? '拍摄中' : '已结束'}',
                          style: const TextStyle(
                              color: workbenchMuted, fontSize: 12)),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                          value: (roll.confirmedCount / roll.targetCount)
                              .clamp(0, 1),
                          backgroundColor: const Color(0xff354136),
                          color: workbenchGold,
                          minHeight: 2),
                    ])),
          ])));
}
