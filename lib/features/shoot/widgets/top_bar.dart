import 'package:flutter/material.dart';
import '../shoot_labels.dart';
import '../../../app/theme/app_colors.dart';

class ShootTopBar extends StatelessWidget {
  const ShootTopBar(
      {required this.exposureMode,
      required this.onBack,
      required this.onRecipe,
      required this.onSettings,
      required this.recipeDetached,
      super.key});
  final String exposureMode;
  final VoidCallback onBack, onRecipe, onSettings;
  final bool recipeDetached;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [
              IconButton(
                  onPressed: onBack,
                  tooltip: '返回首页',
                  icon: const Icon(Icons.chevron_left, size: 23)),
              const Expanded(
                  child: Text('GR III',
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500))),
              Flexible(
                  child: Text(shootValueLabel('exposureMode', exposureMode),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: context.palette.muted))),
              Stack(clipBehavior: Clip.none, children: [
                IconButton(
                    key: const Key('recipe-toggle'),
                    tooltip: '组合方案',
                    onPressed: onRecipe,
                    icon: const Icon(Icons.layers_outlined, size: 20)),
                if (recipeDetached)
                  Positioned(
                      right: 5,
                      top: 5,
                      child: CircleAvatar(
                          radius: 3, backgroundColor: context.palette.danger)),
              ]),
              IconButton(
                  onPressed: onSettings,
                  tooltip: '设置',
                  icon: const Icon(Icons.tune, size: 20)),
            ])),
      );
}
