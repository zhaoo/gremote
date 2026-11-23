import 'package:flutter/material.dart';
import '../library/album_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../camera/companion/camera_roll_index.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../library/camera_gallery.dart';
import '../library/live_gallery_page.dart';
import 'roll_detail_page.dart';
import 'rolls_page.dart';
import 'workbench_providers.dart';
import 'companion_providers.dart';
import 'roll_archive_actions.dart';

class CameraRollDetailPage extends ConsumerStatefulWidget {
  const CameraRollDetailPage(this.initialRoll, {super.key});
  final CameraIndexedRoll initialRoll;
  @override
  ConsumerState<CameraRollDetailPage> createState() =>
      _CameraRollDetailPageState();
}

class _CameraRollDetailPageState extends ConsumerState<CameraRollDetailPage> {
  bool _preparing = false, _cancelled = false;
  String? _error;
  late final String? _sourceCameraKey;
  @override
  void initState() {
    super.initState();
    _sourceCameraKey = ref.read(cameraArchiveStableKeyProvider);
  }

  bool _sameSourceCamera() =>
      _sourceCameraKey != null &&
      ref.read(connectionControllerProvider) is ConnectionReady &&
      ref.read(cameraArchiveStableKeyProvider) == _sourceCameraKey;

  Future<void> _readSourceIndex({bool more = false}) async {
    if (!_sameSourceCamera()) return;
    final controller = ref.read(cameraRollIndexProvider.notifier);
    if (more) {
      await controller.loadMore();
    } else {
      setState(() => _error = null);
      await controller.refresh();
    }
  }

