import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/theme/app_colors.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/gateway/ble_gateway.dart';
import '../../camera/connection/connection_state.dart';
import '../../camera/http/camera_api.dart';
import '../../camera/http/camera_files.dart';
import '../../platform/device_api.g.dart';
import 'camera_transfer.dart';
import '../home/import_history.dart';

final cameraGalleryServiceProvider = Provider<CameraGalleryService>((ref) {
  final gateways = ref.read(cameraGatewaysProvider);
  return CameraGalleryService(
      CameraApi(gateways.transport), CameraDeviceHostApi(),
      events: gateways.ble.events);
});

class CameraGalleryService {
  CameraGalleryService(this.api, this.host,
      {this.events = const Stream.empty()});
  final Stream<CameraDeviceEvent> events;

  final transferGate = CameraTransferGate();

  final CameraApi api;
  final CameraDeviceHostApi host;

  Future<List<CameraFile>> photos() async =>
      (await api.photos()).where((file) => file.downloadable).toList();

  Future<Uint8List> thumbnail(CameraFile file) =>
      transferGate.thumbnail(() => api.thumbnail(file));

  Future<String> download(CameraFile file) async {
    if (!file.downloadable) throw ArgumentError.value(file.file, 'file');
    if (!Platform.isIOS &&
        await host.androidSdkInt() < 29 &&
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
  String _format = 'RAW+JPG';
  StreamSubscription<CameraDeviceEvent>? _progressSubscription;
  int _received = 0;
  int _expected = -1;
  String? _currentId;
  bool _stopAfterCurrent = false;
  String? _currentFile;
  String? _result;
  final _failures = <String, String>{};

  bool _included(CameraFile file) =>
      _format == 'RAW+JPG' ||
      (_format == 'RAW' ? file.extension == 'DNG' : file.extension != 'DNG');
  List<CameraFile> get _selectedFiles => _files
      .where((file) => _selected.contains(file.remoteId) && _included(file))
      .toList();
  int get _selectedPhotos => _files
      .where((f) => _selected.contains(f.remoteId))
      .map((f) => '${f.dir}/${f.baseName}')
      .toSet()
      .length;
  String? _error;
  int _completed = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _service = ref.read(cameraGalleryServiceProvider);
    _progressSubscription = _service.events.listen((event) {
      if (!mounted || !_downloading || event.type != 'photoProgress') return;
      try {
        final data = jsonDecode(event.jsonPayload);
        if (data is! Map || data['id'] != _currentId) return;
        final bytes = data['bytes'];
        final total = data['total'];
        if (bytes is! int || total is! int || bytes < 0 || bytes < _received) {
          return;
        }
        setState(() {
          _received = bytes;
          _expected = total;
        });
      } on FormatException {
        // Ignore malformed native progress events.
      }
    });
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
    unawaited(_progressSubscription?.cancel());
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
      _stopAfterCurrent = false;
      _currentId = null;
      _currentFile = null;
      _received = 0;
      _expected = -1;
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
          if (!mounted || session != _session || _stopAfterCurrent) break;
          if (ref.read(connectionControllerProvider) is! ConnectionReady) break;
          setState(() {
            _currentFile = file.file;
            _currentId = file.remoteId;
            _received = 0;
            _expected = -1;
          });
          try {
            await service.download(file);
            if (!mounted || session != _session) break;
            successes++;
            ref.invalidate(importHistoryProvider);
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
      _currentId = null;
      _result =
          '${_stopAfterCurrent ? '已停止' : '保存完成'} · 成功 $successes / ${files.length} 个文件';
      if (_failures.isNotEmpty) {
        _selectionMode = true;
        _error = '${_failures.length} 个文件保存失败，已保留选择，可再次保存重试';
      }
    });
  }

