import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../camera/http/camera_files.dart';
import '../../camera/recipe/shooting_recipe.dart';
import '../camera/shooting_recipes_page.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import '../../darkroom/darkroom_providers.dart';
import '../../film/capture/camera_roll_importer.dart';
import '../../film/catalog/official_lut_selection.dart';
import '../../darkroom/model/edit_document.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/widgets/workspace_tabs.dart';
import '../../darkroom/export/export_queue.dart';
import '../../darkroom/model/export_recipe.dart';
import '../../media/local/local_media_repository.dart';
import '../../media/local/media_gateway.dart';
import 'library_controller.dart';
import 'camera_gallery.dart';
import 'widgets/media_grid.dart';
import 'widgets/recipe_sheet.dart';
import '../film_workbench/workbench_providers.dart';
import '../film_workbench/rolls_page.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import 'live_gallery_page.dart';
import 'album_theme.dart';

final albumPhotoPickerProvider = Provider<Future<List<XFile>> Function()>(
    (ref) => () => openFiles(acceptedTypeGroups: const [
          XTypeGroup(
              label: 'JPEG',
              extensions: ['jpg', 'jpeg'],
              mimeTypes: ['image/jpeg'])
        ]));
final albumTemporaryDirectoryProvider =
    Provider<Future<Directory> Function()>((ref) => getTemporaryDirectory);

enum _Source { local, camera }