  Future<void> _save(CameraIndexedRoll roll) async {
    if (_preparing || !_sameSourceCamera()) return;
    setState(() {
      _preparing = true;
      _cancelled = false;
      _error = null;
    });
    try {
      // Finish the bounded serial index before calling the existing downloader;
      // the first scan page must never be presented as the whole roll.
      while (
          mounted && !_cancelled && ref.read(cameraRollIndexProvider).hasMore) {
        if (!_sameSourceCamera())
          throw const FormatException('相机已切换，请返回胶卷列表重新读取');
        final before = ref.read(cameraRollIndexProvider);
        await ref.read(cameraRollIndexProvider.notifier).loadMore();
        if (!mounted || _cancelled) return;
        final after = ref.read(cameraRollIndexProvider);
        if (after.error != null ||
            (after.hasMore && after.checked <= before.checked)) {
          throw const FormatException('整卷原片尚未读取完整，请继续读取后重试');
        }
        if (!_sameSourceCamera())
          throw const FormatException('相机已切换，请返回胶卷列表重新读取');
      }
      if (!mounted || _cancelled || !_sameSourceCamera()) return;
      final terminal = ref.read(cameraRollIndexProvider);
      if (terminal.truncated) {
        throw const FormatException(
            '相机照片超过单次读取上限（4096 张），无法确认整卷完整。请改用相机照片按张保存。');
      }
      if (terminal.skipped > 0) {
        throw const FormatException('部分照片卷标记未能读取，无法确认整卷完整。请重新读取后重试。');
      }
      if (terminal.error != null) {
        throw const FormatException('整卷原片尚未读取完整，请重新读取后重试');
      }
      final complete = ref
          .read(cameraRollIndexProvider)
          .rolls
          .where((r) => r.id == roll.id)
          .firstOrNull;
      if (complete == null) throw const FormatException('胶卷记录已变化，请返回胶卷列表重新读取');
      if (complete.photos.isEmpty) {
        throw const FormatException('尚未找到本卷原片，请重新读取相机胶卷');
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('保存整卷')),
              body: SafeArea(
                  child: CameraGallery(
                      initialFiles: complete.photos.map((p) => p.file).toList(),
                      startDownload: true,
                      sourceCameraKey: _sourceCameraKey)))));
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception catch (_) {
      if (mounted) setState(() => _error = '整卷读取失败，请检查连接后重试');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        ref.watch(connectionControllerProvider) is ConnectionReady;
    final currentKey = ref.watch(cameraArchiveStableKeyProvider);
    if (connected &&
        (_sourceCameraKey == null || currentKey != _sourceCameraKey)) {
      return Theme(
          data: albumTheme(context),
          child: Scaffold(
              appBar: AppBar(
                  title: const Text('胶卷', style: TextStyle(fontSize: 18)),
                  centerTitle: true),
              body: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.cameraswitch_outlined,
                        color: context.palette.muted, size: 30),
                    const SizedBox(height: 16),
                    Text(_sourceCameraKey == null ? '相机身份尚未确认' : '相机已切换',
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('返回胶卷列表'))
                  ]))));
    }
    final state = ref.watch(cameraRollIndexProvider);
    final catalog = ref.watch(cameraFilmCatalogProvider).valueOrNull;
    final roll =
        state.rolls.where((r) => r.id == widget.initialRoll.id).firstOrNull ??
            widget.initialRoll;
    final local = ref
        .watch(filmRollsProvider)
        .valueOrNull
        ?.where((r) => r.id == roll.id)
        .firstOrNull;
    final reading = state.loading || state.scanning;
    return Theme(
        data: albumTheme(context),
        child: Builder(
            builder: (context) => Scaffold(
                  appBar: AppBar(
                      title: const Text('胶卷', style: TextStyle(fontSize: 18)),
                      centerTitle: true,
                      actions: [
                        PopupMenuButton<String>(
                            tooltip: '胶卷更多',
                            icon: const Icon(Icons.more_horiz),
                            onSelected: (value) async {
                              if (value == 'remove' &&
                                  _sourceCameraKey != null) {
                                try {
                                  final removed = await hideCameraRollArchive(
                                      context, ref, _sourceCameraKey, roll.id);
                                  if (removed && context.mounted)
                                    Navigator.of(context).maybePop();
                                } catch (_) {
                                  if (mounted)
                                    setState(() => _error = '记录移除失败，请重试');
                                }
                              } else if (value == 'export' &&
                                  local != null &&
                                  local.confirmedCount > 0) {
                                Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                        builder: (_) => RollDetailPage(
                                            rollId: roll.id,
                                            openExport: true)));
                              }
                            },
                            itemBuilder: (_) => [
                                  PopupMenuItem(
                                      value: 'export',
                                      enabled: (local?.confirmedCount ?? 0) > 0,
                                      child: const Text('导出印样')),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                      value: 'remove',
                                      enabled: _sourceCameraKey != null &&
                                          !_preparing,
                                      child: const Text('移除记录'))
                                ]),
                      ]),
                  body: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                            child: Row(children: [
                              SizedBox(
                                  width: 48,
                                  height: 64,
                                  child: CameraRollFilmIcon(
                                      roll: roll, catalog: catalog, size: 48)),
                              const SizedBox(width: 18),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(cameraRollName(roll, catalog: catalog),
                                        style: const TextStyle(
                                            fontSize: 25,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 7),
                                    Text(
                                        '${roll.journalCount ?? roll.verifiedPhotoCount} / ${roll.target} 张 · ${cameraRollStatus(roll)}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context.palette.muted))
                                  ])),
                              const AlbumTag('相机'),
                            ])),
                        if (reading)
                          LinearProgressIndicator(
                              minHeight: 2, color: context.palette.accent),
                        if (_error != null) ...[
                          AlbumNotice(_error!, error: true),
                          TextButton(
                              onPressed: connected && !_preparing
                                  ? () async {
                                      setState(() => _error = null);
                                      await _readSourceIndex();
                                    }
                                  : null,
                              child: const Text('重新读取胶卷'))
                        ],
                        if (state.error != null &&
                            ref.watch(cameraRollIndexApiProvider) != null)
                          AlbumNotice(state.error!, error: true),
                        if (local != null && local.confirmedCount > 0)
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                      onPressed: () => Navigator.of(context)
                                          .push(MaterialPageRoute<void>(
                                              builder: (_) => RollDetailPage(
                                                  rollId: roll.id))),
                                      child: Text(
                                          '查看已保存的 ${local.confirmedCount} 张')))),
                        if (!connected)
                          const Padding(
                              padding: EdgeInsets.all(28),
                              child: Center(child: Text('连接相机后查看照片')))
                        else if (roll.photos.isEmpty)
                          Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 62, horizontal: 24),
                              child: Column(children: [
                                Icon(Icons.photo_outlined,
                                    size: 30, color: context.palette.muted),
                                const SizedBox(height: 14),
                                Text(
                                    reading
                                        ? '正在读取照片…'
                                        : (roll.journalCount ?? 0) > 0
                                            ? '照片尚未读取'
                                            : '这一卷还没有照片',
                                    style: TextStyle(
                                        color: context.palette.muted,
                                        fontSize: 14)),
                                if (!reading)
                                  TextButton(
                                      onPressed: () => _readSourceIndex(),
                                      child: const Text('重新读取'))
                              ]))
                        else
                          Expanded(
                              child: CameraGallery(
                                  initialFiles:
                                      roll.photos.map((p) => p.file).toList(),
                                  sourceCameraKey: _sourceCameraKey)),
                        if (connected && state.hasMore && !reading)
                          TextButton(
                              onPressed: () => _readSourceIndex(more: true),
                              child: const Text('读取更多照片')),
                      ]),
                  bottomNavigationBar: connected && roll.photos.isNotEmpty
                      ? SafeArea(
                          top: false,
                          child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 12, 20, 16),
                              child: FilledButton.icon(
                                  onPressed: _preparing || reading
                                      ? null
                                      : () => _save(roll),
                                  icon: const Icon(Icons.download_outlined,
                                      size: 18),
                                  label:
                                      Text(_preparing ? '正在读取整卷…' : '保存整卷'))))
                      : null,
                )));
  }
}
