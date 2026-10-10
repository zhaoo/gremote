import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/http/camera_files.dart';

void main() {
  test('base names ignore extension and case', () {
    const jpeg = CameraFile(dir: '100RICOH', file: 'R0000001.JPG');
    const raw = CameraFile(dir: '100RICOH', file: 'r0000001.dng');
    expect(jpeg.baseName, raw.baseName);
    expect(raw.extension, 'DNG');
  });

  test('only supported originals can be downloaded', () {
    expect(const CameraFile(dir: '100RICOH', file: 'R0000001.JPG').downloadable,
        isTrue);
    expect(const CameraFile(dir: '100RICOH', file: 'R0000001.DNG').downloadable,
        isTrue);
    expect(const CameraFile(dir: '100RICOH', file: 'R0000001.MOV').downloadable,
        isFalse);
  });

  test('a missing dirs field is an empty list', () {
    expect(parsePhotoList({'errCode': 200}), isEmpty);
    expect(
        parsePhotoList({
          'dirs': [
            {'name': 1, 'files': []},
          ],
        }),
        isEmpty);
  });

  test('camera and EXIF times share one wall-clock scale', () {
    final camera = parseCaptureWallSeconds({'datetime': '2026-10-10T08:30:00'});
    final exif = exifWallSeconds('2026:10:10 08:30:00');
    expect(camera, isNotNull);
    expect(camera, exif);
    expect(parseCaptureWallSeconds({'captureDate': 'yesterday'}), isNull);
  });

  test('phone wall clock ignores the time zone offset', () {
    final local = DateTime(2026, 10, 10, 8, 30);
    expect(phoneWallSeconds(local), wallSecondsOf('2026-10-10 08:30:00'));
  });
}
