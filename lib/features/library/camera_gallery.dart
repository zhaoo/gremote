import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/theme/app_colors.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../../camera/http/camera_api.dart';
import '../../camera/http/camera_files.dart';
import '../../platform/device_api.g.dart';

final cameraGalleryServiceProvider = Provider<CameraGalleryService>((ref) {
  final transport = ref.read(cameraGatewaysProvider).transport;
  return CameraGalleryService(CameraApi(transport), CameraDeviceHostApi());
});

class CameraGalleryService {
  const CameraGalleryService(this.api, this.host);

  final CameraApi api;
  final CameraDeviceHostApi host;

  Future<List<CameraFile>> photos() async =>
      (await api.photos()).where((file) => file.downloadable).toList();

  Future<Uint8List> thumbnail(CameraFile file) => api.thumbnail(file);

  Future<String> download(CameraFile file) async {
    if (!file.downloadable) throw ArgumentError.value(file.file, 'file');
    if (await host.androidSdkInt() < 29 &&
        !(await Permission.storage.request()).isGranted) {
      throw StateError('Storage permission denied');
    }
    return host.downloadPhoto(file.dir, file.file);
  }
}

class CameraGallery extends ConsumerStatefulWidget {
  const CameraGallery({super.key});

  @override
  ConsumerState<CameraGallery> createState() => _CameraGalleryState();
}

