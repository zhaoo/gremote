import 'dart:convert';
import '../../camera/companion/camera_film_catalog.dart';
import '../../film/catalog/film_catalog.dart';
import 'companion_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../film/capture/active_roll_context.dart';
import '../../film/model/film_recipe.dart';
import '../../film/model/film_roll.dart';
import '../../film/store/film_repository.dart';
import 'roll_detail_page.dart';
import 'workbench_providers.dart';
import '../../camera/companion/camera_roll_index.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../library/live_gallery_page.dart';
import 'camera_roll_detail_page.dart';
import 'widgets/workbench_style.dart';
import 'roll_archive_actions.dart';

class RollsPage extends ConsumerStatefulWidget {
  const RollsPage({super.key});
  @override
  ConsumerState<RollsPage> createState() => _RollsPageState();
}

class _RollsPageState extends ConsumerState<RollsPage> {
  int _source = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(cameraRollIndexProvider.notifier).refresh());
  }

  Future<void> _new() async {
    try {
      final catalog = await ref.read(filmCatalogProvider.future);
      if (!mounted) return;
      final recipe = ref.read(selectedFilmRecipeProvider) ?? catalog.recipe(33);
      final roll = await showCreateRollSheet(
          context, ref.read(filmRepositoryProvider), recipe);
      if (roll != null) {
        ref.read(filmRollRevisionProvider.notifier).state++;
        ref.read(activeRollCaptureContextProvider.notifier).state =
            FrozenRollContext(
                rollId: roll.id, recipeJson: jsonEncode(recipe.toJson()));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  void _openCamera(CameraIndexedRoll roll) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CameraRollDetailPage(roll)));
  @override
  Widget build(BuildContext context) {
    ref.listen(cameraRollIndexApiProvider, (previous, next) {
      if (next != null && !identical(previous, next)) {
        Future.microtask(() {
          if (mounted) ref.read(cameraRollIndexProvider.notifier).refresh();
        });
      }
    });
    final local = ref.watch(filmRollsProvider),
        hidden = ref.watch(hiddenCameraRollIdsProvider);
    final index = ref.watch(cameraRollIndexProvider);
    final catalog = ref.watch(cameraFilmCatalogProvider).valueOrNull;
    final connected =
        ref.watch(connectionControllerProvider) is ConnectionReady;
    final camera = _source == 2 || !connected || hidden.isLoading
        ? <CameraIndexedRoll>[]
        : index.rolls
            .where(
                (roll) => !(hidden.valueOrNull ?? <String>{}).contains(roll.id))
            .toList();
    final phone =
        _source == 1 ? <FilmRoll>[] : local.valueOrNull ?? <FilmRoll>[];
    final reading = index.loading || index.scanning;
    void refresh() {
      ref.invalidate(filmRollsProvider);
      if (connected) {
        if (ref.read(cameraRollIndexApiProvider) == null) {
          ref.invalidate(companionHotspotPairingProvider);
        } else {
          ref.read(cameraRollIndexProvider.notifier).refresh();
        }
      }
    }

    return Material(
        color: context.palette.background,
        child: ListView(
            key: const PageStorageKey('film-rolls'),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(children: [
                    AlbumFilter(
                        choices: const ['全部', '相机', '手机'],
                        selected: _source,
                        onChanged: (i) => setState(() => _source = i)),
                    const Spacer(),
                    if (reading)
                      IconButton(
                          tooltip: '停止读取胶卷',
                          onPressed: () => ref
                              .read(cameraRollIndexProvider.notifier)
                              .cancel(),
                          icon: const Icon(Icons.close, size: 20))
                    else
                      PopupMenuButton<String>(
                          tooltip: '胶卷操作',
                          icon: const Icon(Icons.more_horiz),
                          onSelected: (value) {
                            if (value == 'new') {
                              _new();
                            } else {
                              refresh();
                            }
                          },
                          itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'refresh', child: Text('重新读取')),
                                PopupMenuItem(
                                    value: 'new', child: Text('新建手机胶卷'))
                              ]),
                  ])),
              if (reading)
                LinearProgressIndicator(
                    minHeight: 2, color: context.palette.accent),
              if (connected &&
                  index.error != null &&
                  ref.watch(cameraRollIndexApiProvider) != null)
                AlbumNotice(index.error!, error: true),
              if (local.hasError || hidden.hasError)
                const AlbumNotice('胶卷读取失败，请重试', error: true),
              for (final roll in camera)
                Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: AlbumRollCard(
                        key: roll.isLatest
                            ? const ValueKey('latest-camera-roll')
                            : ValueKey('camera-roll-${roll.id}'),
                        title: cameraRollName(roll, catalog: catalog),
                        subtitle:
                            '${roll.journalCount ?? roll.verifiedPhotoCount} / ${roll.target} 张 · ${cameraRollStatus(roll)}',
                        label: '相机',
                        identityIcon: CameraRollFilmIcon(
                            roll: roll, catalog: catalog, size: 44),
                        cover: roll.photos.isEmpty
                            ? null
                            : Stack(fit: StackFit.expand, children: [
                                CameraAlbumThumbnail(roll.photos.first.file),
                                if (roll.photos.first.file.extension == 'DNG')
                                  const Positioned(
                                      top: 8, left: 8, child: AlbumTag('RAW'))
                              ]),
                        onTap: () => _openCamera(roll))),
              for (final roll in phone)
                Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: AlbumRollCard(
                        title: roll.name,
                        subtitle:
                            '${roll.confirmedCount} / ${roll.targetCount} 张 · ${roll.statusLabel}',
                        label: '手机',
                        cover: roll.confirmedCount > 0
                            ? _RollCover(roll.id)
                            : null,
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    RollDetailPage(rollId: roll.id))))),
              if (camera.isEmpty &&
                  phone.isEmpty &&
                  !reading &&
                  !hidden.isLoading)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 44),
                    child: AlbumEmpty(
                        icon: Icons.local_movies_outlined,
                        title: _source == 1 && !connected
                            ? '连接相机后查看胶卷'
                            : connected &&
                                    ref.watch(cameraRollIndexApiProvider) ==
                                        null &&
                                    _source != 2
                                ? '正在连接相机服务'
                                : '还没有胶卷',
                        message: '',
                        action:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          TextButton(
                              onPressed: refresh, child: const Text('重新读取')),
                          TextButton(
                              onPressed: () =>
                                  context.go('/library?source=camera'),
                              child: const Text('从相机添加照片'))
                        ]))),
              if (connected && index.hasMore && _source != 2 && !reading)
                TextButton(
                    onPressed: () =>
                        ref.read(cameraRollIndexProvider.notifier).loadMore(),
                    child: const Text('读取更多胶卷')),
            ]));
  }
}

