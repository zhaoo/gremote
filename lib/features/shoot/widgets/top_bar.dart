import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

class ShootTopBar extends StatelessWidget {
  const ShootTopBar({
    required this.exposureMode,
    required this.onBack,
    required this.onRecipe,
    required this.onTimer,
    required this.onHistogram,
    required this.onSettings,
    required this.histogram,
    required this.recipeDetached,
    super.key,
  });

  final String exposureMode;
  final VoidCallback onBack;
  final VoidCallback onRecipe;
  final VoidCallback onTimer;
  final VoidCallback onHistogram;
  final VoidCallback onSettings;
  final bool histogram;
  final bool recipeDetached;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 350;
          return Row(children: [
            IconButton(
              onPressed: onBack,
              constraints: const BoxConstraints.tightFor(width: 38, height: 40),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back_ios_new, size: 19),
              tooltip: '返回首页',
            ),
            Text(exposureMode,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const Spacer(),
            if (!compact) _topButton('⚡', null),
            if (!compact) _topButton('HDR', null, small: true),
            _topButton('⏱', onTimer),
            Stack(clipBehavior: Clip.none, children: [
              _topButton('◍', onRecipe, key: const Key('recipe-toggle')),
              if (recipeDetached)
                const Positioned(
                  right: 5,
                  top: 5,
                  child: CircleAvatar(
                      radius: 3, backgroundColor: GRemoteColors.danger),
                ),
            ]),
            _topButton(histogram ? '▥' : '▦', onHistogram),
            IconButton(
              onPressed: onSettings,
              constraints: const BoxConstraints.tightFor(width: 38, height: 40),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.menu, size: 20),
              tooltip: '设置',
            ),
          ]);
        }),
      );

  Widget _topButton(String label, VoidCallback? onTap,
          {bool small = false, Key? key}) =>
      SizedBox(
        width: small ? 39 : 34,
        child: TextButton(
          key: key,
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            foregroundColor: GRemoteColors.text,
          ),
          child: Text(label,
              style: TextStyle(fontSize: small ? 9 : 17, letterSpacing: 0)),
        ),
      );
}
