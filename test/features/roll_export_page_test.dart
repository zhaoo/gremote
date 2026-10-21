import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/model/film_roll.dart';
import 'package:gremote/features/film_workbench/roll_export_page.dart';
import '../support/fake_media_gateway.dart';

void main() {
  testWidgets('empty roll exports no fake photos but can share its real recipe',
      (tester) async {
    final gateway = FakeMediaGateway();
    final recipe = FilmCatalog.fromJson(
            jsonDecode(File('assets/films/catalog.json').readAsStringSync())
                as Map<String, dynamic>)
        .recipe(33);
    final roll = FilmRoll(
        id: 'r',
        name: '空胶卷',
        targetCount: 36,
        recipeFingerprint: recipe.fingerprint,
        status: FilmRollStatus.open,
        createdAt: DateTime(2026));
    await tester.pumpWidget(ProviderScope(
        overrides: [mediaGatewayProvider.overrideWithValue(gateway)],
        child: MaterialApp(
            theme: GRemoteTheme.dark,
            home:
                RollExportPage(roll: roll, items: const [], recipe: recipe))));
    expect(find.text('0 张照片 · 0 张精选'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存联系印样'))
            .onPressed,
        isNull);
    await tester.tap(find.text('分享配方卡'));
    await tester.pump();
    expect(gateway.recipeCards, hasLength(1));
    expect(gateway.generated, isEmpty);
  });
}
