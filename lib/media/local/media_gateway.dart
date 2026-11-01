import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../darkroom/model/photo_meta.dart';

/// One JPEG row from MediaStore, before EXIF is read.
@immutable
class LocalMediaEntry {
  const LocalMediaEntry({
    required this.id,
    required this.uri,
    required this.displayName,
    required this.dateModified,
    this.dateTaken,
    this.width = 0,
    this.height = 0,
    this.appAlbum = false,
  });

  final int id;
  final String uri;
  final String displayName;

  /// Seconds since epoch, as MediaStore reports it.
  final int dateModified;

  /// Milliseconds since epoch.
  final int? dateTaken;
  final int width;
  final int height;
  final bool appAlbum;
}

enum MediaAccess { granted, partial, denied }

class MediaException implements Exception {
  const MediaException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() =>
      'MediaException($code${message == null ? '' : ': $message'})';
}

/// Platform boundary for the local photo library and export publishing.
abstract interface class MediaGateway {
  Future<MediaAccess> access();

  /// Requests photo access and returns the resulting state.
  Future<MediaAccess> requestAccess();

  /// Whether EXIF GPS is readable (ACCESS_MEDIA_LOCATION).
  Future<bool> hasLocationAccess();

  Future<bool> requestLocationAccess();

  Future<List<LocalMediaEntry>> queryImages();

  Future<Map<int, PhotoMeta>> readExif(List<int> ids);

  Future<Uint8List?> thumbnail(int id, int edge);

  /// Detached read-only descriptor; the receiver must close it.
  Future<int> openReadFd(int id);

  /// SHA256 of the original JPEG, streamed by the platform.
  Future<String> contentHash(int id);

  /// Writes filtered EXIF into [tempPath] and publishes it; returns the uri.
  Future<String> publishExport({
    required String tempPath,
    required int sourceId,
    required String displayName,
    required bool keepGps,
    required int width,
    required int height,
  });

  /// Publishes a newly generated JPEG with no source-photo metadata.
  Future<String> publishGenerated(
      {required String tempPath,
      required String displayName,
      required int width,
      required int height});

  Future<String> importPhoto(String tempPath, String displayName);

  Future<void> shareRecipe(Uint8List card);

  Future<void> share(String uri);
}
