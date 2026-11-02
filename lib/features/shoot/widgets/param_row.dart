import 'package:flutter/material.dart';

import '../shoot_labels.dart';

import '../../../app/theme/app_colors.dart';
import '../../../camera/params/camera_param.dart';
import '../../../camera/sync/camera_state.dart';

const _params = <(ParamKey, String)>[
  (ParamKey.whiteBalance, '白平衡'),
  (ParamKey.aperture, '光圈'),
  (ParamKey.shutter, '快门'),
  (ParamKey.iso, '感光度'),
  (ParamKey.exposureComp, '补偿'),
  (ParamKey.metering, '测光'),
];

class CameraParamRow extends StatelessWidget {
  const CameraParamRow({
    required this.state,
    required this.onSelected,
    this.compact = false,
    super.key,
  });

  final CameraState state;
  final ValueChanged<CameraParam> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fontSize = compact ? 17.0 : 12.0;
    final scale = (MediaQuery.textScalerOf(context).scale(fontSize) / fontSize)
        .clamp(1.0, double.infinity);
    return SizedBox(
      height: (compact ? 66.0 : 56.0) * scale,
      child: Row(children: [
        for (final (key, label) in compact
            ? const [
                (ParamKey.shutter, '快门'),
                (ParamKey.aperture, '光圈'),
                (ParamKey.iso, 'ISO'),
                (ParamKey.exposureComp, '补偿')
              ]
            : _params)
          Expanded(child: _item(context, key, label)),
      ]),
    );
  }

  Widget _item(BuildContext context, ParamKey key, String label) {
    final param = state.param(key);
    final enabled = param?.writable == true;
    return InkWell(
      key: Key('param-${key.wireKey}'),
      onTap: param == null
          ? null
          : () {
              if (enabled) {
                onSelected(param);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('由机身决定')),
                );
              }
            },
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label,
            maxLines: 1,
            style: TextStyle(
                color: GRemoteColors.muted, fontSize: compact ? 11 : 10)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(
            child: Text(shootValueLabel(key.wireKey, param?.current),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: enabled ? GRemoteColors.text : GRemoteColors.muted,
                    fontSize: compact ? 17 : 12,
                    fontWeight: FontWeight.w400)),
          ),
          if (state.pending.containsKey(key.wireKey)) ...[
            const SizedBox(width: 3),
            const SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(strokeWidth: 1)),
          ],
        ]),
      ]),
    );
  }
}
