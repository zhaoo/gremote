import '../../app/release_policy.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'album_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../camera/companion/camera_live_manifest.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../../camera/http/camera_files.dart';
import '../../media/local/camera_live_media.dart';
import '../../platform/motion_photo_api.dart';
import '../film_workbench/companion_providers.dart';
import 'camera_gallery.dart';
import 'live_gallery_controller.dart';
import 'live_gallery_page.dart';

bool get _motionSupported => defaultTargetPlatform == TargetPlatform.android;

final cameraLiveApiProvider = Provider<CameraLiveApi?>((ref) {
  if (!cameraLiveAvailable) return null;
  final identity = ref.watch(effectiveCompanionIdentityProvider);
  final connection = ref.watch(connectionControllerProvider.select((value) =>
      value is ConnectionReady ? (true, value.cameraKey) : (false, null)));
  if (!connection.$1 || identity == null) return null;
  final api = ref.watch(companionApiFactoryProvider)(identity);
  ref.onDispose(api.invalidate);
  return api is CameraLiveApi ? api as CameraLiveApi : null;
});

final cameraLiveMediaProvider =
    Provider<CameraLiveMedia>((ref) => const CameraLiveMedia());

final _preparedPhotoProvider = FutureProvider.autoDispose
    .family<PreparedCameraLivePhoto?, CameraFile>((ref, photo) async {
  final automatic = ref.read(companionHotspotPairingProvider.future);
  final legacy = ref.read(companionIdentityHydrationProvider.future);
  final gallery = ref.watch(cameraGalleryServiceProvider);
  final media = ref.watch(cameraLiveMediaProvider);
  var current = true;
  PreparedCameraLivePhoto? prepared;
  ref.onDispose(() {
    current = false;
    unawaited(prepared?.dispose());
  });
  await Future.wait<Object?>([automatic, legacy]);
  if (!current) return null;
  final api = ref.read(cameraLiveApiProvider);
  if (api == null) throw const FormatException('当前相机没有可用的动态照片配对服务');
  final sourceCameraKey = ref.read(liveCameraArchiveKeyProvider);
  // A staged pair remains playable after a disconnect. Reject a connection
  // change while staging, before handing either file to the exporter.
  bool sameConnection() =>
      current && identical(ref.read(cameraLiveApiProvider), api);
  final pair = await gallery.transferGate.originals(() => sameConnection()
      ? media.prepare(api, photo,
          isCurrent: sameConnection, sourceCameraKey: sourceCameraKey)
      : Future<PreparedCameraLivePhoto?>.value());
  if (!current) {
    await pair?.dispose();
    return null;
  }
  if (pair == null && !sameConnection()) {
    throw const FormatException('相机连接已改变，请重新读取动态照片');
  }
  return prepared = pair;
});

class CameraLivePhotoPage extends ConsumerStatefulWidget {
  const CameraLivePhotoPage(this.photo, {super.key, this.saved});

  final SavedLivePhoto? saved;

  final CameraFile photo;

  @override
  ConsumerState<CameraLivePhotoPage> createState() =>
      _CameraLivePhotoPageState();
}

final _savedPreparedProvider = FutureProvider.autoDispose
    .family<PreparedCameraLivePhoto, SavedLivePhoto>((ref, saved) async {
  final root =
      await (await ref.read(cameraLiveMediaProvider).temporaryDirectory())
          .createTemp('gremote-live-');
  var current = true;
  PreparedCameraLivePhoto? prepared;
  ref.onDispose(() {
    current = false;
    unawaited(prepared?.dispose());
  });
  try {
    final jpeg = await File(saved.jpegPath).copy('${root.path}/still.jpg');
    final mp4 = await File(saved.mp4Path).copy('${root.path}/motion.mp4');
    if (!current) throw const FormatException('已离开 Live 预览');
    return prepared = PreparedCameraLivePhoto(
        root, jpeg, mp4, saved.timestampUs,
        sourceCameraKey: saved.cameraKey);
  } finally {
    if (prepared == null) await root.delete(recursive: true);
  }
});

