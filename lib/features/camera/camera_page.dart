import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/widgets/workspace_tabs.dart';
import '../../camera/companion/companion_sync_controller.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../film_workbench/companion_providers.dart';
import '../film_workbench/camera_films_page.dart';
import 'film_library_page.dart';
import 'extensions_page.dart';

class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key});
  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends ConsumerState<CameraPage> {
  var _tab = 0;
  CompanionSyncController? _loaded;
  @override
  Widget build(BuildContext context) {
    ref.watch(companionIdentityHydrationProvider);
    final connection = ref.watch(connectionControllerProvider);
    final connected = connection is ConnectionReady;
    final sync = ref.watch(companionSyncControllerProvider);
    if (!connected) _loaded = null;
    if (connected && sync != null && !identical(sync, _loaded)) {
      _loaded = sync;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(sync.refresh());
      });
    }
    return Scaffold(
        body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(children: [
                      Expanded(
                          child: Text('相机',
                              style:
                                  Theme.of(context).textTheme.headlineMedium)),
                      TextButton.icon(
                          onPressed: _connectionOptions,
                          icon: Icon(Icons.circle,
                              size: 6,
                              color: connected
                                  ? GRemoteColors.text
                                  : GRemoteColors.muted),
                          label: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .4),
                              child: Text(connected ? connection.snapshot.identity.model : '未连接',
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: GRemoteColors.muted)))),
                    ])),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: WorkspaceTabs<int>(
                        items: const [(0, '胶卷库'), (1, '扩展')],
                        value: _tab,
                        onChanged: (v) => setState(() => _tab = v))),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Divider(height: 12)),
                Expanded(
                    child: IndexedStack(index: _tab, children: const [
                  FilmLibraryPage(),
                  CameraExtensions()
                ])),
              ],
            )));
  }

  void _connectionOptions() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              title: const Text('相机连接'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(sheet);
                context.go('/home');
              }),
          ListTile(
              title: const Text('配对与机内胶卷'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('机内胶卷')),
                            body: const SafeArea(child: CameraFilmsPage()))));
              }),
        ])),
      );
}
