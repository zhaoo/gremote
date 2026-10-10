import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App is resumed or only momentarily inactive (not paused / hidden).
final appForegroundProvider = StateProvider<bool>((_) => true);

/// The shoot tab is the selected shell branch.
final shootPageVisibleProvider = StateProvider<bool>((_) => false);