enum AlbumSection { photos, rolls, live }

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage(
      {super.key,
      this.initialCamera = false,
      this.initialSection = AlbumSection.photos});
  final bool initialCamera;
  final AlbumSection initialSection;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  late var _source = widget.initialCamera ? _Source.camera : _Source.local;
  late AlbumSection _section = widget.initialSection;
  bool _busy = false, _selectMode = false;
  late bool _cameraVisited = widget.initialCamera;
  late final AppLifecycleListener _lifecycle;

  LibraryController get _controller =>
      ref.read(libraryControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Permission may change in system settings while we are away.
    _lifecycle = AppLifecycleListener(onResume: () => _controller.refresh());
    Future.microtask(_controller.refresh);
  }

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCamera && !oldWidget.initialCamera) {
      _source = _Source.camera;
      _cameraVisited = true;
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final connected =
        ref.watch(connectionControllerProvider) is ConnectionReady;
    return Theme(
        data: albumTheme(context),
        child: Builder(
            builder: (context) => Scaffold(
                  body: SafeArea(
                    bottom: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                          child: Row(children: [
                            const Expanded(
                                child: Text('相册',
                                    style: TextStyle(
                                        fontSize: 27,
                                        fontWeight: FontWeight.w700))),
                            Text(connected ? '● 已连接' : '离线',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: context.palette.muted)),
                            if (_section == AlbumSection.photos)
                              IconButton(
                                  tooltip: '导入照片',
                                  onPressed: _busy ? null : _importPhotos,
                                  icon: const Icon(Icons.add)),
                            if (_section == AlbumSection.photos)
                              PopupMenuButton<String>(
                                  tooltip: '更多',
                                  icon: const Icon(Icons.more_horiz),
                                  onSelected: (value) {
                                    if (value == 'select') {
                                      setState(() {
                                        _section = AlbumSection.photos;
                                        _source = _Source.local;
                                        _selectMode = true;
                                      });
                                    } else if (value == 'rolls') {
                                      setState(
                                          () => _section = AlbumSection.rolls);
                                    } else {
                                      context.push('/darkroom');
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'select',
                                            child: Text('选择照片')),
                                        PopupMenuItem(
                                            value: 'resources',
                                            child: Text('LUT 与出图方案')),
                                      ]),
                          ]),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: Row(children: [
                            for (final entry in const [
                              (AlbumSection.photos, '照片'),
                              (AlbumSection.rolls, '胶卷'),
                              (AlbumSection.live, 'Live · 暂不可用')
                            ])
                              Padding(
                                  padding: const EdgeInsets.only(right: 28),
                                  child: InkWell(
                                      key: ValueKey(
                                          'album-tab-${entry.$1.name}'),
                                      onTap: () =>
                                          setState(() => _section = entry.$1),
                                      child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                          decoration: BoxDecoration(
                                              border: Border(
                                                  bottom: BorderSide(
                                                      color: _section == entry.$1
                                                          ? context
                                                              .palette.accent
                                                          : Colors.transparent,
                                                      width: 2))),
                                          child: Text(entry.$2,
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: _section == entry.$1
                                                      ? FontWeight.w700
                                                      : FontWeight.w400,
                                                  color:
                                                      _section == entry.$1 ? context.palette.text : context.palette.muted))))),
                          ]),
                        ),
                        if (_section == AlbumSection.photos)
                          Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              child: WorkspaceTabs<_Source>(
                                items: const [
                                  (_Source.local, '手机'),
                                  (_Source.camera, '相机')
                                ],
                                value: _source,
                                onChanged: (next) {
                                  if (next == _Source.local) {
                                    unawaited(_controller.refresh());
                                  }
                                  setState(() {
                                    _source = next;
                                    if (next == _Source.camera) {
                                      _cameraVisited = true;
                                    }
                                  });
                                },
                              )),
                        if (_busy) const LinearProgressIndicator(minHeight: 2),
                        Expanded(
                          child: _section == AlbumSection.rolls
                              ? const RollsPage()
                              : _section == AlbumSection.live
                                  ? const LiveGalleryPage()
                                  : IndexedStack(
                                      index: _source.index,
                                      children: [
                                          _LocalLibrary(
                                              state: state,
                                              controller: _controller,
                                              selecting: _selectMode ||
                                                  state.selecting,
                                              onLongPress: _photoActions),
                                          if (_cameraVisited)
                                            const CameraGallery()
                                          else
                                            const SizedBox.shrink(),
                                        ]),
                        ),
                      ],
                    ),
                  ),
                  bottomNavigationBar: _section == AlbumSection.photos &&
                          (_selectMode || state.selecting) &&
                          _source == _Source.local
                      ? _SelectionBar(
                          count: state.selected.length,
                          showConfirm: state.selectedHasUnconfirmedWeak,
                          onCancel: () {
                            _controller.clearSelection();
                            setState(() => _selectMode = false);
                          },
                          onExport: _startBatch,
                          onRecipeExport: _startRecipeBatch,
                          onConfirm: _controller.confirmSelectedTags,
                        )
                      : null,
                )));
  }

  Future<void> _importPhotos() async {
    setState(() => _busy = true);
    Directory? temp;
    try {
      final files = await ref.read(albumPhotoPickerProvider)();
      if (files.isEmpty) return;
      temp = await (await ref.read(albumTemporaryDirectoryProvider)())
          .createTemp('album-import-');
      final gateway = ref.read(mediaGatewayProvider);
      final repo = ref.read(localMediaRepositoryProvider);
      final rollImporter = CameraRollImporter(ref.read(filmRepositoryProvider));
      var done = 0;
      var rollFailures = 0;
      final knownIds = (await gateway.queryImages()).map((e) => e.id).toSet();
      for (final file in files) {
        if (await file.length() > 100000000) {
          throw const MediaException('tooLarge', '单张照片不能超过 100 MB');
        }
        final hash = (await sha256.bind(file.openRead()).first).toString();
        final existing = await repo.importedId(hash);
        final alreadyImported = existing != null && knownIds.contains(existing);
        if (alreadyImported && !Platform.isAndroid) continue;
        final path = '${temp.path}/input.jpg';
        await file.saveTo(path);
        var id = existing;
        if (!alreadyImported) {
          final uri = await gateway.importPhoto(path, file.name);
          await repo.addUriToAlbum(uri, source: 'import', sourceHash: hash);
          id = int.tryParse(Uri.parse(uri).pathSegments.lastOrNull ?? '');
          if (id != null) knownIds.add(id);
          done++;
        }
        if (Platform.isAndroid) {
          try {
            final record = await const MethodChannel('gremote/camera_roll')
                .invokeMapMethod<String, Object?>('readPickedJpeg', path);
            final frame =
                CameraRollFrame.parse(record?['rollFrame'] as String?);
            if (frame != null) {
              await rollImporter.import(
                  CameraFile(dir: localCameraRollDirectory, file: file.name),
                  frame,
                  hash: hash,
                  mediaId: id,
                  filmCode: record?['code'] as int?,
                  recipe: record?['exposureRecipe'] as String?);
              if (mounted) ref.read(filmRollRevisionProvider.notifier).state++;
            }
          } on Exception {
            rollFailures++;
          } on StateError {
            rollFailures++;
          }
        }
      }
      if (mounted) {
        _message(rollFailures == 0
            ? '已导入 $done 张'
            : '已导入 $done 张 · $rollFailures 张未能归入机身胶卷');
      }
    } catch (error) {
      if (mounted) _message('导入失败：$error');
    } finally {
      if (temp != null) await temp.delete(recursive: true);
      if (mounted) {
        setState(() => _busy = false);
        await _controller.refresh();
      }
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _photoActions(LocalMediaItem item) async {
    if (_busy) return;
    final recorded = await ShootingRecipeStore(ref.read(databaseProvider))
        .photoFilm(item.uri);
    if (!mounted) return;
    final body =
        RecordedExposure.parse(recorded?.exposureRecipe, recorded?.code);
    final filmId = body?.filmId ?? recordedBuiltinFilmId(recorded?.code);
    final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('保存'),
                  onTap: () => Navigator.pop(context, 'save')),
              ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('分享'),
                  onTap: () => Navigator.pop(context, 'share')),
              ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text(body != null
                      ? '应用原拍配方'
                      : recorded?.recipe == null
                          ? '查看同款胶卷配方'
                          : '应用手机记录的拍摄配方'),
                  enabled: filmId != null,
                  onTap: filmId == null
                      ? null
                      : () => Navigator.pop(context, 'filmRecipes')),
              ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('选择照片'),
                  onTap: () => Navigator.pop(context, 'select')),
            ])));
    if (!mounted || action == null) return;
    if (action == 'filmRecipes' && filmId != null && recorded != null) {
      try {
        if (await ref.read(mediaGatewayProvider).contentHash(item.id) !=
            recorded.hash) {
          if (mounted) _message('当前照片与保存记录不符');
          return;
        }
      } on Exception {
        if (mounted) _message('暂时无法核对这张原图');
        return;
      }
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
              builder: (_) => ShootingRecipesPage(
                  filmId: filmId,
                  recordedRecipe: recorded.recipe,
                  recordedExposure: body,
                  applyOnOpen: body != null || recorded.recipe != null)));
      return;
    }
    if (action == 'select') {
      _controller.toggle(item.id);
      setState(() => _selectMode = true);
      return;
    }
    setState(() => _busy = true);
    try {
      final doc = await ref.read(darkroomStoreProvider).loadEdit(item.id) ??
          EditDocument(mediaId: item.id, updatedAt: DateTime.now());
      final outcome = await ref.read(exportServiceProvider).export(item, doc);
      if (action == 'share') {
        await ref.read(mediaGatewayProvider).share(outcome.uri);
      } else if (mounted) {
        _message('已保存');
      }
    } catch (error) {
      if (mounted) _message('操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startRecipeBatch() async {
    final result = await _controller.recipeJobs();
    if (!mounted) return;
    if (result.jobs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选照片没有可用的组合配方出图方案')),
      );
      return;
    }
    if (result.skipped > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('部分照片将跳过'),
          content: Text('${result.skipped} 张没有已确认的配方或出图方案。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    final queue = ref.read(exportQueueProvider.notifier);
    if (ref.read(exportQueueProvider).running) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已有导出任务在进行')));
      return;
    }
    unawaited(queue.startEach(result.jobs));
    _controller.clearSelection();
    unawaited(context.push('/export-queue'));
  }

  Future<void> _startBatch() async {
    final items = _controller.selectedItems;
    final recipe = await showModalBottomSheet<ExportRecipe>(
      context: context,
      builder: (_) => RecipeSheet(count: items.length),
    );
    if (recipe == null || !mounted) return;
    final queue = ref.read(exportQueueProvider.notifier);
    if (ref.read(exportQueueProvider).running) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已有导出任务在进行')));
    } else {
      unawaited(queue.start(items, recipe));
      _controller.clearSelection();
    }
    unawaited(context.push('/export-queue'));
  }
}

