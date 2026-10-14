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
import 'camera_transfer.dart';

final cameraGalleryServiceProvider = Provider<CameraGalleryService>((ref) {
  final transport = ref.read(cameraGatewaysProvider).transport;
  return CameraGalleryService(CameraApi(transport), CameraDeviceHostApi());
});

class CameraGalleryService {
  CameraGalleryService(this.api, this.host);

  final transferGate = CameraTransferGate();

  final CameraApi api;
  final CameraDeviceHostApi host;

  Future<List<CameraFile>> photos() async =>
      (await api.photos()).where((file) => file.downloadable).toList();

  Future<Uint8List> thumbnail(CameraFile file) =>
      transferGate.thumbnail(() => api.thumbnail(file));

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
  late final CameraGalleryService _service;
  List<CameraFile> _files = const [];
  final _selected = <String>{};
  final _saved = <String>{};
  final _thumbnails = <String, Future<Uint8List>>{};
  bool _loading = false;
  bool _downloading = false;
  bool _selectionMode = false;
  int _session = 0;
  String _format = '全部';
  String? _currentFile;
  String? _result;
  final _failures = <String, String>{};

  bool _included(CameraFile file) =>
      _format == '全部' ||
      (_format == '仅 RAW' ? file.extension == 'DNG' : file.extension != 'DNG');
  String? _error;
  int _completed = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _service = ref.read(cameraGalleryServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          ref.read(connectionControllerProvider) is ConnectionReady) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void dispose() {
    _session++;
    _service.transferGate.invalidate();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading || _downloading) return;
    final session = _session;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await _service.photos();
      if (!mounted || session != _session) return;
      setState(() {
        _files = files;
        _selected.removeWhere((id) => !files.any((f) => f.remoteId == id));
        _thumbnails.clear();
      });
    } catch (_) {
      if (mounted && session == _session) {
        setState(() => _error = '读取相机照片失败，请检查相机连接后重试');
      }
    } finally {
      if (mounted && session == _session) setState(() => _loading = false);
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
    final session = _session;
    final service = _service;
    var successes = 0;
    _failures.clear();
    _result = null;
    try {
      await service.transferGate.originals(() async {
        for (final file in files) {
          if (!mounted || session != _session) break;
          if (ref.read(connectionControllerProvider) is! ConnectionReady) break;
          setState(() => _currentFile = file.file);
          try {
            await service.download(file);
            if (!mounted || session != _session) break;
            successes++;
            _saved.add(file.remoteId);
            _selected.remove(file.remoteId);
          } catch (error) {
            if (!mounted || session != _session) break;
            _failures[file.remoteId] = error.toString();
            _selected.add(file.remoteId);
          }
          if (mounted && session == _session) setState(() => _completed++);
        }
      });
    } catch (error) {
      if (!mounted || session != _session) return;
      for (final file in files) {
        if (!_saved.contains(file.remoteId)) {
          _failures[file.remoteId] = error.toString();
          _selected.add(file.remoteId);
        }
      }
    } finally {
      if (mounted && session == _session) setState(() => _downloading = false);
    }
    if (!mounted || session != _session) return;
    setState(() {
      _downloading = false;
      _currentFile = null;
      _result = '保存完成 · 成功 $successes / ${files.length} 个文件';
      if (_failures.isNotEmpty) {
        _selectionMode = true;
        _error = '${_failures.length} 个文件保存失败，已保留选择，可再次保存重试';
      }
    });
  }

  void _toggle(List<CameraFile> files) {
    if (_downloading) return;
    final ids = files.where(_included).map((f) => f.remoteId).toList();
    setState(() {
      _selectionMode = true;
      if (ids.every(_selected.contains)) {
        _selected.removeAll(ids);
      } else {
        _selected.addAll(ids);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(connectionControllerProvider) is ConnectionReady;
    ref.listen(connectionControllerProvider, (previous, next) {
      if (previous is ConnectionReady && next is! ConnectionReady) {
        setState(() {
          _session++;
          _service.transferGate.invalidate();
          _files = const [];
          _selected.clear();
          _saved.clear();
          _thumbnails.clear();
          _failures.clear();
          _selectionMode = false;
          _loading = false;
          _downloading = false;
          _error = null;
          _currentFile = null;
          _result = null;
        });
      }
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
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('相机照片',
                  style:
                      TextStyle(color: GRemoteColors.goldSoft, fontSize: 12)),
              const SizedBox(height: 4),
              Text('${groups.length} 张 · ${_files.length} 个文件',
                  style: const TextStyle(
                      color: GRemoteColors.muted, fontSize: 11)),
            ],
          )),
          TextButton(
            onPressed: _downloading
                ? null
                : () => setState(() {
                      _selectionMode = !_selectionMode;
                      if (!_selectionMode) _selected.clear();
                    }),
            child: Text(_selectionMode ? '取消' : '多选'),
          ),
          IconButton(
              tooltip: '刷新相机图库',
              onPressed: _loading || _downloading ? null : _refresh,
              icon:
                  const Icon(Icons.refresh_rounded, color: GRemoteColors.gold)),
        ]),
      ),
      if (_selectionMode)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: GRemoteColors.raised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: GRemoteColors.divider),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final format in ['全部', '仅 JPEG', '仅 RAW'])
                ChoiceChip(
                  label: Text(format),
                  selected: _format == format,
                  onSelected: _downloading
                      ? null
                      : (_) => setState(() {
                            _format = format;
                            _selected.removeWhere((id) => !_files
                                .any((f) => f.remoteId == id && _included(f)));
                          }),
                ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Expanded(
                  child: Text('轻点照片可多选',
                      style:
                          TextStyle(color: GRemoteColors.muted, fontSize: 12))),
              TextButton(
                  onPressed: _downloading
                      ? null
                      : () => setState(() {
                            _selected.addAll(
                                _files.where(_included).map((f) => f.remoteId));
                          }),
                  child: const Text('全选')),
              TextButton(
                  onPressed:
                      _downloading ? null : () => setState(_selected.clear),
                  child: const Text('清除')),
            ]),
          ]),
        ),
      if (_result != null && !_downloading)
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(_result!,
                style: const TextStyle(color: GRemoteColors.goldSoft))),
      if (_loading)
        const LinearProgressIndicator(
            color: GRemoteColors.gold, backgroundColor: GRemoteColors.divider),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(_error!,
              style: const TextStyle(color: GRemoteColors.danger)),
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
      if (_selectionMode || _downloading)
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            decoration: const BoxDecoration(
                color: GRemoteColors.navy,
                border: Border(top: BorderSide(color: GRemoteColors.divider))),
            child: _downloading
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Row(children: [
                          const Icon(Icons.downloading_rounded,
                              color: GRemoteColors.gold, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                              child: Text('正在保存原图',
                                  style: TextStyle(
                                      color: GRemoteColors.text,
                                      fontWeight: FontWeight.w600))),
                          Text('$_completed / $_total',
                              style:
                                  const TextStyle(color: GRemoteColors.gold)),
                        ]),
                        const SizedBox(height: 8),
                        Text(_currentFile ?? '正在准备下载…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: GRemoteColors.muted, fontSize: 12)),
                        const SizedBox(height: 10),
                        ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                                minHeight: 4,
                                value: _total == 0 ? 0 : _completed / _total,
                                color: GRemoteColors.gold,
                                backgroundColor: GRemoteColors.divider)),
                      ])
                : Row(children: [
                    Expanded(
                        child: Text('已选 ${_selected.length} 个文件',
                            style: const TextStyle(color: GRemoteColors.text))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: FilledButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => _download(_files
                              .where((f) => _selected.contains(f.remoteId))
                              .toList()),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('保存原图'),
                    )),
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
    final preview = _thumbnails.putIfAbsent(
        cover.remoteId, () => _service.thumbnail(cover));
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _downloading
          ? null
          : () => _selectionMode ? _toggle(files) : _showFileSheet(files),
      onLongPress: _downloading ? null : () => _toggle(files),
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
              if (_selectionMode)
                Positioned(
                    top: 10,
                    right: 10,
                    child: Icon(
                        selected > 0
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: GRemoteColors.gold,
                        size: 25)),
              if (files.any((file) => _failures.containsKey(file.remoteId)))
                Positioned(
                    bottom: 10,
                    left: 10,
                    child: Tooltip(
                      message: files
                          .where((file) => _failures.containsKey(file.remoteId))
                          .map((file) =>
                              '${file.file}: ${_failures[file.remoteId]}')
                          .join('\n'),
                      child: const Chip(
                          label: Text('保存失败'),
                          avatar: Icon(Icons.error_outline,
                              size: 16, color: GRemoteColors.danger)),
                    )),
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
                            child: Text('保存全部格式 · ${files.length} 个文件'))),
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
