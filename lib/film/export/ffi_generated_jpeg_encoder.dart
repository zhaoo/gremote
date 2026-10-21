import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import '../../imaging/imaging_engine.dart';
import '../../imaging/imaging_exception.dart';
import 'contact_sheet_exporter.dart';

typedef _EncodeC = Int32 Function(
    Pointer<Uint8>, Int32, Int32, Pointer<Utf8>, Pointer<Int32>);
typedef _EncodeDart = int Function(
    Pointer<Uint8>, int, int, Pointer<Utf8>, Pointer<Int32>);

class FfiGeneratedJpegEncoder implements GeneratedJpegEncoder {
  const FfiGeneratedJpegEncoder({this.libraryPath = 'libgremote_imaging.so'});
  final String libraryPath;
  @override
  Future<void> encode(PreviewImage image, String path,
      {ImagingCancelToken? cancel}) {
    if (image.width < 1 ||
        image.height < 1 ||
        image.width * image.height > 4000000 ||
        image.rgba.length != image.width * image.height * 4) {
      throw const ImagingException(ImagingErrorCode.invalidArgument);
    }
    final library = libraryPath, address = cancel?.address ?? 0;
    return Isolate.run(() => _encode(image, path, library, address));
  }
}

void _encode(
    PreviewImage image, String path, String library, int cancelAddress) {
  final lib = DynamicLibrary.open(
      Platform.isIOS ? 'gremote_imaging.framework/gremote_imaging' : library);
  final encode = lib
      .lookupFunction<_EncodeC, _EncodeDart>('gremote_encode_generated_jpeg');
  using((arena) {
    final pixels = arena<Uint8>(image.rgba.length)
      ..asTypedList(image.rgba.length).setAll(0, image.rgba);
    final result = encode(
        pixels,
        image.width,
        image.height,
        path.toNativeUtf8(allocator: arena),
        Pointer<Int32>.fromAddress(cancelAddress));
    if (result != 0) throw ImagingException(ImagingErrorCode.fromValue(result));
  });
}