class _CameraLivePhotoPageState extends ConsumerState<CameraLivePhotoPage> {
  bool _busy = false;
  PreparedCameraLivePhoto? _systemSavedPair, _offlineSavedPair;
  String? _message;
  Future<void> _act(PreparedCameraLivePhoto pair,
      {required bool export}) async {
    if (_busy) return;
    final native = ref.read(cameraLiveMediaProvider).native;
    pair.retain();
    setState(() {
      _busy = true;
      _message = export
          ? identical(_systemSavedPair, pair)
              ? '正在保存离线副本…'
              : '正在保存 Live…'
          : null;
    });
    try {
      if (export) {
        if (!identical(_systemSavedPair, pair)) {
          await native.export(pair.jpeg.path, pair.mp4.path, widget.photo.file,
              presentationTimestampUs: pair.presentationTimestampUs);
          _systemSavedPair = pair;
          if (mounted) setState(() => _message = '已保存到系统相册');
        }
        try {
          await ref
              .read(livePhotoArchiveProvider)
              .save(widget.photo, pair, cameraKey: pair.sourceCameraKey ?? '');
          _offlineSavedPair = pair;
          ref.invalidate(savedLivePhotosProvider);
          if (mounted) setState(() => _message = '已保存到系统相册和手机离线副本');
        } catch (_) {
          if (mounted) {
            setState(() => _message = '已保存到系统相册 · 手机离线副本未能保存，请检查空间后重试');
          }
        }
      } else {
        await native.preview(pair.mp4.path);
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? '操作失败，请重试');
    } on Exception catch (_) {
      if (mounted) setState(() => _message = '操作失败，请重试');
    } finally {
      await pair.release();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportVideo(PreparedCameraLivePhoto pair) async {
    if (_busy) return;
    pair.retain();
    setState(() {
      _busy = true;
      _message = '正在导出视频…';
    });
    try {
      await ref
          .read(cameraLiveMediaProvider)
          .native
          .exportVideo(pair.mp4.path, widget.photo.file);
      if (mounted) setState(() => _message = '视频已保存到系统相册');
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? '视频导出失败，请重试');
    } on Exception catch (_) {
      if (mounted) setState(() => _message = '视频导出失败，请重试');
    } finally {
      await pair.release();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!cameraLiveAvailable) {
      return Scaffold(
          appBar: AppBar(title: const Text('Live')),
          body: const Center(
              child: Text('$cameraLiveUnavailableMessage\n已保存的数据保留',
                  textAlign: TextAlign.center)));
    }
    final AsyncValue<PreparedCameraLivePhoto?> pair = widget.saved == null
        ? ref.watch(_preparedPhotoProvider(widget.photo))
        : ref.watch(_savedPreparedProvider(widget.saved!));
    return Theme(
        data: albumTheme(context),
        child: Builder(
            builder: (context) => PopScope(
                  canPop: !_busy,
                  child: Scaffold(
                    appBar: AppBar(
                        title: Text(widget.photo.baseName,
                            style: const TextStyle(fontSize: 14)),
                        centerTitle: true),
                    body: SafeArea(
                      top: false,
                      child: pair.when(
                        loading: () => const Center(
                            child: Padding(
                                padding: EdgeInsets.all(28),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      LinearProgressIndicator(),
                                      SizedBox(height: 18),
                                      Text('正在核对原片和配对短片…'),
                                      SizedBox(height: 10),
                                      Text('读取期间请保持相机连接',
                                          style: TextStyle(fontSize: 12))
                                    ]))),
                        error: (error, _) => AlbumEmpty(
                            icon: Icons.error_outline,
                            title: '无法读取 Live',
                            message: switch (error) {
                              FormatException(:final message) => message,
                              PlatformException(:final message) =>
                                message ?? '无法读取动态照片',
                              _ => '请检查相机连接后重试'
                            },
                            action: OutlinedButton(
                                onPressed: () {
                                  if (widget.saved == null) {
                                    ref.invalidate(
                                        _preparedPhotoProvider(widget.photo));
                                  } else {
                                    ref.invalidate(
                                        _savedPreparedProvider(widget.saved!));
                                  }
                                },
                                child: const Text('重新读取'))),
                        data: (data) => data == null
                            ? const AlbumEmpty(
                                icon: Icons.motion_photos_off_outlined,
                                title: '尚无配对短片',
                                message: '这张照片没有可读取的 Live 短片。相机生成短片后可重新读取。')
                            : _LivePreview(
                                key: ObjectKey(data),
                                pair: data,
                                title: widget.photo.baseName,
                                saved: widget.saved != null ||
                                    identical(_offlineSavedPair, data),
                                archiveRetry:
                                    identical(_systemSavedPair, data) &&
                                        !identical(_offlineSavedPair, data),
                                busy: _busy,
                                message: _message,
                                onSave: () => _act(data, export: true),
                                onExportVideo: () => _exportVideo(data),
                                onFallbackPlay: () => _act(data, export: false),
                              ),
                      ),
                    ),
                  ),
                )));
  }
}

