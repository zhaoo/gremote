import 'package:pigeon/pigeon.dart';

enum NativeMediaAccess { granted, partial, denied }

class NativeMediaEntry {
  NativeMediaEntry({
    required this.id,
    required this.uri,
    required this.displayName,
    required this.dateModified,
    required this.width,
    required this.height,
  });

  int id;
  String uri;
  String displayName;
  int dateModified;
  int? dateTaken;
  int width;
  int height;
}

class NativeExifSummary {
  NativeExifSummary({
    required this.id,
    required this.width,
    required this.height,
    required this.orientation,
    required this.hasGps,
  });

  int id;
  int width;
  int height;
  int orientation;
  String? make;
  String? model;
  double? fNumber;
  double? exposureTime;
  int? iso;
  int? focal35;
  double? focal;
  String? takenAt;
  bool hasGps;
}

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/platform/media_api.g.dart',
  kotlinOut: 'android/app/src/main/kotlin/com/zhaoo/gremote/media/MediaApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.izhaoo.gremote.media'),
))
@HostApi()
abstract class MediaHostApi {
  NativeMediaAccess access();

  @async
  NativeMediaAccess requestAccess();

  bool hasLocationAccess();

  @async
  bool requestLocationAccess();

  @async
  List<NativeMediaEntry> queryImages();

  @async
  List<NativeExifSummary> readExif(List<int> ids);

  @async
  Uint8List? thumbnail(int id, int edge);

  @async
  int openReadFd(int id);

  @async
  String publishExport(
    String tempPath,
    int sourceId,
    String displayName,
    bool keepGps,
    int width,
    int height,
  );

  void share(String uri);
}
