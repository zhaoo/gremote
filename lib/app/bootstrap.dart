import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../darkroom/darkroom_providers.dart';
import '../storage/gremote_database.dart';
import 'app.dart';
import '../settings/preferences_repository.dart';
import '../settings/preferences_controller.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  final db = await GRemoteDatabase.open();
  final preferences = await PreferencesRepository(db).hydrate();
  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      initialPreferencesProvider.overrideWithValue(preferences),
    ],
    child: const GRemoteApp(),
  ));
}
