import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

class MoreGrid extends StatelessWidget {
  const MoreGrid({required this.onProbe, super.key});

  final VoidCallback onProbe;

  @override
  Widget build(BuildContext context) => Container(
        color: GRemoteColors.navy,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('工具',
              style: TextStyle(color: GRemoteColors.muted, fontSize: 11)),
          const SizedBox(height: 8),
          InkWell(
            onTap: onProbe,
            borderRadius: BorderRadius.circular(12),
            child: const SizedBox(
              width: 76,
              height: 66,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.manage_search_outlined, color: GRemoteColors.gold),
                    SizedBox(height: 5),
                    Text('协议探测', style: TextStyle(fontSize: 10)),
                  ]),
            ),
          ),
        ]),
      );
}
