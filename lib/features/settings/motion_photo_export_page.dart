import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_palette.dart';
import '../../platform/motion_photo_api.dart';

class MotionPhotoExportPage extends StatefulWidget {
  const MotionPhotoExportPage({super.key});

  @override
  State<MotionPhotoExportPage> createState() => _MotionPhotoExportPageState();
}

class _MotionPhotoExportPageState extends State<MotionPhotoExportPage> {
  static const _api = MotionPhotoApi();
  static const _photoTypes = XTypeGroup(
    label: 'JPEG',
    extensions: ['jpg', 'jpeg'],
    mimeTypes: ['image/jpeg'],
  );
  static const _videoTypes = XTypeGroup(
    label: 'MP4',
    extensions: ['mp4'],
    mimeTypes: ['video/mp4'],
  );

  XFile? _photo;
  XFile? _video;
  bool _choosing = false;
  bool _exporting = false;
  bool _exported = false;
  String? _error;

  bool get _busy => _choosing || _exporting;

  Future<void> _choose({required bool photo}) async {
    setState(() => _choosing = true);
    try {
      // The Android file selector returns a local copy in the app cache.
      final file = await openFile(
        acceptedTypeGroups: [photo ? _photoTypes : _videoTypes],
      );
      if (file == null || !mounted) return;
      setState(() {
        if (photo) {
          _photo = file;
        } else {
          _video = file;
        }
        _exported = false;
        _error = null;
      });
    } on Exception {
      if (mounted) {
        setState(() {
          _exported = false;
          _error = photo ? '无法读取照片，请重新选择 JPEG' : '无法读取短片，请重新选择 MP4';
        });
      }
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  Future<void> _export() async {
    final photo = _photo;
    final video = _video;
    if (_busy || photo == null || video == null) return;
    setState(() {
      _exporting = true;
      _exported = false;
      _error = null;
    });
    try {
      await _api.export(photo.path, video.path, photo.name);
      if (mounted) setState(() => _exported = true);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? '导出失败，请重试');
    } on Exception {
      if (mounted) setState(() => _error = '导出失败，请重试');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_exporting,
        child: Scaffold(
          appBar: AppBar(title: const Text('导出动态照片')),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  '手动选择同一次拍摄的 JPEG 照片和 MP4 短片。原文件会保留。',
                  style: TextStyle(color: context.palette.muted),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('选择 JPEG 照片'),
                  subtitle: Text(_photo?.name ?? '未选择'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _choose(photo: true),
                ),
                Divider(height: 1, color: context.palette.divider),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.movie_outlined),
                  title: const Text('选择 MP4 短片'),
                  subtitle: Text(_video?.name ?? '未选择'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _choose(photo: false),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy || _photo == null || _video == null
                      ? null
                      : _export,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('保存到系统相册'),
                ),
                if (_exporting || _exported || _error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error ?? (_exported ? '已保存到系统相册' : '正在保存动态照片…'),
                      style: TextStyle(
                        color: _error == null
                            ? context.palette.muted
                            : context.palette.danger,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}
