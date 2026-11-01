import 'package:flutter/material.dart';
import 'film_library_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../film_workbench/camera_films_page.dart';

class CameraPage extends StatelessWidget {
  const CameraPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('相机'),
              bottom: const TabBar(tabs: [Tab(text: '胶卷库'), Tab(text: '扩展')])),
          body: const TabBarView(
              children: [FilmLibraryPage(), CameraExtensions()]),
        ),
      );
}

class CameraExtensions extends ConsumerWidget {
  const CameraExtensions({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected =
        ref.watch(connectionControllerProvider) is ConnectionReady;
    return ListView(padding: const EdgeInsets.all(20), children: [
      if (!connected)
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('未连接相机'),
            trailing: TextButton(
                onPressed: () => context.go('/home'), child: const Text('连接'))),
      Card(
          child: ListTile(
              title: const Text('胶卷参数'),
              subtitle: const Text('颗粒、光晕'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('机内胶卷')),
                          body: const SafeArea(child: CameraFilmsPage())))))),
      for (final group in const {
        '功能': ['快切', 'Half'],
        '效果': ['HDF', '边框', '漏光', '模糊'],
        '水印': ['时间', '胶卷'],
        '焦距': ['第一档', '第二档'],
        '画幅': ['3:2', '1:1', '4:3', '16:9', 'XPan', '6×7', 'Half 3:4'],
        '开关机画面': ['开机画面', '关机画面']
      }.entries) ...[
        Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Text(group.key,
                style: Theme.of(context).textTheme.titleMedium)),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(group.value.join(' · ')),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Icon(Icons.lock_outline, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(
                                group.key == '功能' ||
                                        group.key == '效果' ||
                                        group.key == '画幅' ||
                                        group.key == '开关机画面'
                                    ? '当前固件与遥控接口尚未完整支持'
                                    : '遥控接口待接入',
                                style: Theme.of(context).textTheme.bodySmall))
                      ]),
                    ]))),
      ],
    ]);
  }
}
