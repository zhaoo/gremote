import 'package:flutter/services.dart';

class AppPackageInfo {
  const AppPackageInfo(
      {required this.appName,
      required this.version,
      required this.buildNumber});
  final String appName, version, buildNumber;

  static Future<AppPackageInfo> fromPlatform() async {
    final info = await const MethodChannel('gremote/app_info')
        .invokeMapMethod<String, Object?>('read');
    String field(String key) {
      final value = info?[key];
      if (value is! String || value.isEmpty) {
        throw const FormatException('无法读取应用版本');
      }
      return value;
    }

    return AppPackageInfo(
        appName: field('appName'),
        version: field('version'),
        buildNumber: field('buildNumber'));
  }
}
