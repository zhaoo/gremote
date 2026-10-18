import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../camera/recipe/recipe_store.dart';
import '../../camera/recipe/tag_matcher.dart';
import '../../darkroom/darkroom_providers.dart';
import '../../darkroom/model/export_recipe.dart';
import '../../media/local/local_media_repository.dart';
import '../../media/local/media_gateway.dart';

@immutable
class LibraryState {
  const LibraryState({
    this.access,
    this.grOnly = true,
    this.items = const [],
    this.tags = const {},
    this.scan,
    this.selected = const {},
    this.error,
  });

  /// Null until the first permission check returns.
  final MediaAccess? access;
  final bool grOnly;
  final List<LocalMediaItem> items;
  final Map<int, TagMatch> tags;

  /// Non-null while EXIF is being read.
  final ScanProgress? scan;
  final Set<int> selected;
  final String? error;

  bool get selecting => selected.isNotEmpty;
  bool get selectedHasUnconfirmedWeak => selected.any((id) {
        final match = tags[id];
        return match?.strength == MatchStrength.weak && !match!.tag.confirmed;
      });

  LibraryState copyWith({
    MediaAccess? access,
    bool? grOnly,
    List<LocalMediaItem>? items,
    Map<int, TagMatch>? tags,
    ScanProgress? Function()? scan,
    Set<int>? selected,
    String? Function()? error,
  }) =>
      LibraryState(
        access: access ?? this.access,
        grOnly: grOnly ?? this.grOnly,
        items: items ?? this.items,
        tags: tags ?? this.tags,
        scan: scan == null ? this.scan : scan(),
        selected: selected ?? this.selected,
        error: error == null ? this.error : error(),
      );
}

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryState>(LibraryController.new);

class LibraryController extends Notifier<LibraryState> {
  bool _scanning = false;

  @override
  LibraryState build() => const LibraryState();

  MediaGateway get _gateway => ref.read(mediaGatewayProvider);
  LocalMediaRepository get _repository =>
      ref.read(localMediaRepositoryProvider);

  /// Re-checks permission (it may change in system settings) and rescans.
  Future<void> refresh() async {
    final access = await _gateway.access();
    state = state.copyWith(access: access);
    if (access != MediaAccess.denied) await _scan();
  }

  Future<void> requestAccess() async {
    final access = await _gateway.requestAccess();
    state = state.copyWith(access: access);
    if (access != MediaAccess.denied) await _scan();
  }

  Future<void> setGrOnly(bool grOnly) async {
    state = state.copyWith(grOnly: grOnly, selected: const {});
    await _reload();
  }

  void toggle(int id) {
    final selected = {...state.selected};
    if (!selected.remove(id)) selected.add(id);
    state = state.copyWith(selected: selected);
  }

  void clearSelection() => state = state.copyWith(selected: const {});

  List<LocalMediaItem> get selectedItems => [
        for (final item in state.items)
          if (state.selected.contains(item.id)) item
      ];

  Future<void> confirmSelectedTags() async {
    final store = ref.read(recipeStoreProvider);
    for (final id in state.selected) {
      final match = state.tags[id];
      if (match?.strength == MatchStrength.weak && !match!.tag.confirmed) {
        await store.confirmTag(match.tag.id);
      }
    }
    await _reload();
  }

  Future<RecipeExportJobs> recipeJobs() async {
    final recipes = {
      for (final recipe in await ref.read(recipeStoreProvider).recipes())
        recipe.id: recipe,
    };
    final presets = {
      for (final preset in await ref.read(darkroomStoreProvider).presets())
        preset.id: preset.recipe,
    };
    final jobs = <(LocalMediaItem, ExportRecipe)>[];
    var skipped = 0;
    for (final item in selectedItems) {
      final match = state.tags[item.id];
      final recipe = match == null ? null : recipes[match.tag.recipeId];
      final exportRecipe =
          recipe == null ? null : presets[recipe.exportPresetId];
      if (match?.usable != true || exportRecipe == null) {
        skipped++;
      } else {
        jobs.add((item, exportRecipe));
      }
    }
    return RecipeExportJobs(jobs: jobs, skipped: skipped);
  }

  Future<void> _scan() async {
    if (_scanning) return;
    _scanning = true;
    try {
      await _reload();
      await for (final progress in _repository.scan()) {
        state = state.copyWith(scan: () => progress, error: () => null);
        await _reload();
      }
    } on MediaException catch (e) {
      state =
          state.copyWith(error: () => '读取相册失败（${e.code}）：${e.message ?? ''}');
    } finally {
      _scanning = false;
      state = state.copyWith(scan: () => null);
    }
  }

  Future<void> _reload() async {
    final allItems = await _repository.list(grOnly: state.grOnly);
    final allTags = await ref.read(recipeStoreProvider).tagsForBaseNames(
          allItems.map((item) => baseNameOf(item.displayName)),
        );
    final tags = <int, TagMatch>{};
    for (final item in allItems) {
      final match = matchTag(item, allTags);
      if (match != null) tags[item.id] = match;
    }
    final items = allItems;
    final ids = {for (final item in items) item.id};
    state = state.copyWith(
      items: items,
      tags: tags,
      selected: state.selected.where(ids.contains).toSet(),
    );
  }
}

@immutable
class RecipeExportJobs {
  const RecipeExportJobs({required this.jobs, required this.skipped});

  final List<(LocalMediaItem, ExportRecipe)> jobs;
  final int skipped;
}
