import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../shoot_mode.dart';

class DriveOptions extends StatelessWidget {
  const DriveOptions({required this.mode, required this.onProgram, super.key});

  final ShootMode mode;
  final ValueChanged<String> onProgram;

  @override
  Widget build(BuildContext context) {
    final options = mode == ShootMode.bracket
        ? const [
            ('原生包围', 'nativeBracket'),
            ('自定义包围', 'customBracket'),
            ('配方包围', 'recipeBracket')
          ]
        : const [
            ('原生间隔', 'nativeInterval'),
            ('计划渐变', 'plannedRamp'),
            ('测光渐变', 'meteredRamp')
          ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, index) {
          final option = options[index];
          return ActionChip(
            label: Text('${option.$1}${index == 0 ? '' : ' · 手机'}',
                style: const TextStyle(fontSize: 10)),
            onPressed: () => onProgram(option.$2),
            backgroundColor: GRemoteColors.raised,
            side: const BorderSide(color: GRemoteColors.divider),
          );
        },
      ),
    );
  }
}
