import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/darkroom/export/export_queue.dart';
import 'package:gremote/darkroom/model/export_recipe.dart';
import 'package:gremote/features/library/batch_export_page.dart';
import 'package:gremote/imaging/imaging_exception.dart';
import 'package:gremote/media/local/local_media_repository.dart';

import '../support/test_darkroom.dart';

LocalMediaItem photo(int id) => LocalMediaItem(
    id: id,
    uri: 'u$id',
    displayName: 'R00$id.JPG',
    dateModified: 1,
    meta: grMeta().copyWith());

void main() {
  testWidgets('summarises results and retries failures', (tester) async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    env.engine.exportFailures[2] = ImagingErrorCode.tooLarge;
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides,
      child: MaterialApp(theme: GRemoteTheme.dark, home: const BatchExportPage()),
    ));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(BatchExportPage)));

    await tester.runAsync(() => container
        .read(exportQueueProvider.notifier)
        .start([photo(1), photo(2)], const ExportRecipe()));
    await tester.pump();

    expect(find.text('完成 1 · 失败 1 · 共 2'), findsOneWidget);
    expect(find.textContaining('R002.JPG · 读取失败（tooLarge）'), findsOneWidget);
    expect(find.textContaining('2560 或 1440'), findsOneWidget);
    expect(find.text('重试失败项 (1)'), findsOneWidget);

    env.engine.exportFailures.clear();
    await tester.runAsync(
        () => container.read(exportQueueProvider.notifier).retryFailed());
    await tester.pump();
    expect(find.text('完成 2 · 失败 0 · 共 2'), findsOneWidget);
    expect(find.textContaining('重试失败项'), findsNothing);
  });
}
