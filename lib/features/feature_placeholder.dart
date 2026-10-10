import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';

class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({
    required this.title,
    required this.kicker,
    required this.headline,
    required this.description,
    required this.icon,
    super.key,
  });

  final String title;
  final String kicker;
  final String headline;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 25, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                const Text('GRemote',
                    style: TextStyle(
                        color: GRemoteColors.gold,
                        fontFamily: 'Georgia',
                        fontSize: 17)),
              ]),
              const SizedBox(height: 6),
              Text(kicker,
                  style: const TextStyle(
                      color: GRemoteColors.gold,
                      fontSize: 10,
                      letterSpacing: 2.2)),
              const SizedBox(height: 40),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: GRemoteColors.navy,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GRemoteColors.divider),
                  ),
                  child: Stack(children: [
                    const Positioned(
                      top: 20,
                      left: 20,
                      child: Text('GREMOTE / 001',
                          style: TextStyle(
                              color: GRemoteColors.muted,
                              fontFamily: 'monospace',
                              fontSize: 10,
                              letterSpacing: 1.4)),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: GRemoteColors.divider),
                                ),
                                child: Icon(icon,
                                    size: 34, color: GRemoteColors.goldSoft),
                              ),
                              const SizedBox(height: 26),
                              Text(headline,
                                  textAlign: TextAlign.center,
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 10),
                              Text(description,
                                  textAlign: TextAlign.center,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      bottom: 20,
                      right: 20,
                      child: Text('FRAME THE EVERYDAY',
                          style: TextStyle(
                              color: GRemoteColors.muted,
                              fontSize: 9,
                              letterSpacing: 1.5)),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      );
}
