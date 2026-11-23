import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/camera_roll_index.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/camera/http/camera_api.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/features/library/camera_gallery.dart';
import 'package:gremote/platform/device_api.g.dart';

const id = '0102030405060708090a0b0c0d0e0f10';
const latestRoll = CameraIndexedRoll(
    id: id,
    filmId: 66,
    target: 36,
    journalCount: 0,
    status: CameraRollStatus.closed,
    isLatest: true);

class _Api implements CameraRollIndexApi {
  final firstPage = Completer<CameraRollIndexPage>();
  CameraIndexedRoll? roll = latestRoll;
  int requests = 0;
  @override
  Future<CameraIndexedRoll?> latest() async => roll;
  @override
  Future<CameraRollIndexPage> photos(int cursor) {
    requests++;
    return firstPage.future;
  }
}

class _PagedApi implements CameraRollIndexApi {
  final cursors = <int>[];
  @override
  Future<CameraIndexedRoll?> latest() async => const CameraIndexedRoll(
      id: id,
      filmId: 66,
      target: 36,
      journalCount: 2,
      status: CameraRollStatus.closed,
      isLatest: true);
  @override
  Future<CameraRollIndexPage> photos(int cursor) async {
    cursors.add(cursor);
    if (cursor == 0)
      return const CameraRollIndexPage([], 65537, true, false, 16, 0);
    return const CameraRollIndexPage([
      CameraIndexedPhoto(
          file: CameraFile(dir: '100RICOH', file: '00000017.JPG'),
          rollId: id,
          frame: 1,
          target: 36),
      CameraIndexedPhoto(
          file: CameraFile(dir: '100RICOH', file: '00000018.JPG'),
          rollId: id,
          frame: 2,
          target: 36),
    ], 0, false, false, 18, 0);
  }
}

