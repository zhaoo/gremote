import 'dart:convert';
import 'dart:typed_data';

import 'package:gremote/camera/gateway/camera_transport.dart';
import 'package:gremote/camera/gateway/change_socket.dart';
import 'package:gremote/camera/gateway/fake_camera_model.dart';

/// The socket opens, but parameter PUTs only echo their values over HTTP.
class EchoCameraModel extends FakeCameraModel {
  void Function()? afterWrite;

  @override
  Stream<ChangeSocketEvent> get socketEvents =>
      super.socketEvents.where((event) => event is! ChangeSocketMessage);

  @override
  CameraResponse handle(String method, String path,
      {Map<String, String> headers = const {}, Uint8List? body}) {
    final response = super.handle(method, path, headers: headers, body: body);
    if (method != 'PUT' || response.statusCode != 200) return response;
    afterWrite?.call();
    return CameraResponse(
        statusCode: 200,
        headers: response.headers,
        body: Uint8List.fromList(utf8.encode(jsonEncode(props))));
  }
}