class _LocalLibrary extends StatelessWidget {
  const _LocalLibrary(
      {required this.state,
      required this.controller,
      required this.selecting,
      required this.onLongPress});
  final bool selecting;
  final ValueChanged<LocalMediaItem> onLongPress;

  final LibraryState state;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final access = state.access;
    if (access == null) {
      return state.error == null
          ? const SizedBox.shrink()
          : Center(child: Text(state.error!));
    }
    if (access == MediaAccess.denied) {
      return _AccessCard(onRequest: controller.requestAccess);
    }
    final scan = state.scan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (access == MediaAccess.partial)
          InkWell(
            onTap: controller.requestAccess,
            child: Container(
              color: context.palette.raised,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text('仅显示你允许的照片 · 继续添加',
                  style: TextStyle(color: context.palette.text, fontSize: 13)),
            ),
          ),
        if (scan != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('正在读取 EXIF ${scan.done}/${scan.total}',
                    style:
                        TextStyle(color: context.palette.muted, fontSize: 12)),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: scan.total == 0 ? 0 : scan.done / scan.total,
                  color: context.palette.accent,
                  backgroundColor: context.palette.divider,
                ),
              ],
            ),
          ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(state.error!,
                style: TextStyle(color: context.palette.danger, fontSize: 12)),
          ),
        Expanded(
          child: state.items.isEmpty
              ? Center(
                  child: Text(
                    scan != null ? '正在整理相册…' : '导入照片，或从相机下载',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : MediaGrid(
                  items: state.items,
                  selected: state.selected,
                  tags: state.tags,
                  onTap: (item) {
                    if (selecting) {
                      controller.toggle(item.id);
                      return;
                    }
                    final lut = officialLutSelection(
                        GoRouterState.of(context).uri.queryParameters['lut']);
                    final target = Uri(
                            path: '/edit/${item.id}',
                            queryParameters: lut == null ? null : {'lut': lut})
                        .toString();
                    if (lut == null) {
                      context.push(target);
                    } else {
                      // A library selection is a one-shot handoff, not a
                      // persistent preset for every later photo/reopen.
                      final router = GoRouter.of(context);
                      router.go('/library');
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) router.push(target);
                      });
                    }
                  },
                  onLongPress: onLongPress,
                ),
        ),
      ],
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.onRequest});

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.photo_library_outlined,
                size: 40, color: context.palette.text),
            const SizedBox(height: 18),
            Text('访问本机照片', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('用于读取和编辑导入的照片。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 22),
            FilledButton(onPressed: onRequest, child: const Text('允许访问照片')),
          ]),
        ),
      );
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.showConfirm,
    required this.onCancel,
    required this.onExport,
    required this.onRecipeExport,
    required this.onConfirm,
  });

  final int count;
  final bool showConfirm;
  final VoidCallback onCancel;
  final VoidCallback onExport;
  final VoidCallback onRecipeExport;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: context.palette.surface,
            border: Border(top: BorderSide(color: context.palette.divider)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              TextButton(onPressed: onCancel, child: const Text('取消')),
              Text('已选 $count', style: TextStyle(color: context.palette.muted)),
              const Spacer(),
              if (showConfirm)
                TextButton(
                  onPressed: () => unawaited(onConfirm()),
                  child: const Text('确认配方'),
                ),
            ]),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onRecipeExport,
                  child: const Text('按配方导出'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onExport,
                  child: Text('批量出图 ($count)'),
                ),
              ),
            ]),
          ]),
        ),
      );
}
