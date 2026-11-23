import '../../app/release_policy.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../../camera/http/camera_files.dart';
import '../film_workbench/companion_providers.dart';
import '../film_workbench/roll_archive_actions.dart';
import 'camera_gallery.dart';
import 'camera_live_photo_page.dart';
import 'live_gallery_controller.dart';

typedef CameraAlbumThumbnailKey = ({String cameraKey, CameraFile photo});
final cameraAlbumThumbnailProvider = FutureProvider.autoDispose
    .family<Uint8List, CameraAlbumThumbnailKey>((ref, key) async {
  ref.watch(cameraArchiveStableKeyProvider);
  var alive = true;
  ref.onDispose(() => alive = false);
  bool current() =>
      alive && ref.read(cameraArchiveStableKeyProvider) == key.cameraKey;
  if (!current()) throw StateError('Camera session changed');
  final bytes = await ref
      .watch(cameraGalleryServiceProvider)
      .thumbnail(key.photo, isCurrent: current);
  if (!current()) throw StateError('Camera session changed');
  return bytes;
});

class LiveGalleryPage extends ConsumerStatefulWidget {
  const LiveGalleryPage({super.key});
  @override
  ConsumerState<LiveGalleryPage> createState() => _LiveGalleryPageState();
}

class _LiveGalleryPageState extends ConsumerState<LiveGalleryPage> {
  bool _savedOnly = false;
  @override
  void initState() {
    super.initState();
    if (!cameraLiveAvailable) return;
    Future.microtask(() async {
      await Future.wait<Object?>([
        ref.read(companionHotspotPairingProvider.future),
        ref.read(companionIdentityHydrationProvider.future)
      ]);
      if (mounted) {
        unawaited(ref.read(liveGalleryControllerProvider.notifier).refresh());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!cameraLiveAvailable) {
      return const Center(
          child: Text('$cameraLiveUnavailableMessage\n已保存的数据保留',
              textAlign: TextAlign.center));
    }
    final ready = ref.watch(connectionControllerProvider) is ConnectionReady;
    final state = ref.watch(liveGalleryControllerProvider);
    final saved = ref.watch(savedLivePhotosProvider);
    final cameraKey = ref.watch(liveCameraArchiveKeyProvider);
    final savedMap = {
      for (final item in saved.valueOrNull ?? <SavedLivePhoto>[]) item.id: item
    };
    final items = <String, LiveGalleryItem>{
      for (final item in savedMap.values)
        item.id: LiveGalleryItem(item.photo, saved: item)
    };
    if (!_savedOnly && ready)
      for (final item in state.items) {
        items['$cameraKey:${item.id}'] = LiveGalleryItem(item.photo,
            manifest: item.manifest,
            saved:
                cameraKey == null ? null : savedMap['$cameraKey:${item.id}']);
      }
    final list = items.values.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 16),
          child: Row(children: [
            AlbumFilter(
                choices: const ['全部', '已保存'],
                selected: _savedOnly ? 1 : 0,
                onChanged: (i) => setState(() => _savedOnly = i == 1)),
            const Spacer(),
            IconButton(
                tooltip: state.loading ? '停止读取 Live' : '重新读取 Live',
                onPressed: ready
                    ? () {
                        final controller =
                            ref.read(liveGalleryControllerProvider.notifier);
                        state.loading
                            ? controller.cancel()
                            : unawaited(controller.refresh());
                      }
                    : null,
                icon: Icon(state.loading ? Icons.close : Icons.refresh,
                    size: 21)),
          ])),
      if (state.loading)
        LinearProgressIndicator(minHeight: 2, color: context.palette.accent),
      if (state.error != null) AlbumNotice(state.error!, error: true),
      if (saved.hasError) const AlbumNotice('手机中的 Live 读取失败，请重试', error: true),
      if (state.cancelled) const AlbumNotice('已停止读取 · 已读取的 Live 保留，可重新读取'),
      if (!ready && list.isNotEmpty) const AlbumNotice('相机未连接 · 仅显示已保存的 Live'),
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Text(
              '${list.length} 张 Live${state.loading ? ' · 已检查 ${state.checked} 张照片' : ''}',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
      Expanded(
          child: list.isEmpty
              ? AlbumEmpty(
                  icon: Icons.motion_photos_on_outlined,
                  title: !ready
                      ? '连接相机，读取 Live'
                      : _savedOnly
                          ? '还没有保存的 Live'
                          : state.loading
                              ? '正在查找配对短片'
                              : state.error != null
                                  ? '部分配对信息未能读取'
                                  : '尚未收到 Live 短片',
                  message: !ready
                      ? '已保存的 Live 可离线查看。相机中的短片需要连接后读取。'
                      : _savedOnly
                          ? '打开一张 Live 并保存，即可在这里离线查看。'
                          : '只有读取到配对短片的照片才会显示在这里。Live 模式尚未读取，请在相机上核对模式后重新读取。',
                  action: ready && !state.loading
                      ? TextButton(
                          onPressed: () => ref
                              .read(liveGalleryControllerProvider.notifier)
                              .refresh(),
                          child: const Text('重新读取'))
                      : null,
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 5,
                      mainAxisSpacing: 5,
                      childAspectRatio: .78),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final item = list[i];
                    return InkWell(
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => CameraLivePhotoPage(item.photo,
                                    saved: item.saved))),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: Stack(fit: StackFit.expand, children: [
                              if (item.saved != null)
                                Image.file(File(item.saved!.jpegPath),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Center(
                                        child:
                                            Icon(Icons.broken_image_outlined)))
                              else
                                CameraAlbumThumbnail(item.photo),
                              const Positioned(
                                  top: 10, left: 10, child: AlbumTag('◎ Live')),
                              if (item.saved != null)
                                const Positioned(
                                    bottom: 10,
                                    left: 10,
                                    child: AlbumTag('已保存')),
                            ])));
                  })),
      if (ready && state.hasMore && !state.loading)
        TextButton(
            onPressed: () =>
                ref.read(liveGalleryControllerProvider.notifier).loadMore(),
            child: const Text('继续读取更多照片')),
    ]);
  }
}

