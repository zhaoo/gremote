import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/capture/capture_tracker.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/camera/recipe/recipe_store.dart';
import 'package:gremote/camera/recipe/tag_matcher.dart';
import 'package:gremote/darkroom/model/photo_meta.dart';
import 'package:gremote/media/local/local_media_repository.dart';

LocalMediaItem _item({
  String name = 'R0000001.JPG',
  String? takenAt = '2026:10:10 08:30:00',
  int? dateTaken,
}) =>
    LocalMediaItem(
      id: 1,
      uri: 'content://1',
      displayName: name,
      dateModified: 1,
      dateTaken: dateTaken,
      meta: PhotoMeta(width: 10, height: 10, takenAt: takenAt),
    );

CaptureTag _tag({
  int id = 1,
  String name = 'R0000001',
  required int seconds,
  TimeSource source = TimeSource.camera,
  bool confirmed = false,
}) =>
    CaptureTag(
      id: id,
      baseName: name,
      dir: '100RICOH',
      wallSeconds: seconds,
      timeSource: source,
      recipeId: 'recipe',
      confirmed: confirmed,
    );

void main() {
  final shot = wallSecondsOf('2026-10-10 08:30:00')!;

  test('camera time within two seconds is a strong usable match', () {
    final match = matchTag(_item(), [_tag(seconds: shot + 2)]);
    expect(match?.strength, MatchStrength.strong);
    expect(match?.usable, isTrue);
  });

  test('phone time within 12 hours is weak until confirmed', () {
    final weak = matchTag(
        _item(), [_tag(seconds: shot + 3600, source: TimeSource.phone)]);
    expect(weak?.strength, MatchStrength.weak);
    expect(weak?.usable, isFalse);

    final confirmed = matchTag(_item(), [
      _tag(seconds: shot + 3600, source: TimeSource.phone, confirmed: true),
    ]);
    expect(confirmed?.usable, isTrue);
  });

  test('file name must match, case-insensitively', () {
    expect(matchTag(_item(name: 'r0000001.jpg'), [_tag(seconds: shot)]),
        isNotNull);
    expect(
        matchTag(_item(name: 'R0000002.JPG'), [_tag(seconds: shot)]), isNull);
  });

  test('the closest candidate wins after file names cycle', () {
    final match = matchTag(_item(), [
      _tag(id: 1, seconds: shot - 2),
      _tag(id: 2, seconds: shot + 1),
    ]);
    expect(match?.tag.id, 2);
  });

  test('out-of-window and missing EXIF do not match camera timestamps', () {
    expect(matchTag(_item(), [_tag(seconds: shot + 3)]), isNull);
    expect(matchTag(_item(takenAt: null), [_tag(seconds: shot)]), isNull);
  });
}
