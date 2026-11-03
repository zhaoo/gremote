import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/darkroom/lut/lut_library.dart';
import 'package:gremote/darkroom/model/edit_document.dart';
import 'package:gremote/darkroom/model/export_recipe.dart';
import 'package:gremote/darkroom/model/photo_edits.dart';
import 'package:gremote/features/darkroom/editor/editor_controller.dart';
import 'package:gremote/features/darkroom/editor/editor_page.dart';
import '../support/fake_media_gateway.dart';
import '../support/test_darkroom.dart';

final official = 'official:69:default:${'a' * 64}';
final otherOfficial = 'official:70:default:${'b' * 64}';

class _SelectionLibrary extends LutLibrary {
  _SelectionLibrary(TestDarkroom env, this.catalog)
      : super(
            store: env.store, engine: env.engine, dataDir: () async => env.dir);
  final Future<List<LutEntry>> catalog;
  @override
  Future<List<LutEntry>> entries() => catalog;
  @override
  Future<Uint8List> load(String id) async => Uint8List.fromList([1, 2, 3]);
}

void main() {
  Future<(TestDarkroom, ProviderContainer)> setup(
      WidgetTester tester, String? requested, Future<List<LutEntry>> entries,
      {bool readyFirst = false}) async {
    final env = await TestDarkroom.create(
        gateway:
            FakeMediaGateway(entries: [mediaEntry(3)], exif: {3: grMeta()}));
    await env.store.saveEdit(EditDocument(
        mediaId: 3,
        updatedAt: DateTime(2026),
        recipe: ExportRecipe(
            lutId: 'builtin:pale',
            edits:
                const PhotoEdits().withValue(PhotoAdjustment.exposure, .35))));
    final c = ProviderContainer(overrides: [
      ...env.overrides,
      lutLibraryProvider.overrideWithValue(_SelectionLibrary(env, entries))
    ]);
    await c.read(localMediaRepositoryProvider).scan().drain<void>();
    if (readyFirst) {
      c.listen(editorProvider(3), (_, __) {});
      await tester.pumpAndSettle();
      expect(c.read(editorProvider(3)).doc, isNotNull);
      expect(c.read(editorProvider(3)).luts, isNotEmpty);
    }
    addTearDown(() async {
      c.dispose();
      await env.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child:
            MaterialApp(home: EditorPage(mediaId: 3, initialLut: requested))));
    await tester.pumpAndSettle();
    return (env, c);
  }

  testWidgets(
      'explicit official LUT waits for catalog and applies once with history',
      (tester) async {
    final entries = Completer<List<LutEntry>>();
    final (_, c) = await setup(tester, official, entries.future);
    final editor = c.read(editorProvider(3).notifier);
    expect(c.read(editorProvider(3)).recipe.lutId, 'builtin:pale');
    entries.complete([
      LutEntry(
          id: official,
          name: '官网胶卷',
          size: 15,
          imported: false,
          official: true),
      LutEntry(
          id: otherOfficial,
          name: '另一胶卷',
          size: 15,
          imported: false,
          official: true),
    ]);
    await tester.pumpAndSettle();
    expect(c.read(editorProvider(3)).recipe.lutId, official);
    expect(
        c.read(editorProvider(3)).recipe.edits.value(PhotoAdjustment.exposure),
        .35);
    expect(c.read(editorProvider(3)).canUndo, isTrue);
    editor.undo();
    await tester.pumpAndSettle();
    expect(c.read(editorProvider(3)).recipe.lutId, 'builtin:pale');
    await editor.setLut(otherOfficial);
    await tester.pumpAndSettle();
    editor.setTitle('a later rebuild');
    await tester.pumpAndSettle();
    expect(c.read(editorProvider(3)).recipe.lutId, otherOfficial);
  });

  testWidgets('initial selection works with an already loaded controller',
      (tester) async {
    final (_, c) = await setup(
        tester,
        official,
        Future.value([
          LutEntry(
              id: official,
              name: '官网胶卷',
              size: 15,
              imported: false,
              official: true),
        ]),
        readyFirst: true);
    expect(c.read(editorProvider(3)).recipe.lutId, official);
  });

  testWidgets('leaving before catalog loads cannot apply the pending selection',
      (tester) async {
    final entries = Completer<List<LutEntry>>();
    final (_, c) = await setup(tester, official, entries.future);
    c.listen(editorProvider(3), (_, __) {});
    await tester.pumpWidget(const SizedBox());
    entries.complete([
      LutEntry(
          id: official,
          name: '官网胶卷',
          size: 15,
          imported: false,
          official: true),
    ]);
    await tester.pumpAndSettle();
    expect(c.read(editorProvider(3)).recipe.lutId, 'builtin:pale');
    expect(tester.takeException(), isNull);
  });

  for (final requested in <String?>[
    null,
    'builtin:pale',
    'file:///private/film.cube',
    'official:0:default:${'a' * 64}',
    'official:69:default:${'a' * 64}\n',
    otherOfficial
  ]) {
    testWidgets(
        'missing invalid or unknown initial LUT preserves saved edit: $requested',
        (tester) async {
      final (_, c) = await setup(
          tester,
          requested,
          Future.value([
            LutEntry(
                id: official,
                name: '官网胶卷',
                size: 15,
                imported: false,
                official: true),
          ]));
      expect(c.read(editorProvider(3)).recipe.lutId, 'builtin:pale');
      expect(c.read(editorProvider(3)).canUndo, isFalse);
    });
  }

  testWidgets('matching ID without official provenance is not applied',
      (tester) async {
    final (_, c) = await setup(
        tester,
        official,
        Future.value([
          LutEntry(id: official, name: '导入胶卷', size: 15, imported: true),
        ]));
    expect(c.read(editorProvider(3)).recipe.lutId, 'builtin:pale');
    expect(c.read(editorProvider(3)).canUndo, isFalse);
  });
}
