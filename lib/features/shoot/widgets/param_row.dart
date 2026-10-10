import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../camera/params/camera_param.dart';
import '../../../camera/sync/camera_state.dart';

const _params = <(ParamKey, String)>[
  (ParamKey.whiteBalance, 'WB'),
  (ParamKey.aperture, 'F'),
  (ParamKey.shutter, 'S'),
  (ParamKey.iso, 'ISO'),
  (ParamKey.exposureComp, 'EV'),
  (ParamKey.metering, '测光'),
];

class CameraParamRow extends StatelessWidget {
  const CameraParamRow({
    required this.state,
    required this.onSelected,
    super.key,
  });

  final CameraState state;
  final ValueChanged<CameraParam> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: Row(children: [
          for (final (key, label) in _params)
            Expanded(child: _item(context, key, label)),
        ]),
      );

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
            style: const TextStyle(color: GRemoteColors.muted, fontSize: 9)),
        const SizedBox(height: 2),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(
            child: Text(param?.current ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: enabled ? GRemoteColors.text : GRemoteColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
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