class CameraAlbumThumbnail extends ConsumerWidget {
  const CameraAlbumThumbnail(this.photo, {super.key, this.sourceCameraKey});
  final CameraFile photo;
  final String? sourceCameraKey;
  Widget _placeholder(BuildContext context) => Semantics(
      label: photo.extension == 'DNG' ? 'RAW 预览暂不可用' : '预览暂不可用',
      child: Center(
          child: Icon(
              photo.extension == 'DNG'
                  ? Icons.raw_on_outlined
                  : Icons.photo_outlined,
              color: context.palette.muted)));
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentKey = ref.watch(cameraArchiveStableKeyProvider);
    final expected = sourceCameraKey ?? currentKey;
    if (expected == null || currentKey != expected)
      return _placeholder(context);
    return ref
        .watch(
            cameraAlbumThumbnailProvider((cameraKey: expected, photo: photo)))
        .when(
          loading: () => _placeholder(context),
          error: (_, __) => _placeholder(context),
          data: (data) => Image.memory(data,
              fit: BoxFit.cover,
              cacheWidth: 600,
              errorBuilder: (_, __, ___) => _placeholder(context)),
        );
  }
}

class AlbumTag extends StatelessWidget {
  const AlbumTag(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
          color: context.palette.background.withOpacity(.8),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: context.palette.divider)),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: context.palette.text)));
}

class AlbumFilter extends StatelessWidget {
  const AlbumFilter(
      {super.key,
      required this.choices,
      required this.selected,
      required this.onChanged});
  final List<String> choices;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: context.palette.raised,
          borderRadius: BorderRadius.circular(4)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < choices.length; i++)
          InkWell(
              onTap: () => onChanged(i),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 13),
                  decoration: BoxDecoration(
                      color: i == selected
                          ? context.palette.divider
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(3)),
                  child: Text(choices[i],
                      style: TextStyle(
                          fontSize: 12,
                          color: i == selected
                              ? context.palette.text
                              : context.palette.muted))))
      ]));
}

class AlbumNotice extends StatelessWidget {
  const AlbumNotice(this.text, {super.key, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: error ? context.palette.danger : context.palette.muted)));
}

class AlbumEmpty extends StatelessWidget {
  const AlbumEmpty(
      {super.key,
      required this.icon,
      required this.title,
      required this.message,
      this.action});
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 38, color: context.palette.muted),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.palette.muted, height: 1.7, fontSize: 12)),
            if (action != null) ...[const SizedBox(height: 16), action!]
          ])));
}
