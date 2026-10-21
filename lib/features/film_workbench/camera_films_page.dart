import 'package:flutter/material.dart';
import 'widgets/workbench_style.dart';

class CameraFilmsPage extends StatelessWidget {
  const CameraFilmsPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(children: [
        const WorkbenchHeading('相机胶卷', '手机选好，相机带走。', 'POCKET TO CAMERA.'),
        Container(
            margin: const EdgeInsets.symmetric(horizontal: 22),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
                color: workbenchSurface,
                borderRadius: BorderRadius.circular(16)),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.camera_alt_outlined,
                      size: 36, color: workbenchGold),
                  SizedBox(height: 16),
                  Text('尚未连接 M10V 胶卷桥',
                      style: TextStyle(
                          color: workbenchCream,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 10),
                  Text('请连接相机 Wi-Fi 并导入配对文件。机内配置读取与写入需要相机桥确认支持。',
                      style: TextStyle(color: workbenchMuted, height: 1.7)),
                ])),
        const Padding(
            padding: EdgeInsets.all(24),
            child: Text('离线时仍可试色、开卷和整理照片。',
                style: TextStyle(fontSize: 12, color: workbenchMuted))),
      ]);
}
