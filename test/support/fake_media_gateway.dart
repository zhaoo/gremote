import 'dart:typed_data';

import 'package:gremote/darkroom/model/photo_meta.dart';
import 'package:gremote/media/local/media_gateway.dart';

class PublishCall {
  PublishCall(this.tempPath, this.sourceId, this.displayName, this.keepGps,
      this.width, this.height);

  final String tempPath;
  final int sourceId;
  final String displayName;
  final bool keepGps;
  final int width;
  final int height;
}

class GeneratedPublishCall {
  GeneratedPublishCall(
      this.tempPath, this.displayName, this.width, this.height);
  final String tempPath, displayName;
  final int width, height;
}

class FakeMediaGateway implements MediaGateway {
  FakeMediaGateway({
    this.entries = const [],
    this.exif = const {},
    this.mediaAccess = MediaAccess.granted,
    this.locationAccess = true,
  });

  List<LocalMediaEntry> entries;
  Map<int, PhotoMeta> exif;
  MediaAccess mediaAccess;
  MediaAccess? accessAfterRequest;
  bool locationAccess;
  Object? publishError;

  /// Awaited before each EXIF batch; lets tests observe a scan in flight.
  Future<void> Function()? beforeExif;
  final exifRequests = <List<int>>[];
  final publishes = <PublishCall>[];
  final generated = <GeneratedPublishCall>[];
  final shared = <String>[];
  final openedFds = <int>[];
  int _nextFd = 100;

  @override
  Future<String> importPhoto(String tempPath, String displayName) async => 'content://media/external/images/media/999';

  @override
  Future<MediaAccess> access() async => mediaAccess;

  @override
  Future<MediaAccess> requestAccess() async =>
      mediaAccess = accessAfterRequest ?? mediaAccess;

  @override
  Future<bool> hasLocationAccess() async => locationAccess;

  @override
  Future<bool> requestLocationAccess() async => locationAccess;

  @override
  Future<List<LocalMediaEntry>> queryImages() async => entries;

  @override
  Future<Map<int, PhotoMeta>> readExif(List<int> ids) async {
    exifRequests.add(List.of(ids));
    await beforeExif?.call();
    return {
      for (final id in ids)
        if (exif[id] != null) id: exif[id]!,
    };
  }

  @override
  Future<Uint8List?> thumbnail(int id, int edge) async => null;

  @override
  Future<int> openReadFd(int id) async {
    final fd = _nextFd++;
    openedFds.add(fd);
    return fd;
  }

  final contentHashes = <int, String>{};
  @override
  Future<String> contentHash(int id) async =>
      contentHashes[id] ?? (throw StateError("original unavailable"));

  @override
  Future<String> publishExport({
    required String tempPath,
    required int sourceId,
    required String displayName,
    required bool keepGps,
    required int width,
    required int height,
  }) async {
    if (publishError != null) throw publishError!;
    publishes.add(
        PublishCall(tempPath, sourceId, displayName, keepGps, width, height));
    return 'content://media/external/images/media/${9000 + publishes.length}';
  }

  @override
  Future<String> publishGenerated(
      {required String tempPath,
      required String displayName,
      required int width,
      required int height}) async {
    if (publishError != null) throw publishError!;
    generated.add(GeneratedPublishCall(tempPath, displayName, width, height));
    return "content://generated/${generated.length}";
  }

  final recipeCards = <Uint8List>[];
  @override
  Future<void> shareRecipe(Uint8List card) async => recipeCards.add(card);

  @override
  Future<void> share(String uri) async => shared.add(uri);
}
