import 'package:flutter/material.dart';

import '../shoot_labels.dart';

import '../../../app/theme/app_colors.dart';
import '../../../camera/params/camera_param.dart';

class ParamRuler extends StatelessWidget {
  const ParamRuler({
    required this.param,
    required this.onChanged,
    required this.onClose,
    super.key,
  });

  final CameraParam param;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('ruler'),
        height: 48,
        color: const Color(0xF20C100E),
        child: Row(children: [
          IconButton(
              onPressed: onClose, icon: const Icon(Icons.close, size: 17)),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: param.options.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (_, index) {
                final value = param.options[index];
                final selected = value == param.current;
                return TextButton(
                  key: value == 'auto' ? const Key('ruler-auto') : null,
                  onPressed: () => onChanged(value),
                  child: Text(shootValueLabel(param.wireKey, value),
                      style: TextStyle(
                        color:
                            selected ? GRemoteColors.gold : GRemoteColors.text,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400,
                      )),
                );
              },
            ),
          ),
        ]),
      );
}
