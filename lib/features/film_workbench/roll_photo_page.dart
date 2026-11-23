import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../camera/http/camera_files.dart';
import '../../darkroom/darkroom_providers.dart';
import '../../darkroom/model/edit_document.dart';
import '../../film/model/film_roll.dart';
import '../../media/local/media_gateway.dart';
import '../../media/local/local_media_repository.dart';
import '../darkroom/editor/editor_page.dart';
import '../library/album_theme.dart';
import '../library/photo_preview_surface.dart';

final _savedPhotoPreviewProvider =
    FutureProvider.autoDispose.family<Uint8List?, RollItem>((ref, item) async {
  final id = item.mediaId;
  if (id == null) throw const MediaException('missingOriginal', '手机中的原片暂不可用');
  final gateway = ref.watch(mediaGatewayProvider);
  final before = await gateway.contentHash(id);
  final expected = item.originalPreviewHash;
  if (expected != null && expected != before)
    throw const MediaException('changedOriginal', '原片已变化，请重新读取照片');
  final bytes = await gateway.thumbnail(id, 1024);
  if (await gateway.contentHash(id) != before)
    throw const MediaException('changedOriginal', '原片已变化，请重新读取照片');
  return bytes;
});

class RollPhotoPage extends ConsumerStatefulWidget {
  const RollPhotoPage(this.item, {super.key});
  final RollItem item;
  @override
  ConsumerState<RollPhotoPage> createState() => _RollPhotoPageState();
}

class _RollPhotoPageState extends ConsumerState<RollPhotoPage> {
  bool _busy = false, _saved = false;
  String? _error;
  bool get _raw =>
      widget.item.files.isNotEmpty &&
      widget.item.files.every((file) => file.toUpperCase().endsWith('.DNG'));
  String get _file => widget.item.files.isEmpty
      ? '照片'
      : widget.item.files.firstWhere(
          (file) => !file.toUpperCase().endsWith('.DNG'),
          orElse: () => widget.item.files.first);
  Future<void> _save() async {
    if (_busy || _raw || widget.item.mediaId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = widget.item.mediaId!, gateway = ref.read(mediaGatewayProvider);
      LocalMediaItem? local =
          await ref.read(localMediaRepositoryProvider).find(id);
      if (local == null || local.meta == null) {
        final entry = (await gateway.queryImages())
            .where((entry) => entry.id == id)
            .firstOrNull;
        final meta = (await gateway.readExif([id]))[id];
        if (entry == null || meta == null)
          throw const MediaException('missingOriginal', '手机中的原片暂不可用');
        local = LocalMediaItem(
            id: id,
            uri: entry.uri,
            displayName: entry.displayName,
            dateModified: entry.dateModified,
            dateTaken: entry.dateTaken,
            meta: meta);
      }
      final expected = widget.item.originalPreviewHash;
      if (expected != null && await gateway.contentHash(id) != expected)
        throw const MediaException('changedOriginal', '原片已变化，请重新读取照片');
      final document = await ref.read(darkroomStoreProvider).loadEdit(id) ??
          EditDocument(mediaId: id, updatedAt: DateTime.now());
      await ref.read(exportServiceProvider).export(local, document);
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted)
        setState(() => _error =
            error is MediaException ? error.message ?? '保存失败，请重试' : '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(_savedPhotoPreviewProvider(widget.item));
    return Theme(
        data: albumTheme(context),
        child: PopScope(
            canPop: !_busy,
            child: Scaffold(
              appBar: AppBar(
                  title: Text(baseNameOf(_file),
                      style: const TextStyle(fontSize: 16)),
                  centerTitle: true,
                  actions: [
                    if (!_raw && widget.item.mediaId != null)
                      PopupMenuButton<String>(
                          tooltip: '照片更多',
                          icon: const Icon(Icons.more_horiz),
                          onSelected: (_) => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => EditorPage(
                                      mediaId: widget.item.mediaId!))),
                          itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'edit', child: Text('编辑照片'))
                              ])
                  ]),
              body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                        child: PhotoPreviewSurface(
                            bytes: preview.valueOrNull,
                            raw: _raw,
                            loading: preview.isLoading)),
                    if (preview.hasError)
                      Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                              preview.error is MediaException
                                  ? (preview.error as MediaException).message ??
                                      '原片暂不可用'
                                  : '原片暂不可用',
                              style: TextStyle(
                                  color: context.palette.muted, fontSize: 12))),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: context.palette.danger,
                                  fontSize: 12))),
                    SafeArea(
                        top: false,
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                            child: _raw
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                        Icon(
                                            preview.hasError
                                                ? Icons.info_outline
                                                : Icons.check,
                                            size: 18,
                                            color: context.palette.muted),
                                        const SizedBox(width: 8),
                                        Text(
                                            preview.hasError
                                                ? '原片暂不可用'
                                                : '已保存到手机',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: context.palette.muted))
                                      ])
                                : FilledButton.icon(
                                    onPressed: _busy ||
                                            preview.isLoading ||
                                            preview.hasError ||
                                            _saved
                                        ? null
                                        : _save,
                                    icon: Icon(
                                        _saved
                                            ? Icons.check
                                            : Icons.download_outlined,
                                        size: 18),
                                    label: Text(_busy
                                        ? '正在保存…'
                                        : _saved
                                            ? '已保存到手机'
                                            : '保存照片')))),
                  ]),
            )));
  }
}
