import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../camera/companion/camera_live_manifest.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../../camera/http/camera_files.dart';
import '../../media/local/camera_live_media.dart';
import '../film_workbench/companion_providers.dart';
import 'camera_gallery.dart';

final _liveCompanionProvider = Provider<CameraLiveApi?>((ref) {
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
  final api = ref.read(_liveCompanionProvider);
  if (api == null) throw const FormatException('当前相机没有可用的动态照片配对服务');
  // A staged pair remains playable after a disconnect. Reject a connection
  // change while staging, before handing either file to the exporter.
  bool sameConnection() =>
      current && identical(ref.read(_liveCompanionProvider), api);
  final pair = await gallery.transferGate.originals(() => sameConnection()
      ? media.prepare(api, photo, isCurrent: sameConnection)
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
  const CameraLivePhotoPage(this.photo, {super.key});

  final CameraFile photo;

  @override
  ConsumerState<CameraLivePhotoPage> createState() =>
      _CameraLivePhotoPageState();
}

class _CameraLivePhotoPageState extends ConsumerState<CameraLivePhotoPage> {
  bool _busy = false;
  bool _saved = false;
  String? _message;

  Future<void> _act(PreparedCameraLivePhoto pair,
      {required bool export}) async {
    if (_busy) return;
    final native = ref.read(cameraLiveMediaProvider).native;
    setState(() {
      _busy = true;
      _message = export ? '正在保存动态照片…' : null;
    });
    try {
      if (export) {
        await native.export(pair.jpeg.path, pair.mp4.path, widget.photo.file,
            presentationTimestampUs: pair.presentationTimestampUs);
        if (mounted) {
          setState(() {
            _saved = true;
            _message = '已保存到系统相册';
          });
        }
      } else {
        await native.preview(pair.mp4.path);
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? '操作失败，请重试');
    } on Exception {
      if (mounted) setState(() => _message = '操作失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pair = ref.watch(_preparedPhotoProvider(widget.photo));
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('相机动态照片')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(widget.photo.file,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              ...pair.when(
                loading: () => const [
                  LinearProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在从相机读取并核对原片和动态短片…'),
                ],
                error: (error, _) => [
                  Text(switch (error) {
                    FormatException(:final message) => message,
                    PlatformException(:final message) => message ?? '无法读取动态照片',
                    _ => '无法读取动态照片，请检查相机连接后重试',
                  }),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () =>
                        ref.invalidate(_preparedPhotoProvider(widget.photo)),
                    child: const Text('重新读取'),
                  ),
                ],
                data: (data) => data == null
                    ? const [Text('这张照片没有配对的动态短片。')]
                    : [
                        AspectRatio(
                          aspectRatio: 3 / 2,
                          child: Image.file(data.jpeg,
                              cacheWidth: 1000,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.image_outlined)),
                        ),
                        const SizedBox(height: 18),
                        OutlinedButton.icon(
                          onPressed:
                              _busy ? null : () => _act(data, export: false),
                          icon: const Icon(Icons.play_arrow_outlined),
                          label: const Text('播放配对短片'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _busy || _saved
                              ? null
                              : () => _act(data, export: true),
                          icon: const Icon(Icons.save_alt),
                          label: const Text('保存动态照片'),
                        ),
                        if (_message != null)
                          Semantics(
                            liveRegion: true,
                            child: Text(_message!,
                                style: TextStyle(color: context.palette.muted)),
                          ),
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