  void _toggle(List<CameraFile> files) {
    if (_downloading) return;
    final ids = files.map((f) => f.remoteId).toList();
    setState(() {
      _selectionMode = true;
      if (ids.any(_selected.contains)) {
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
        child: Row(children: [
          Expanded(
              child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      key: ValueKey(_selectionMode),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                _selectionMode
                                    ? '已选 $_selectedPhotos 张'
                                    : '相机照片',
                                style: const TextStyle(
                                    color: GRemoteColors.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Text(
                                _selectionMode
                                    ? '轻点照片选择 · 长按开始多选'
                                    : '${groups.length} 张照片 · 原始画质',
                                style: const TextStyle(
                                    color: GRemoteColors.muted, fontSize: 11)),
                          ])))),
          if (_selectionMode)
            TextButton(
                onPressed: _downloading
                    ? null
                    : () => setState(() {
                          if (_selected.length == _files.length) {
                            _selected.clear();
                          } else {
                            _selected.addAll(_files.map((f) => f.remoteId));
                          }
                        }),
                child: Text(
                    _selected.length == _files.length && _files.isNotEmpty
                        ? '清除'
                        : '全选')),
          TextButton(
              onPressed: _downloading
                  ? null
                  : () => setState(() {
                        _selectionMode = !_selectionMode;
                        if (!_selectionMode) _selected.clear();
                      }),
              child: Text(_selectionMode ? '取消' : '多选')),
          if (!_selectionMode)
            IconButton(
                tooltip: '刷新相机图库',
                onPressed: _loading || _downloading ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded,
                    size: 22, color: GRemoteColors.gold)),
        ]),
      ),
      if (_loading)
        const LinearProgressIndicator(minHeight: 2, color: GRemoteColors.gold),
      if (_result != null && !_downloading)
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(_result!,
                style: const TextStyle(
                    color: GRemoteColors.goldSoft, fontSize: 12))),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(_error!,
                style: TextStyle(
                    color: _error != null
                        ? GRemoteColors.danger
                        : GRemoteColors.goldSoft,
                    fontSize: 12))),
      Expanded(
          child: entries.isEmpty && !_loading
              ? _GalleryEmpty(
                  icon: Icons.photo_library_outlined,
                  title: _error == null ? '相机里还没有照片' : '暂时无法显示照片',
                  message: _error == null ? '拍摄后轻点右上角刷新。' : '轻点右上角重试。')
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.88),
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _tile(entries[index].value))),
      AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: _selectionMode || _downloading
              ? _savePanel()
              : const SizedBox(width: double.infinity)),
    ]);
  }

  Widget _savePanel() {
    final files = _selectedFiles;
    final fraction =
        _expected > 0 ? (_received / _expected).clamp(0.0, 1.0) : null;
    return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: const BoxDecoration(
              color: GRemoteColors.navy,
              border: Border(top: BorderSide(color: GRemoteColors.divider))),
          child: _downloading
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      Row(children: [
                        const Expanded(
                            child: Text('正在保存原图',
                                style: TextStyle(
                                    color: GRemoteColors.text,
                                    fontWeight: FontWeight.w600))),
                        Text('$_completed / $_total 个文件',
                            style: const TextStyle(
                                color: GRemoteColors.goldSoft, fontSize: 12)),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: Text(_currentFile ?? '正在等待预览传输结束…',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: GRemoteColors.muted, fontSize: 12))),
                        const SizedBox(width: 12),
                        Text(
                            fraction == null
                                ? _bytes(_received)
                                : '${(fraction * 100).floor()}%',
                            key: const Key('photo-byte-progress'),
                            style: const TextStyle(
                                color: GRemoteColors.goldSoft, fontSize: 12)),
                      ]),
                      const SizedBox(height: 10),
                      TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 150),
                          tween: Tween(end: fraction ?? 0),
                          builder: (context, value, _) => ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                  key: const Key('photo-progress-bar'),
                                  minHeight: 4,
                                  value: fraction == null ? null : value,
                                  color: GRemoteColors.gold,
                                  backgroundColor: GRemoteColors.divider))),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: Text(
                                _expected > 0
                                    ? '${_bytes(_received)} / ${_bytes(_expected)}'
                                    : '已接收 ${_bytes(_received)} · 文件大小未知',
                                style: const TextStyle(
                                    color: GRemoteColors.muted, fontSize: 10))),
                        TextButton(
                            onPressed: _stopAfterCurrent
                                ? null
                                : () =>
                                    setState(() => _stopAfterCurrent = true),
                            child: Text(_stopAfterCurrent ? '正在收尾' : '停止后续')),
                      ]),
                    ])
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      Row(children: [
                        const Text('保存格式',
                            style: TextStyle(
                                color: GRemoteColors.muted, fontSize: 12)),
                        const SizedBox(width: 14),
                        Expanded(
                            child: SegmentedButton<String>(
                                style: SegmentedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    textStyle: const TextStyle(fontSize: 11)),
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(
                                      value: 'JPG', label: Text('JPG')),
                                  ButtonSegment(
                                      value: 'RAW', label: Text('RAW')),
                                  ButtonSegment(
                                      value: 'RAW+JPG', label: Text('RAW+JPG'))
                                ],
                                selected: {_format},
                                onSelectionChanged: (value) =>
                                    setState(() => _format = value.single))),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('已选 $_selectedPhotos 张',
                                  style: const TextStyle(
                                      color: GRemoteColors.text,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 3),
                              Text(
                                  files.isEmpty && _selectedPhotos > 0
                                      ? '所选照片没有此格式'
                                      : '${files.length} 个文件 · ${_format == 'RAW' ? 'DNG 原始文件' : _format == 'JPG' ? 'JPEG 原图' : '两种格式'}',
                                  style: const TextStyle(
                                      color: GRemoteColors.muted,
                                      fontSize: 10)),
                            ])),
                        const SizedBox(width: 12),
                        Expanded(
                            child: FilledButton.icon(
                                onPressed: files.isEmpty
                                    ? null
                                    : () => _download(files),
                                icon: const Icon(Icons.download_rounded,
                                    size: 18),
                                label: const Text('保存原图'))),
                      ]),
                    ]),
        ));
  }

  String _bytes(int value) => value < 1024 * 1024
      ? '${(value / 1024).toStringAsFixed(0)} KB'
      : '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';

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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
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
                      return Image.memory(snapshot.data!,
                          fit: BoxFit.cover, gaplessPlayback: true);
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
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected > 0
                              ? GRemoteColors.gold
                              : Colors.black45,
                          border: Border.all(
                              color: selected > 0
                                  ? GRemoteColors.gold
                                  : Colors.white70,
                              width: 1.5)),
                      child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: selected > 0
                              ? const Icon(Icons.check_rounded,
                                  key: ValueKey(true),
                                  color: GRemoteColors.night,
                                  size: 18)
                              : const SizedBox(key: ValueKey(false))),
                    )),
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
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 3),
              Text(
                  files
                      .map((f) => f.extension == 'DNG' ? 'RAW' : 'JPG')
                      .join(' + '),
                  style: const TextStyle(
                      color: GRemoteColors.muted,
                      fontSize: 9,
                      letterSpacing: 0.5)),
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