class _LivePreview extends ConsumerStatefulWidget {
  const _LivePreview(
      {super.key,
      required this.pair,
      required this.title,
      required this.saved,
      required this.archiveRetry,
      required this.busy,
      required this.message,
      required this.onSave,
      required this.onExportVideo,
      required this.onFallbackPlay});
  final PreparedCameraLivePhoto pair;
  final String title;
  final bool saved, busy, archiveRetry;
  final String? message;
  final VoidCallback onSave, onExportVideo, onFallbackPlay;
  @override
  ConsumerState<_LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends ConsumerState<_LivePreview>
    with WidgetsBindingObserver {
  MotionVideoPlayer? _player;
  MotionVideoInfo? _info;
  Timer? _timer;
  int _position = 0;
  bool _playing = false, _showVideo = false, _polling = false;
  String? _error;
  late final MotionPhotoApi _native;
  late final Future<void> _opening;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _native = ref.read(cameraLiveMediaProvider).native;
    widget.pair.retain();
    _opening = _open();
    unawaited(_opening);
  }

  Future<void> _open() async {
    // iOS currently has no motion-photo texture/export channel. It displays
    // the original without presenting unsupported playback/export controls.
    if (!_motionSupported) return;
    try {
      final player = await _native.openPlayer(widget.pair.mp4.path);
      if (!mounted) {
        await _native.playerControl(player.textureId, 'dispose');
        return;
      }
      setState(() => _player = player);
      _timer =
          Timer.periodic(const Duration(milliseconds: 120), (_) => _poll());
      final info = await _native.inspectVideo(widget.pair.mp4.path);
      if (!mounted) return;
      setState(() => _info = info);
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error =
            error is PlatformException ? error.message : '短片播放器准备失败，可重试播放');
      }
    }
  }

  Future<void> _poll() async {
    final player = _player;
    if (!mounted || player == null || _polling || !_playing) return;
    _polling = true;
    try {
      final status = await _native.playerStatus(player.textureId);
      if (mounted) {
        setState(() {
          _position = (status['positionMs'] as int? ?? _position)
              .clamp(0, player.durationMs);
          _playing = status['playing'] == true;
        });
      }
    } on Exception catch (_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _error = '播放已中断，请重新打开 Live';
        });
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _play() async {
    final player = _player;
    if (player == null || widget.busy) {
      if (!widget.busy) widget.onFallbackPlay();
      return;
    }
    try {
      if (_position >= player.durationMs - 50) {
        await _native.playerControl(player.textureId, 'seek', positionMs: 0);
      }
      await _native.playerControl(player.textureId, 'play');
      if (mounted) {
        setState(() {
          _playing = true;
          _showVideo = true;
        });
      }
    } on Exception catch (_) {
      if (mounted) setState(() => _error = '播放失败，请重新打开 Live');
    }
  }

  Future<void> _pause({bool poster = false}) async {
    final player = _player;
    if (player == null) return;
    try {
      await _native.playerControl(player.textureId, 'pause');
    } on Exception catch (_) {/* A disposed native player cannot resume. */}
    if (mounted) {
      setState(() {
        _playing = false;
        if (poster) _showVideo = false;
      });
    }
  }

  Future<void> _seek(double value) async {
    final player = _player;
    if (player == null) return;
    await _pause();
    try {
      await _native.playerControl(player.textureId, 'seek',
          positionMs: value.round());
      if (mounted) {
        setState(() {
          _position = value.round();
          _showVideo = true;
        });
      }
    } on Exception catch (_) {
      if (mounted) setState(() => _error = '无法拖动短片进度，请重试');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_pause());
  }

  Future<void> _close() async {
    try {
      await _opening;
      final player = _player;
      if (player != null) {
        await _native.playerControl(player.textureId, 'dispose');
      }
    } on Exception catch (_) {
      /* The player may have already closed on error. */
    } finally {
      await widget.pair.release();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final duration = player?.durationMs ?? _info?.durationMs;
    final timestamp = widget.pair.presentationTimestampUs;
    return ListView(children: [
      GestureDetector(
          onLongPressStart:
              widget.busy || !_motionSupported ? null : (_) => _play(),
          onLongPressEnd: (_) => _pause(poster: true),
          child: AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                Image.file(widget.pair.jpeg,
                    cacheWidth: 1200,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.image_outlined)),
                if (_showVideo && player != null)
                  Center(
                      child: AspectRatio(
                          aspectRatio: player.width > 0 && player.height > 0
                              ? player.width / player.height
                              : 3 / 2,
                          child: Texture(textureId: player.textureId))),
                const Positioned(top: 16, left: 20, child: AlbumTag('◎ Live')),
                if (!_playing && _motionSupported)
                  Center(
                      child: IconButton.filledTonal(
                          tooltip: '播放 Live',
                          onPressed: widget.busy ? null : _play,
                          iconSize: 36,
                          style: IconButton.styleFrom(
                              backgroundColor: Colors.black45,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(18),
                              side: const BorderSide(color: Colors.white60)),
                          icon: const Icon(Icons.play_arrow_rounded))),
                if (_playing)
                  Positioned(
                      bottom: 10,
                      right: 12,
                      child: IconButton.filledTonal(
                          tooltip: '暂停 Live',
                          onPressed: _pause,
                          icon: const Icon(Icons.pause))),
              ]))),
      Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 36),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700))),
              Text(
                  duration == null
                      ? 'Live'
                      : '${(duration / 1000).toStringAsFixed(1)} 秒',
                  style: TextStyle(color: context.palette.muted, fontSize: 12))
            ]),
            const SizedBox(height: 8),
            Text(
                widget.saved
                    ? '已保存'
                    : widget.archiveRetry
                        ? '系统相册已保存 · 离线副本待保存'
                        : '相机中',
                style: TextStyle(color: context.palette.muted, fontSize: 12)),
            const SizedBox(height: 24),
            if (player != null && player.durationMs > 0) ...[
              if (_info != null)
                ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                        height: 58,
                        child: Row(children: [
                          for (final frame in _info!.frames)
                            Expanded(
                                child: Image.memory(frame,
                                    fit: BoxFit.cover, height: 58))
                        ]))),
              SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12)),
                  child: Slider(
                      key: const ValueKey('live-timeline'),
                      min: 0,
                      max: player.durationMs.toDouble(),
                      value: _position
                          .toDouble()
                          .clamp(0, player.durationMs.toDouble()),
                      onChanged: widget.busy ? null : _seek)),
              Row(children: [
                Text('${(_position / 1000).toStringAsFixed(1)} 秒',
                    style:
                        TextStyle(fontSize: 10, color: context.palette.muted)),
                const Spacer(),
                if (timestamp != null && timestamp <= player.durationMs * 1000)
                  Text('● 快门 ${(timestamp / 1000000).toStringAsFixed(1)} 秒',
                      style: TextStyle(
                          fontSize: 10, color: context.palette.accent)),
                const Spacer(),
                Text('${(player.durationMs / 1000).toStringAsFixed(1)} 秒',
                    style:
                        TextStyle(fontSize: 10, color: context.palette.muted))
              ]),
              const SizedBox(height: 28),
            ],
            Row(children: [
              Expanded(
                  child: FilledButton.icon(
                      onPressed:
                          widget.busy || widget.saved || !_motionSupported
                              ? null
                              : widget.onSave,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(widget.saved
                          ? '已保存 Live'
                          : widget.archiveRetry
                              ? '重试离线保存'
                              : '保存 Live'))),
              if (_motionSupported) ...[
                const SizedBox(width: 10),
                Expanded(
                    child: OutlinedButton(
                        onPressed: widget.busy ? null : widget.onExportVideo,
                        child: const Text('导出视频')))
              ]
            ]),
            const SizedBox(height: 20),
            Text(player == null ? '点按播放配对短片' : '长按照片播放 · 拖动时间轴预览',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.palette.muted, fontSize: 11)),
            if (!_motionSupported) const AlbumNotice('当前设备暂不支持保存 Live 或导出视频'),
            if (_error != null) AlbumNotice(_error!, error: true),
            if (widget.message != null)
              Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Semantics(
                      liveRegion: true,
                      child: Text(widget.message!,
                          style: TextStyle(
                              color: context.palette.muted, fontSize: 12)))),
          ])),
    ]);
  }
}
