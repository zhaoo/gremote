// Opt-in Flutter rendering evidence. Not camera or phone verification.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/connection/connection_state.dart';
import 'package:gremote/camera/gateway/ble_gateway.dart';
import 'package:gremote/camera/model/camera_identity.dart';
import 'package:gremote/camera/model/camera_snapshot.dart';
import 'package:gremote/features/camera/camera_page.dart';
import 'package:gremote/features/camera/film_library_page.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import 'package:gremote/features/home/home_page.dart';
import 'package:gremote/features/home/import_history.dart';
import 'package:gremote/features/home/widgets/camera_switcher.dart';
import '../support/test_darkroom.dart';

class _VisualConnection extends ConnectionController {
  _VisualConnection(this.model);
  final String model;
  @override
  CameraConnectionState build() => ConnectionReady(
        snapshot: CameraSnapshot(
            identity: CameraIdentity(
                model: model,
                firmware: model.contains('IIIx') ? '1.60' : '1.11'),
            battery: const CameraBattery(level: 87, acPowered: false)),
        firmwareWarning: true,
      );
}

void main() {
  testWidgets('capture multi-camera Flutter surfaces', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final chinese =
          File('/Library/Fonts/Alibaba-PuHuiTi-Regular.otf').readAsBytesSync();
      for (final family in [
        'VisualCN',
        'Roboto',
        'Ahem',
        'PingFang SC',
        'Noto Sans CJK SC'
      ]) {
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(chinese))))
            .load();
      }
      await (FontLoader('GRemoteEditorial')
            ..addFont(
                rootBundle.load('assets/fonts/gremote_editorial_serif.ttf')))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    final catalog = await tester.runAsync(() async =>
        CameraFilmCatalog.fromJson(jsonDecode(
                await rootBundle.loadString('assets/films/camera-catalog.json'))
            as Map<String, dynamic>));
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    final key = GlobalKey();
    Future<void> capture(String name, Widget child,
        {bool dark = false, String model = 'RICOH GR IIIx'}) async {
      await tester.pumpWidget(ProviderScope(
          key: ValueKey(name),
          overrides: [
            ...env.overrides,
            connectionControllerProvider
                .overrideWith(() => _VisualConnection(model)),
            companionHotspotPairingProvider.overrideWith((_) async => null),
            companionIdentityHydrationProvider.overrideWith((_) async {}),
            cameraFilmCatalogProvider.overrideWith((_) async => catalog!),
            officialFilmCacheProvider.overrideWith((_) async => null),
            importHistoryProvider.overrideWith((_) async => []),
          ],
          child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: (dark ? GRemoteTheme.dark : GRemoteTheme.light).copyWith(
                    textTheme: (dark ? GRemoteTheme.dark : GRemoteTheme.light)
                        .textTheme
                        .apply(fontFamily: 'VisualCN')),
                home: Scaffold(body: child),
              ))));
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('docs/design/2026-11-20-flutter-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('multicamera-home', const HomePage());
    await capture(
        'multicamera-switch',
        Align(
            alignment: Alignment.bottomCenter,
            child: CameraSwitcher(
              current:
                  _VisualConnection('RICOH GR IIIx').build() as ConnectionReady,
              discover: () async => const [
                BleDeviceCandidate(
                    id: 'demo-iv', name: 'RICOH GR IV', rssi: -40),
                BleDeviceCandidate(
                    id: 'demo-mono', name: 'RICOH GR IV Monochrome', rssi: -55)
              ],
              onManualWifi: () {},
            )));
    await capture('multicamera-stock', const CameraPage(),
        dark: true, model: 'RICOH GR IV Monochrome');
    await tester.pumpWidget(const SizedBox());
  }, skip: !const bool.fromEnvironment('CAMERA_VISUALS'));
}
