import '../../darkroom/darkroom_providers.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/theme/app_colors.dart';
import '../../settings/preferences_controller.dart';
import '../../app/widgets/workspace_motion.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/gateway/ble_gateway.dart';
import '../../camera/connection/connection_state.dart';
import '../../camera/http/camera_api.dart';
import '../../camera/http/camera_files.dart';
import '../../diagnostics/diagnostic_event.dart';
import '../../diagnostics/diagnostic_store.dart';
import '../../film/capture/camera_roll_importer.dart';
import '../../platform/device_api.g.dart';
import 'camera_transfer.dart';
import 'camera_live_photo_page.dart';
import 'library_controller.dart';
import '../home/import_history.dart';
import '../film_workbench/companion_providers.dart';
import '../film_workbench/workbench_providers.dart';
import '../../camera/recipe/shooting_recipe.dart';
import '../camera/shooting_recipes_page.dart';

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
  final _recordedFilms = <String, int>{};
  final _recordedHashes = <String, String>{};
  final _recordedTimes = <String, int>{};
  final _exposureRecipes = <String, String>{};
  final _photoRecipes = <String, ShootingRecipe>{};
  CameraRollFrame? _currentRollFrame;
  final _clock = Stopwatch()..start();
  final _thumbnails = <String, Future<Uint8List>>{};
  bool _loading = false;
  bool _downloading = false;
  bool _selectionMode = false;
  int _session = 0;
  String? _cameraKey;
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
    final connection = ref.read(connectionControllerProvider);
    if (connection is ConnectionReady) _cameraKey = connection.cameraKey;
    _progressSubscription = _service.events.listen((event) {
      if (!mounted || !_downloading) return;
      if (event.type != 'photoProgress' && event.type != 'photoRecordedFilm') {
        return;
      }
      try {
        final data = jsonDecode(event.jsonPayload);
        if (data is! Map || data['id'] != _currentId) return;
        if (event.type == 'photoRecordedFilm') {
          final code = data['code'];
          final marker = data['rollFrame'];
          _currentRollFrame =
              marker is String ? CameraRollFrame.parse(marker) : null;
          setState(() {
            if (code is int && code >= 0x1001 && code <= 0xffff) {
              _recordedFilms[_currentId!] = code;
            }
            final hash = data['hash'];
            if (hash is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
              _recordedHashes[_currentId!] = hash;
            }
            final time = data['capturedAt'];
            if (time is String) {
              final seconds = wallSecondsOf(time);
              if (seconds != null) _recordedTimes[_currentId!] = seconds;
            }
            final exposure = data['exposureRecipe'];
            if (exposure is String &&
                RegExp(r'^(4d435231[0-9a-f]{152}|4d435232[0-9a-f]{344})$')
                    .hasMatch(exposure)) {
              _exposureRecipes[_currentId!] = exposure;
            }
          });
          return;
        }
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
      _selected.addAll(files.map((f) => f.remoteId));
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
    var rollFailures = 0;
    _failures.clear();
    _result = null;
    try {
      await service.transferGate.originals(() async {
        for (final file in files) {
          if (!mounted || session != _session || _stopAfterCurrent) break;
          if (ref.read(connectionControllerProvider) is! ConnectionReady) break;
          setState(() {
            _recordedHashes.remove(file.remoteId);
            _recordedFilms.remove(file.remoteId);
            _recordedTimes.remove(file.remoteId);
            _exposureRecipes.remove(file.remoteId);
            _photoRecipes.remove(file.remoteId);
            _currentFile = file.file;
            _currentId = file.remoteId;
            _currentRollFrame = null;
            _received = 0;
            _expected = -1;
          });
          try {
            final uri = await service.download(file);
            final metadataStart = _clock.elapsedMicroseconds;
            final code = _recordedFilms[file.remoteId];
            final hash = _recordedHashes[file.remoteId];
            final frame = _currentRollFrame;
            if (frame != null &&
                hash != null &&
                mounted &&
                session == _session) {
              final importer =
                  CameraRollImporter(ref.read(filmRepositoryProvider));
              try {
                final mediaId = await _savedPhotoId(file, uri);
                if (!mounted || session != _session) break;
                await importer.import(file, frame,
                    hash: hash,
                    mediaId: mediaId,
                    filmCode: code,
                    recipe: _exposureRecipes[file.remoteId]);
                if (mounted) {
                  ref.read(filmRollRevisionProvider.notifier).state++;
                }
              } on Exception {
                rollFailures++;
              } on StateError {
                rollFailures++;
              }
            }
            if (code != null &&
                hash != null &&
                mounted &&
                session == _session) {
              try {
                final store = ShootingRecipeStore(ref.read(databaseProvider));
                final seconds = _recordedTimes[file.remoteId];
                final exposure = _exposureRecipes[file.remoteId];
                final camera = _cameraKey;
                final recipe = seconds == null || camera == null
                    ? null
                    : await store.captureRecipe(camera, file, seconds, code);
                await store.rememberPhotoFilm(uri, code, hash,
                    recipe: recipe, exposureRecipe: exposure);
                if (mounted && session == _session) {
                  ref.read(diagnosticStoreProvider).record(DiagnosticEvent(
                      stage: 'photoShootingRecipe',
                      monotonicMicros: metadataStart,
                      durationMs:
                          (_clock.elapsedMicroseconds - metadataStart) ~/ 1000,
                      retryCount: 0,
                      exceptionCode: recipe != null
                          ? null
                          : exposure != null
                              ? 'bodySnapshotStored'
                              : 'filmIdentityOnly'));
                }
                if (recipe != null && mounted && session == _session) {
                  _photoRecipes[file.remoteId] = recipe;
                }
              } on Exception {
                // The original is already saved. Metadata must not mark it failed.
              }
            }
            if (file.file.toLowerCase().endsWith('.jpg') ||
                file.file.toLowerCase().endsWith('.jpeg')) {
              await ref
                  .read(localMediaRepositoryProvider)
                  .addUriToAlbum(uri, source: 'camera');
              // A download can finish after the user has switched to the local grid.
              unawaited(ref.read(libraryControllerProvider.notifier).refresh());
            }
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
      _currentRollFrame = null;
      _currentId = null;
      _result =
          '${_stopAfterCurrent ? '已停止' : '保存完成'} · 成功 $successes / ${files.length} 个文件';
      if (rollFailures > 0) {
        _result = '$_result · $rollFailures 个原片未能归入机身胶卷';
      }
      if (_failures.isNotEmpty) {
        _selectionMode = true;
        _error = '${_failures.length} 个文件保存失败，已保留选择，可再次保存重试';
      }
    });
  }

  Future<int?> _savedPhotoId(CameraFile file, String uri) async {
    if (!Platform.isIOS) {
      return int.tryParse(Uri.parse(uri).pathSegments.lastOrNull ?? '');
    }
    if (file.extension == 'DNG') return null;
    try {
      final entries = await ref.read(mediaGatewayProvider).queryImages();
      return entries.where((entry) => entry.uri == uri).firstOrNull?.id;
    } on Exception {
      // Add-only Photos permission is sufficient to archive the frame.
      return null;
    }
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
    if (_recordedFilms.isNotEmpty) ref.watch(bundledLeicaCameraCatalogProvider);
    final ready = ref.watch(connectionControllerProvider) is ConnectionReady;
    ref.listen(connectionControllerProvider, (previous, next) {
      if (previous is ConnectionReady && next is! ConnectionReady) {
        setState(() {
          _session++;
          _service.transferGate.invalidate();
          _files = const [];
          _thumbnails.clear();
          _selectionMode = _selected.isNotEmpty;
          _loading = false;
          _downloading = false;
          _error = null;
          _currentFile = null;
          _result = null;
        });
      }
      if (next is ConnectionReady &&
          (previous is! ConnectionReady ||
              previous.cameraKey != next.cameraKey)) {
        if (_cameraKey == null || _cameraKey != next.cameraKey) {
          _selected.clear();
          _saved.clear();
          _recordedFilms.clear();
          _recordedHashes.clear();
          _recordedTimes.clear();
          _exposureRecipes.clear();
          _photoRecipes.clear();
          _failures.clear();
          _selectionMode = false;
          _error = null;
        } else if (_selected.isNotEmpty) {
          _selectionMode = true;
          _error = '已保留未完成选择，请核对后重试';
        }
        _cameraKey = next.cameraKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_refresh());
        });
      }
    });
    if (!ready) {
      return const _GalleryEmpty(
        icon: Icons.wifi_off_rounded,
        title: '等待相机连接',
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
                  duration: WorkspaceMotion.duration(context, 180),
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
                                style: TextStyle(
                                    color: context.palette.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Text(
                                _selectionMode
                                    ? '选择要保存的照片'
                                    : '${groups.length} 张',
                                style: TextStyle(
                                    color: context.palette.muted,
                                    fontSize: 11)),
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
                icon: Icon(Icons.refresh_rounded,
                    size: 22, color: context.palette.accent)),
        ]),
      ),
      if (_loading)
        LinearProgressIndicator(minHeight: 2, color: context.palette.accent),
      if (_result != null && !_downloading)
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(_result!,
                style: TextStyle(color: context.palette.text, fontSize: 12))),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(_error!,
                style: TextStyle(
                    color: _error != null
                        ? context.palette.danger
                        : context.palette.text,
                    fontSize: 12))),
      Expanded(
          child: entries.isEmpty && !_loading
              ? _GalleryEmpty(
                  icon: Icons.photo_library_outlined,
                  title: _error == null ? '相机里还没有照片' : '暂时无法显示照片',
                  message: _error == null ? '拍摄后轻点右上角刷新。' : '轻点右上角重试。')
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 3,
                      childAspectRatio: 0.78),
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _tile(entries[index].value))),
      WorkspaceReveal(
          visible: _selectionMode || _downloading, child: _savePanel()),
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
          decoration: BoxDecoration(
              color: context.palette.surface,
              border: Border(top: BorderSide(color: context.palette.divider))),
          child: _downloading
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      Row(children: [
                        Expanded(
                            child: Text('正在保存原图',
                                style: TextStyle(
                                    color: context.palette.text,
                                    fontWeight: FontWeight.w600))),
                        Text('$_completed / $_total 个文件',
                            style: TextStyle(
                                color: context.palette.text, fontSize: 12)),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: Text(_currentFile ?? '正在等待预览传输结束…',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: context.palette.muted,
                                    fontSize: 12))),
                        const SizedBox(width: 12),
                        Text(
                            fraction == null
                                ? _bytes(_received)
                                : '${(fraction * 100).floor()}%',
                            key: const Key('photo-byte-progress'),
                            style: TextStyle(
                                color: context.palette.text, fontSize: 12)),
                      ]),
                      const SizedBox(height: 10),
                      TweenAnimationBuilder<double>(
                          duration: WorkspaceMotion.duration(context, 150),
                          tween: Tween(end: fraction ?? 0),
                          builder: (context, value, _) => ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                  key: const Key('photo-progress-bar'),
                                  minHeight: 4,
                                  value: fraction == null ? null : value,
                                  color: context.palette.accent,
                                  backgroundColor: context.palette.divider))),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: Text(
                                _expected > 0
                                    ? '${_bytes(_received)} / ${_bytes(_expected)}'
                                    : '已接收 ${_bytes(_received)} · 文件大小未知',
                                style: TextStyle(
                                    color: context.palette.muted,
                                    fontSize: 10))),
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
                        Text('保存格式',
                            style: TextStyle(
                                color: context.palette.muted, fontSize: 12)),
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
                                  style: TextStyle(
                                      color: context.palette.text,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 3),
                              Text(
                                  files.isEmpty && _selectedPhotos > 0
                                      ? '所选照片没有此格式'
                                      : '${files.length} 个文件 · ${_format == 'RAW' ? 'DNG 原始文件' : _format == 'JPG' ? 'JPEG 原图' : '两种格式'}',
                                  style: TextStyle(
                                      color: context.palette.muted,
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
      borderRadius: BorderRadius.zero,
      onTap: _downloading
          ? null
          : () => _selectionMode ? _toggle(files) : _showFileSheet(files),
      onLongPress: _downloading ? null : () => _toggle(files),
      enableFeedback: ref
          .watch(appPreferencesProvider.select((s) => s.preferences.haptics)),
      child: AnimatedContainer(
        duration: WorkspaceMotion.duration(context, 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
            color: context.palette.raised,
            borderRadius: BorderRadius.zero,
            border: Border.all(
                color: selected > 0
                    ? context.palette.accent
                    : context.palette.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: ClipRRect(
            borderRadius: BorderRadius.zero,
            child: Stack(fit: StackFit.expand, children: [
              FutureBuilder<Uint8List>(
                  future: preview,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return Image.memory(snapshot.data!,
                          fit: BoxFit.cover, gaplessPlayback: true);
                    }
                    return ColoredBox(
                        color: context.palette.surface,
                        child: Icon(Icons.photo_camera_back_outlined,
                            color: context.palette.muted, size: 34));
                  }),
              if (_selectionMode)
                Positioned(
                    top: 10,
                    right: 10,
                    child: AnimatedContainer(
                      duration: WorkspaceMotion.duration(context, 180),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected > 0
                              ? context.palette.accent
                              : Colors.black45,
                          border: Border.all(
                              color: selected > 0
                                  ? context.palette.accent
                                  : Colors.white70,
                              width: 1.5)),
                      child: AnimatedSwitcher(
                          duration: WorkspaceMotion.duration(context, 150),
                          child: selected > 0
                              ? Icon(Icons.check_rounded,
                                  key: const ValueKey(true),
                                  color: context.palette.background,
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
                      child: Chip(
                          label: const Text('保存失败'),
                          avatar: Icon(Icons.error_outline,
                              size: 16, color: context.palette.danger)),
                    )),
              if (saved == files.length)
                Positioned(
                    top: 10,
                    left: 10,
                    child: Icon(Icons.download_done_rounded,
                        color: context.palette.text)),
            ]),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 7, 6, 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cover.baseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.palette.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 3),
              Text(
                  files
                      .map((f) => f.extension == 'DNG' ? 'RAW' : 'JPG')
                      .join(' + '),
                  style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 9,
                      letterSpacing: 0.5)),
            ]),
          ),
        ]),
      ),
    );
  }

  String? _recordedFilmLabel(CameraFile file) {
    final code = _recordedFilms[file.remoteId];
    if (code == null) return null;
    if (code >= 0x2000) return '拍摄胶卷：自定义胶卷';
    final id = code - 0x1000;
    final catalog = ref.read(bundledLeicaCameraCatalogProvider).valueOrNull;
    final name =
        catalog?.entries.where((entry) => entry.id == id).firstOrNull?.name;
    return name == null ? '拍摄胶卷：编号 $id' : '拍摄胶卷：$name';
  }

  void _showFileSheet(List<CameraFile> files) {
    final jpeg = files.where((file) => file.extension != 'DNG').firstOrNull;
    final exposure = files
        .map((file) => RecordedExposure.parse(
            _exposureRecipes[file.remoteId], _recordedFilms[file.remoteId]))
        .whereType<RecordedExposure>()
        .firstOrNull;
    final recorded = files
        .map((file) => _photoRecipes[file.remoteId])
        .whereType<ShootingRecipe>()
        .firstOrNull;
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
                child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(files.first.baseName,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text('选择要保存的原始文件',
                        style: TextStyle(color: context.palette.muted)),
                    const SizedBox(height: 18),
                    for (final file in files)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                            file.extension == 'DNG'
                                ? Icons.raw_on_outlined
                                : Icons.image_outlined,
                            color: context.palette.accent),
                        title: Text(file.file),
                        subtitle: Text(_recordedFilmLabel(file) ??
                            (file.extension == 'DNG' ? 'RAW 原始文件' : 'JPEG 原图')),
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
                    if (jpeg != null &&
                        defaultTargetPlatform == TargetPlatform.android)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.motion_photos_on_outlined),
                        title: const Text('读取动态照片'),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CameraLivePhotoPage(jpeg),
                            ),
                          );
                        },
                      ),
                    if (recorded != null || exposure != null)
                      FilledButton.tonal(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => ShootingRecipesPage(
                                      recordedRecipe: recorded,
                                      recordedExposure: exposure,
                                      applyOnOpen: true)));
                        },
                        child:
                            Text(exposure == null ? '应用手机记录的拍摄配方' : '应用原拍配方'),
                      ),
                    ...files
                        .map((file) => recordedBuiltinFilmId(
                            _recordedFilms[file.remoteId]))
                        .whereType<int>()
                        .toSet()
                        .map((id) => TextButton(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                Navigator.of(context, rootNavigator: true).push(
                                    MaterialPageRoute<void>(
                                        builder: (_) =>
                                            ShootingRecipesPage(filmId: id)));
                              },
                              child: const Text('查看同款胶卷配方'),
                            )),
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
          Icon(icon, size: 44, color: context.palette.text),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.muted)),
        ]),
      ));
}
