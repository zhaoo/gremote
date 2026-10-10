import 'package:pigeon/pigeon.dart';

class NativeBleDevice {
  String? id;
  String? name;
  int? rssi;
}

class NativeCameraBootstrap {
  String? model;
  String? firmware;
  int? batteryLevel;
  bool? acPowered;
  String? ssid;
  String? passphrase;
}

class NativeHttpResponse {
  int? statusCode;
  Map<String?, String?>? headers;
  Uint8List? body;
}

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/platform/device_api.g.dart',
  kotlinOut:
      'android/app/src/main/kotlin/com/izhaoo/gremote/device/DeviceApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.izhaoo.gremote.device'),
))
@HostApi()
abstract class CameraDeviceHostApi {
  int androidSdkInt();

  @async
  List<NativeBleDevice?> scan(int timeoutMs);

  @async
  void connectBle(String deviceId);

  @async
  void disconnectBle();

  @async
  NativeCameraBootstrap readBootstrap();

  @async
  void setCameraPower(int value);

  @async
  void setNetworkType(int value);

  @async
  void writeOperationRequest(Uint8List value);

  @async
  void connectCameraWifi(String ssid, String passphrase);

  @async
  NativeHttpResponse cameraRequest(
    String method,
    String url,
    Map<String?, String?> headers,
    Uint8List? body,
  );

  /// Streams one camera original directly into Android MediaStore.
  @async
  String downloadPhoto(String directory, String fileName);

  @async
  void startLiveView(String url);

  @async
  void stopLiveView();

  /// Opens the `/v1/changes` WebSocket; events arrive as `changes.*`.
  @async
  void openChangeSocket(String path);

  @async
  void closeChangeSocket();

  void setKeepScreenOn(bool on);
}

@FlutterApi()
abstract class CameraDeviceFlutterApi {
  void onLiveViewChunk(Uint8List bytes);

  void onNativeEvent(String type, String jsonPayload);
}
