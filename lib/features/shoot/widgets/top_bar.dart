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
  final String? exposureMode;
  final VoidCallback onBack, onRecipe, onSettings;
  final bool recipeDetached;

  static final _buttonStyle = IconButton.styleFrom(
    minimumSize: const Size(44, 48),
    maximumSize: const Size(44, 48),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

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
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: exposureMode == null
                      ? null
                      : Text(shootValueLabel('exposureMode', exposureMode!),
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: context.palette.muted)),
                ),
              ),
              Stack(clipBehavior: Clip.none, children: [
                IconButton(
                    key: const Key('recipe-toggle'),
                    tooltip: '组合方案',
                    style: _buttonStyle,
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
                  style: _buttonStyle,
                  icon: const Icon(Icons.tune, size: 20)),
            ])),
      );
}