class _CameraGalleryState extends ConsumerState<CameraGallery> {
  List<CameraFile> _files = const [];
  final _selected = <String>{};
  final _saved = <String>{};
  final _thumbnails = <String, Future<Uint8List>>{};
  bool _loading = false;
  bool _downloading = false;
  String? _error;
  int _completed = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          ref.read(connectionControllerProvider) is ConnectionReady) {
        unawaited(_refresh());
      }
    });
  }

  Future<void> _refresh() async {
    if (_loading || _downloading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await ref.read(cameraGalleryServiceProvider).photos();
      if (!mounted) return;
      setState(() {
        _files = files;
        _selected.removeWhere((id) => !files.any((f) => f.remoteId == id));
        _thumbnails.clear();
      });
    } catch (_) {
      if (mounted) setState(() => _error = '读取相机照片失败，请检查相机连接后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(List<CameraFile> files) async {
    if (_downloading || files.isEmpty) return;
    setState(() {
      _downloading = true;
      _completed = 0;
      _total = files.length;
      _error = null;
    });
    var failures = 0;
    for (final file in files) {
      if (!mounted) break;
      if (ref.read(connectionControllerProvider) is! ConnectionReady) {
        failures += files.length - _completed;
        break;
      }
      try {
        await ref.read(cameraGalleryServiceProvider).download(file);
        _saved.add(file.remoteId);
        _selected.remove(file.remoteId);
      } catch (_) {
        failures++;
      }
      if (mounted) setState(() => _completed++);
    }
    if (!mounted) return;
    setState(() {
      _downloading = false;
      if (failures > 0) _error = '$failures 个文件下载失败，请确认 Wi-Fi、相机电量和手机空间';
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failures == 0
          ? '已保存 ${files.length} 个原图到系统相册'
          : '已保存 ${files.length - failures} 个，失败 $failures 个'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(connectionControllerProvider) is ConnectionReady;
    ref.listen(connectionControllerProvider, (previous, next) {
      if (previous is! ConnectionReady && next is ConnectionReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_refresh());
        });
      }
    });
    if (!ready) {
      return const _GalleryEmpty(
        icon: Icons.wifi_off_rounded,
        title: '等待 GR III 连接',
        message: '先在首页连接相机 Wi-Fi，再浏览和下载原图。',
      );
    }
    final groups = <String, List<CameraFile>>{};
    for (final file in _files) {
      groups.putIfAbsent('${file.dir}/${file.baseName}', () => []).add(file);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
        child: Row(children: [
          const Icon(Icons.circle, size: 8, color: GRemoteColors.gold),
          const SizedBox(width: 9),
          const Text('GR III  ·  CAMERA ROLL',
              style: TextStyle(
                  color: GRemoteColors.goldSoft,
                  fontSize: 11,
                  letterSpacing: 1.2)),
          const Spacer(),
          Text('${_files.length} 个文件',
              style: const TextStyle(color: GRemoteColors.muted, fontSize: 12)),
          IconButton(
              tooltip: '刷新相机图库',
              onPressed: _loading ? null : _refresh,
              icon:
                  const Icon(Icons.refresh_rounded, color: GRemoteColors.gold)),
        ]),
      ),
      if (_loading)
        const LinearProgressIndicator(
            color: GRemoteColors.gold, backgroundColor: GRemoteColors.divider),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(_error!,
              style: const TextStyle(color: GRemoteColors.danger)),
        ),
      if (_downloading)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(children: [
            Text('正在保存原图  $_completed / $_total',
                style: const TextStyle(
                    color: GRemoteColors.goldSoft, fontSize: 12)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: _total == 0 ? 0 : _completed / _total,
                color: GRemoteColors.gold,
                backgroundColor: GRemoteColors.divider),
          ]),
        ),
      Expanded(
          child: entries.isEmpty && !_loading
              ? _GalleryEmpty(
                  icon: Icons.photo_library_outlined,
                  title: _error == null ? '相机里还没有照片' : '暂时无法显示照片',
                  message: _error == null ? '拍摄后轻点右上角刷新。' : '轻点右上角重试。',
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _tile(entries[index].value),
                )),
      if (_selected.isNotEmpty || _downloading)
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            decoration: const BoxDecoration(
                color: GRemoteColors.navy,
                border: Border(top: BorderSide(color: GRemoteColors.divider))),
            child: Row(children: [
              Text('已选 ${_selected.length} 个文件',
                  style: const TextStyle(color: GRemoteColors.text)),
              const Spacer(),
              TextButton(
                  onPressed:
                      _downloading ? null : () => setState(_selected.clear),
                  child: const Text('清除')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _downloading
                    ? null
                    : () => _download(_files
                        .where((f) => _selected.contains(f.remoteId))
                        .toList()),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('下载原图'),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _tile(List<CameraFile> files) {
    final jpeg = files.where((f) => f.extension != 'DNG').firstOrNull;
    final cover = jpeg ?? files.first;
    final selected = files.where((f) => _selected.contains(f.remoteId)).length;
    final saved = files.where((f) => _saved.contains(f.remoteId)).length;
    final preview = _thumbnails.putIfAbsent(cover.remoteId,
        () => ref.read(cameraGalleryServiceProvider).thumbnail(cover));
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showFileSheet(files),
      onLongPress: () => setState(() {
        if (selected == files.length) {
          _selected.removeAll(files.map((f) => f.remoteId));
        } else {
          _selected.addAll(files.map((f) => f.remoteId));
        }
      }),
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: GRemoteColors.raised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color:
                    selected > 0 ? GRemoteColors.gold : GRemoteColors.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            child: Stack(fit: StackFit.expand, children: [
              FutureBuilder<Uint8List>(
                  future: preview,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return Image.memory(snapshot.data!, fit: BoxFit.cover);
                    }
                    return const ColoredBox(
                        color: GRemoteColors.navy,
                        child: Icon(Icons.photo_camera_back_outlined,
                            color: GRemoteColors.muted, size: 34));
                  }),
              if (selected > 0)
                const Positioned(
                    top: 10,
                    right: 10,
                    child: Icon(Icons.check_circle,
                        color: GRemoteColors.gold, size: 25)),
              if (saved == files.length)
                const Positioned(
                    top: 10,
                    left: 10,
                    child: Icon(Icons.download_done_rounded,
                        color: GRemoteColors.goldSoft)),
            ]),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cover.baseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: GRemoteColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(files.map((f) => f.extension).join('  +  '),
                  style: const TextStyle(
                      color: GRemoteColors.gold,
                      fontSize: 10,
                      letterSpacing: 1)),
            ]),
          ),
        ]),
      ),
    );
  }

  void _showFileSheet(List<CameraFile> files) {
    showModalBottomSheet<void>(
        context: context,
        backgroundColor: GRemoteColors.navy,
        builder: (sheetContext) => SafeArea(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(files.first.baseName,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    const Text('选择要保存的原始文件',
                        style: TextStyle(color: GRemoteColors.muted)),
                    const SizedBox(height: 18),
                    for (final file in files)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                            file.extension == 'DNG'
                                ? Icons.raw_on_outlined
                                : Icons.image_outlined,
                            color: GRemoteColors.gold),
                        title: Text(file.file),
                        subtitle: Text(
                            file.extension == 'DNG' ? 'RAW 原始文件' : 'JPEG 原图'),
                        trailing: IconButton(
                            tooltip: '下载 ${file.extension}',
                            onPressed: _downloading
                                ? null
                                : () {
                                    Navigator.pop(sheetContext);
                                    unawaited(_download([file]));
                                  },
                            icon: const Icon(Icons.download_rounded)),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                            onPressed: _downloading
                                ? null
                                : () {
                                    Navigator.pop(sheetContext);
                                    unawaited(_download(files));
                                  },
                            child: Text('全部下载 · ${files.length} 个文件'))),
                  ]),
            )));
  }
}

class _GalleryEmpty extends StatelessWidget {
  const _GalleryEmpty(
      {required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
          child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: GRemoteColors.goldSoft),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: GRemoteColors.muted)),
        ]),
      ));
}
