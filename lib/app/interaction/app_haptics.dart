import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/preferences_controller.dart';

final appHapticsProvider = Provider<AppHaptics>((ref) => AppHaptics(
    enabled: () => ref.read(appPreferencesProvider).preferences.haptics));

class AppHaptics {
  AppHaptics({required bool Function() enabled}) : _enabled = enabled;
  final bool Function() _enabled;

  /// Platform feedback still respects the device's system haptic policy.
  Future<void> selection() async {
    if (_enabled()) await HapticFeedback.selectionClick();
  }
}
