import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../shoot_mode.dart';

class ModeCarousel extends StatelessWidget {
  const ModeCarousel({
    required this.mode,
    required this.onChanged,
    this.locked = false,
    super.key,
  });

  final ShootMode mode;
  final ValueChanged<ShootMode> onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 38,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final item in ShootMode.values)
              SizedBox(
                width: 56,
                child: TextButton(
                  key: Key('mode-${item.name}'),
                  onPressed: locked ? null : () => onChanged(item),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor:
                        item == mode ? GRemoteColors.gold : GRemoteColors.muted,
                  ),
                  child: Text(item.label,
                      style: TextStyle(
                        fontSize: item == mode ? 14 : 12,
                        fontWeight:
                            item == mode ? FontWeight.w700 : FontWeight.w400,
                      )),
                ),
              ),
          ],
        ),
      );
}