void main() {
  test('verified JPEG and RAW originals remain available with JPEG first', () {
    final wire = <String, dynamic>{
      'id': id,
      'target': 36,
      'frame': 1,
      'filmCode': 0x1042,
      'directory': '141_1122',
      'file': '00004562.DNG'
    };
    final raw = CameraIndexedPhoto.parse(wire);
    final jpg = CameraIndexedPhoto.parse({...wire, 'file': '00004562.JPG'});
    expect(
        mergeCameraRollPhotos([latestRoll], [raw])
            .single
            .photos
            .single
            .file
            .extension,
        'DNG');
    for (final photos in [
      [raw, jpg],
      [jpg, raw]
    ]) {
      final roll = mergeCameraRollPhotos([latestRoll], photos).single;
      expect(roll.photos.map((p) => p.file.extension), ['JPG', 'DNG']);
      expect(mergeCameraRollPhotos([roll], photos).single.photos.length, 2);
      expect(roll.verifiedPhotoCount, 1);
    }
  });

  test('latest closed zero-photo roll remains valid without downloaded JPEG',
      () {
    final roll = CameraIndexedRoll.parseLatest({
      'id': id,
      'sequence': 3,
      'filmId': 66,
      'target': 36,
      'count': 0,
      'status': 3
    });
    expect(roll.status, CameraRollStatus.closed);
    expect(roll.journalCount, 0);
    expect(roll.photos, isEmpty);
  });
  test('older markers group independently and do not invent historical status',
      () {
    const other = '11111111111111111111111111111111';
    const a = CameraIndexedPhoto(
        file: CameraFile(dir: '100RICOH', file: 'R0000001.JPG'),
        rollId: other,
        frame: 7,
        target: 24,
        filmCode: 0x1042);
    const b = CameraIndexedPhoto(
        file: CameraFile(dir: '100RICOH', file: 'R0000002.JPG'),
        rollId: other,
        frame: 9,
        target: 24,
        filmCode: 0x1042);
    final rolls = mergeCameraRollPhotos([latestRoll], [a, a, b]);
    expect(rolls.length, 2);
    expect(rolls.first.journalCount, 0);
    expect(rolls.last.status, isNull);
    expect(rolls.last.journalCount, isNull);
    expect(rolls.last.verifiedPhotoCount, 2);
    expect(rolls.last.filmId, 66);
    expect(rolls.last.photos.map((p) => p.frame), [7, 9]);
  });
  test(
      'malformed pagination, path injection and incompatible target are rejected',
      () {
    final wire = <String, dynamic>{
      'version': 1,
      'nextCursor': 0,
      'hasMore': false,
      'truncated': false,
      'checked': 1,
      'skipped': 0,
      'photos': []
    };
    expect(CameraRollIndexPage.parse(wire, 0).photos, isEmpty);
    expect(() => CameraRollIndexPage.parse({...wire, 'checked': 4097}, 0),
        throwsFormatException);
    expect(() => CameraRollIndexPage.parse({...wire, 'hasMore': true}, 0),
        throwsFormatException);
    expect(
        () => CameraIndexedPhoto.parse({
              'id': id,
              'target': 36,
              'frame': 1,
              'filmCode': 0,
              'directory': '../etc',
              'file': 'R0000001.JPG'
            }),
        throwsFormatException);
    expect(
        () => mergeCameraRollPhotos([
              latestRoll
            ], [
              const CameraIndexedPhoto(
                  file: CameraFile(dir: '100RICOH', file: 'R0000001.JPG'),
                  rollId: id,
                  frame: 1,
                  target: 24)
            ]),
        throwsFormatException);
  });
  test('journal publishes before scan; cancellation discards late page',
      () async {
    final api = _Api();
    final gateways = FakeCameraGateways();
    addTearDown(gateways.dispose);
    final service = CameraGalleryService(
        CameraApi(gateways.transport), CameraDeviceHostApi());
    final container = ProviderContainer(overrides: [
      cameraRollIndexApiProvider.overrideWithValue(api),
      cameraGalleryServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(cameraRollIndexProvider, (_, __) {});
    addTearDown(subscription.close);
    final controller = container.read(cameraRollIndexProvider.notifier);
    final pending = controller.refresh();
    await pumpEventQueue();
    final state = container.read(cameraRollIndexProvider);
    expect(state.latest?.status, CameraRollStatus.closed);
    expect(state.scanning, isTrue);
    controller.cancel();
    api.firstPage
        .complete(const CameraRollIndexPage([], 0, false, false, 1, 0));
    await pending;
    expect(container.read(cameraRollIndexProvider).checked, 0);
    expect(container.read(cameraRollIndexProvider).scanning, isFalse);
  });
  test('refresh reaches latest saved JPEGs beyond an unmarked first page',
      () async {
    final api = _PagedApi();
    final gateways = FakeCameraGateways();
    addTearDown(gateways.dispose);
    final service = CameraGalleryService(
        CameraApi(gateways.transport), CameraDeviceHostApi());
    final container = ProviderContainer(overrides: [
      cameraRollIndexApiProvider.overrideWithValue(api),
      cameraGalleryServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(cameraRollIndexProvider, (_, __) {});
    addTearDown(subscription.close);
    await container.read(cameraRollIndexProvider.notifier).refresh();
    expect(api.cursors, [0, 65537]);
    expect(
        container.read(cameraRollIndexProvider).latest?.verifiedPhotoCount, 2);
  });

  test('cancel stops automatic paging while waiting for its next turn',
      () async {
    final api = _PagedApi();
    final gateways = FakeCameraGateways();
    addTearDown(gateways.dispose);
    final service = CameraGalleryService(
        CameraApi(gateways.transport), CameraDeviceHostApi());
    final container = ProviderContainer(overrides: [
      cameraRollIndexApiProvider.overrideWithValue(api),
      cameraGalleryServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(cameraRollIndexProvider, (_, __) {});
    addTearDown(subscription.close);
    final controller = container.read(cameraRollIndexProvider.notifier);
    final pending = controller.refresh();
    await pumpEventQueue();
    expect(container.read(cameraRollIndexProvider).checked, 16);
    controller.cancel();
    await pending;
    expect(api.cursors, [0]);
    expect(container.read(cameraRollIndexProvider).latest?.journalCount, 2);
  });

  test('offline refresh is explicit and cannot create local fake rolls',
      () async {
    final container = ProviderContainer(
        overrides: [cameraRollIndexApiProvider.overrideWithValue(null)]);
    addTearDown(container.dispose);
    final subscription = container.listen(cameraRollIndexProvider, (_, __) {});
    addTearDown(subscription.close);
    await container.read(cameraRollIndexProvider.notifier).refresh();
    expect(container.read(cameraRollIndexProvider).rolls, isEmpty);
    expect(container.read(cameraRollIndexProvider).error, isNotNull);
  });
}