FilmDefinition? cameraRollFilm(
        CameraIndexedRoll roll, CameraFilmCatalog? catalog) =>
    catalog?.entries.where((entry) => entry.id == roll.filmId).firstOrNull;
String cameraRollName(CameraIndexedRoll roll, {CameraFilmCatalog? catalog}) =>
    cameraRollFilm(roll, catalog)?.name ??
    (roll.filmId == null
        ? '机身胶卷 ${roll.id.substring(0, 8)}'
        : '胶卷 ${roll.filmId}');

class CameraRollFilmIcon extends StatelessWidget {
  const CameraRollFilmIcon(
      {super.key, required this.roll, required this.catalog, this.size = 44});
  final CameraIndexedRoll roll;
  final CameraFilmCatalog? catalog;
  final double size;
  @override
  Widget build(BuildContext context) {
    final film = cameraRollFilm(roll, catalog);
    if (film == null) {
      return Icon(Icons.local_movies_outlined,
          size: size, color: context.palette.muted);
    }
    return Image.asset(film.icon,
        key: ValueKey('camera-roll-film-icon-${film.id}'),
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(Icons.local_movies_outlined,
            size: size, color: context.palette.muted));
  }
}

String cameraRollStatus(CameraIndexedRoll roll) => switch (roll.status) {
      CameraRollStatus.active => '拍摄中',
      CameraRollStatus.paused => '已暂停',
      CameraRollStatus.closed => '已收卷',
      null => '已拍记录 · 状态未记录'
    };

class AlbumRollCard extends StatelessWidget {
  const AlbumRollCard(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.label,
      required this.onTap,
      this.cover,
      this.identityIcon});
  final String title, subtitle, label;
  final VoidCallback onTap;
  final Widget? cover, identityIcon;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (cover != null)
          ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: AspectRatio(aspectRatio: 1.85, child: cover)),
        Padding(
            padding: EdgeInsets.fromLTRB(
                cover == null ? 0 : 2, cover == null ? 6 : 14, 0, 12),
            child: Row(children: [
              if (identityIcon != null) ...[
                SizedBox(width: 42, height: 54, child: identityIcon),
                const SizedBox(width: 14)
              ],
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 7),
                    Text(subtitle,
                        style: TextStyle(
                            color: context.palette.muted, fontSize: 11))
                  ])),
              const SizedBox(width: 10),
              AlbumTag(label),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 19, color: context.palette.muted),
            ])),
        if (cover == null) Divider(height: 1, color: context.palette.divider),
      ]));
}

Future<FilmRoll?> showCreateRollSheet(
        BuildContext context, FilmRepository repository, FilmRecipe recipe) =>
    showModalBottomSheet<FilmRoll>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        sheetAnimationStyle: workbenchSheetAnimation(context),
        builder: (_) =>
            _CreateRollSheet(repository: repository, recipe: recipe));

class _CreateRollSheet extends StatefulWidget {
  const _CreateRollSheet({required this.repository, required this.recipe});
  final FilmRepository repository;
  final FilmRecipe recipe;
  @override
  State<_CreateRollSheet> createState() => _CreateRollSheetState();
}

class _CreateRollSheetState extends State<_CreateRollSheet> {
  final _name = TextEditingController(),
      _count = TextEditingController(text: '36');
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final roll = await widget.repository.createRoll(
          name: _name.text,
          targetCount: int.tryParse(_count.text) ?? 0,
          recipe: widget.recipe);
      if (mounted) Navigator.pop(context, roll);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              24, 6, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('给这一天起个名字',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text('本卷配方 · ${widget.recipe.name}'),
                const SizedBox(height: 24),
                TextField(
                    controller: _name,
                    maxLength: 24,
                    decoration: const InputDecoration(
                        labelText: '胶卷名称',
                        hintText: '例如：沿河散步',
                        border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(
                    controller: _count,
                    keyboardType: TextInputType.number,
                    maxLength: 3,
                    decoration: const InputDecoration(
                        labelText: '计划张数（1–999）',
                        border: OutlineInputBorder())),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 20),
                FilledButton(
                    onPressed: _busy ? null : _create,
                    child: Text(_busy ? '正在开卷…' : '开始这一卷')),
              ])));
}

class _RollCover extends ConsumerWidget {
  const _RollCover(this.rollId);
  final String rollId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(rollItemsProvider(rollId)).valueOrNull;
    if (items == null || items.isEmpty) {
      return Center(
          child: Icon(Icons.photo_outlined, color: context.palette.muted));
    }
    final image = ref.watch(rollThumbnailProvider(items.first)).valueOrNull;
    return image == null
        ? Center(
            child:
                Icon(Icons.hide_image_outlined, color: context.palette.muted))
        : Image.memory(image, fit: BoxFit.cover, cacheWidth: 640);
  }
}
