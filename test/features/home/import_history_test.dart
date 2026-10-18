import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gremote/features/home/import_history.dart';

void main() {
  CameraImportRecord entry(String name, DateTime time) => CameraImportRecord(
      uri: 'content://$name',
      name: name,
      mime: name.toLowerCase().endsWith('.dng')
          ? 'image/x-adobe-dng'
          : 'image/jpeg',
      dateAdded: time.millisecondsSinceEpoch ~/ 1000);

  test(
      'RAW JPG and repeated download copies count as one imported photo per day',
      () {
    final photos = groupCameraImports([
      entry('R001.JPG', DateTime(2026, 10, 18, 9)),
      entry('R001.DNG', DateTime(2026, 10, 18, 9, 1)),
      entry('R001_1.JPG', DateTime(2026, 10, 18, 10)),
      entry('R001 (2).JPG', DateTime(2026, 10, 18, 11)),
      entry('R002.JPG', DateTime(2026, 10, 18, 12)),
      entry('R001.JPG', DateTime(2026, 10, 17, 23, 59)),
    ]);
    expect(photos.length, 3);
    expect(countTodayImports(photos, DateTime(2026, 10, 18)), 2);
    expect(photos[1].formats, {'JPG', 'RAW'});
    expect(photos[1].importedAt, DateTime(2026, 10, 18, 11));
  });

  test('today means local import day and history is sorted newest first', () {
    final photos = groupCameraImports([
      entry('R001.JPG', DateTime(2026, 10, 17, 23, 59)),
      entry('R002.JPG', DateTime(2026, 10, 18, 0, 1)),
    ]);
    expect(countTodayImports(photos, DateTime(2026, 10, 18, 23)), 1);
    expect(photos.first.name, 'R002');
  });

  testWidgets(
      'tile opens paired history and read failures offer retry instead of zero',
      (tester) async {
    const channel = MethodChannel('gremote/import_history');
    var failed = true;
    var cleared = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (failed) throw PlatformException(code: 'queryFailed');
      if (cleared) return [];
      final added = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return [
        {
          'uri': 'content://1',
          'name': 'R001.JPG',
          'mime': 'image/jpeg',
          'dateAdded': added
        },
        {
          'uri': 'content://2',
          'name': 'R001.DNG',
          'mime': 'image/x-adobe-dng',
          'dateAdded': added
        },
      ];
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ImportStatusTile()))));
    await tester.pumpAndSettle();
    expect(find.text('读取失败'), findsOneWidget);
    expect(find.text('0 张'), findsNothing);
    await tester.tap(find.text('今日导入'));
    await tester.pumpAndSettle();
    expect(find.text('导入历史'), findsOneWidget);
    failed = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('R001'), findsOneWidget);
    expect(find.text('RAW+JPG'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 张'), findsOneWidget);
    cleared = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('0 张'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
