import 'package:flutter/services.dart';

import '../../darkroom/model/photo_meta.dart';
import '../../platform/media_api.g.dart';
import 'media_gateway.dart';

/// [MediaGateway] backed by the Kotlin `MediaHostApi`.
class NativeMediaGateway implements MediaGateway {
  NativeMediaGateway([MediaHostApi? api]) : _api = api ?? MediaHostApi();

  final MediaHostApi _api;

  @override
  Future<MediaAccess> access() =>
      _guard(() async => _access(await _api.access()));

  @override
  Future<MediaAccess> requestAccess() =>
      _guard(() async => _access(await _api.requestAccess()));

  @override
  Future<bool> hasLocationAccess() => _guard(_api.hasLocationAccess);

  @override
  Future<bool> requestLocationAccess() => _guard(_api.requestLocationAccess);

  @override
  Future<List<LocalMediaEntry>> queryImages() => _guard(() async => [
        for (final e in await _api.queryImages())
          LocalMediaEntry(
            id: e.id,
            uri: e.uri,
            displayName: e.displayName,
            dateModified: e.dateModified,
            dateTaken: e.dateTaken,
            width: e.width,
            height: e.height,
          ),
      ]);

  @override
  Future<Map<int, PhotoMeta>> readExif(List<int> ids) => _guard(() async => {
        for (final s in await _api.readExif(ids))
          s.id: PhotoMeta(
            width: s.width,
            height: s.height,
            orientation: s.orientation,
            make: s.make,
            model: s.model,
            fNumber: s.fNumber,
            exposureTime: s.exposureTime,
            iso: s.iso,
            focal35: s.focal35,
            focal: s.focal,
            takenAt: s.takenAt,
            hasGps: s.hasGps,
          ),
      });

  @override
  Future<Uint8List?> thumbnail(int id, int edge) =>
      _guard(() => _api.thumbnail(id, edge));

  @override
  Future<int> openReadFd(int id) => _guard(() => _api.openReadFd(id));

  @override
  Future<String> publishExport({
    required String tempPath,
    required int sourceId,
    required String displayName,
    required bool keepGps,
    required int width,
    required int height,
  }) =>
      _guard(() => _api.publishExport(
          tempPath, sourceId, displayName, keepGps, width, height));

  @override
  Future<void> share(String uri) => _guard(() => _api.share(uri));

  static MediaAccess _access(NativeMediaAccess value) => switch (value) {
        NativeMediaAccess.granted => MediaAccess.granted,
        NativeMediaAccess.partial => MediaAccess.partial,
        NativeMediaAccess.denied => MediaAccess.denied,
      };

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw MediaException(e.code, e.message);
    }
  }
}
