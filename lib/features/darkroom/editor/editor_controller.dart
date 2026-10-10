import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../../darkroom/darkroom_providers.dart';
import '../../../darkroom/export/export_service.dart';
import '../../../darkroom/frame/frame_layout.dart';
import '../../../darkroom/lut/lut_library.dart';
import '../../../darkroom/model/edit_document.dart';
import '../../../darkroom/model/export_recipe.dart';
import '../../../darkroom/model/photo_meta.dart';
import '../../../imaging/imaging_engine.dart';
import '../../../imaging/imaging_exception.dart';
import '../../../media/local/local_media_repository.dart';
import '../../../media/local/media_gateway.dart';

/// Long edge of the decoded on-screen preview.
const previewEdge = 1600;

@immutable
class EditorState {
  const EditorState({
    this.item,
    this.doc,
    this.base,
    this.graded,
    this.luts = const [],
    this.locationAccess = false,
    this.exporting = false,
    this.error,
  });

  final LocalMediaItem? item;
  final EditDocument? doc;

  /// Decoded photo without LUT, and with the current LUT applied.
  final PreviewImage? base;
  final PreviewImage? graded;
  final List<LutEntry> luts;
  final bool locationAccess;
  final bool exporting;
  final String? error;

  PhotoMeta? get meta => item?.meta;
  ExportRecipe get recipe => doc?.recipe ?? const ExportRecipe();

  /// Export-resolution geometry; the preview draws it scaled down.
  FrameLayout? get layout {
    final meta = this.meta;
    final doc = this.doc;
    if (meta == null || doc == null) return null;
    final (w, h) =
        scaledPhotoSize(meta.orientedWidth, meta.orientedHeight, recipe.size);
    return computeFrameLayout(
      photoWidth: w,
      photoHeight: h,
      style: recipe.frame,
      ratio: recipe.ratio,
      content: FrameContent.from(meta,
          title: doc.title, location: doc.location, hidden: doc.hidden),
    );
  }

  EditorState copyWith({
    LocalMediaItem? item,
    EditDocument? doc,
    PreviewImage? base,
    PreviewImage? graded,
    List<LutEntry>? luts,
    bool? locationAccess,
    bool? exporting,
    String? Function()? error,
  }) =>
      EditorState(
        item: item ?? this.item,
        doc: doc ?? this.doc,
        base: base ?? this.base,
        graded: graded ?? this.graded,
        luts: luts ?? this.luts,
        locationAccess: locationAccess ?? this.locationAccess,
        exporting: exporting ?? this.exporting,
        error: error == null ? this.error : error(),
      );
}

final editorProvider = NotifierProvider.autoDispose
    .family<EditorController, EditorState, int>(EditorController.new);

class EditorController extends AutoDisposeFamilyNotifier<EditorState, int> {
  final _cubes = <String, Uint8List>{};
  var _gradeTicket = 0;
  var _alive = true;
  Future<void> _saving = Future<void>.value();

  @override
  EditorState build(int arg) {
    ref.onDispose(() => _alive = false);
    Future.microtask(_load);
    return const EditorState();
  }

  /// Async work may finish after the page closed; drop its result then.
  void _emit(EditorState next) {
    if (_alive) state = next;
  }

  Future<void> _load() async {
    // Read dependencies up front: `ref` is unusable once the page closes.
    final gateway = ref.read(mediaGatewayProvider);
    final engine = ref.read(imagingEngineProvider);
    final store = ref.read(darkroomStoreProvider);
    final library = ref.read(lutLibraryProvider);
    final item = await ref.read(localMediaRepositoryProvider).find(arg);
    if (item == null || item.meta == null) {
      _emit(state.copyWith(error: () => '照片不存在，或无法读取它的 EXIF'));
      return;
    }
    final doc = await store.loadEdit(arg) ??
        EditDocument(mediaId: arg, updatedAt: DateTime.now());
    final luts = await library.entries();
    _emit(state.copyWith(
      item: item,
      doc: doc,
      luts: luts,
      locationAccess: await gateway.hasLocationAccess(),
    ));
    try {
      final fd = await gateway.openReadFd(arg);
      final base = await engine.decodePreview(
          fd: fd, orientation: item.meta!.orientation, maxEdge: previewEdge);
      _emit(state.copyWith(base: base, graded: base));
      await regrade();
    } on ImagingException catch (e) {
      _emit(state.copyWith(
          error: () => '预览解码失败（${e.code.name}）：${e.code.label}'));
    } on MediaException catch (e) {
      _emit(state.copyWith(error: () => '无法打开原图（${e.code}）'));
    }
  }

  /// Re-applies the current LUT; stale results from older calls are dropped.
  Future<void> regrade() async {
    final base = state.base;
    if (base == null) return;
    final ticket = ++_gradeTicket;
    final lutId = state.recipe.lutId;
    if (lutId == null) {
      _emit(state.copyWith(graded: base));
      return;
    }
    final library = ref.read(lutLibraryProvider);
    final engine = ref.read(imagingEngineProvider);
    final strength = state.recipe.strength;
    try {
      final cube = _cubes[lutId] ??= await library.load(lutId);
      final graded = await engine.applyLut(base, cube, strength);
      if (ticket == _gradeTicket) _emit(state.copyWith(graded: graded));
    } on Object catch (e) {
      if (ticket == _gradeTicket) {
        _emit(state.copyWith(error: () => 'LUT 应用失败：$e'));
      }
    }
  }

  Future<void> setLut(String? lutId) async {
    _updateRecipe(state.recipe.copyWith(lutId: () => lutId, strength: 1));
    await regrade();
  }

  /// Updates the value while dragging; call [regrade] when the drag ends.
  void setStrength(double strength) =>
      _updateRecipe(state.recipe.copyWith(strength: strength));

  void setFrame(FrameStyle frame) =>
      _updateRecipe(state.recipe.copyWith(frame: frame));

  void setRatio(FrameRatio ratio) =>
      _updateRecipe(state.recipe.copyWith(ratio: ratio));

  void setSize(ExportSize size) =>
      _updateRecipe(state.recipe.copyWith(size: size));

  void setQuality(int quality) =>
      _updateRecipe(state.recipe.copyWith(quality: quality));

  void setKeepGps(bool keep) =>
      _updateRecipe(state.recipe.copyWith(keepGps: keep));

  void setTitle(String title) => _updateDoc((d) => d.copyWith(title: title));

  void setLocation(String location) =>
      _updateDoc((d) => d.copyWith(location: location));

  void toggleField(FrameField field) => _updateDoc((d) {
        final hidden = {...d.hidden};
        if (!hidden.remove(field)) hidden.add(field);
        return d.copyWith(hidden: hidden);
      });

  Future<void> requestLocationAccess() async {
    final granted =
        await ref.read(mediaGatewayProvider).requestLocationAccess();
    _emit(state.copyWith(locationAccess: granted));
  }

  Future<void> savePreset(String name) async {
    final revision = ref.read(darkroomRevisionProvider.notifier);
    await ref.read(darkroomStoreProvider).savePreset(name, state.recipe);
    revision.state++;
  }

  /// Throws [ExportFailure] or [ExportCancelled].
  Future<ExportOutcome> export() async {
    final item = state.item;
    final doc = state.doc;
    if (item == null || doc == null || state.exporting) {
      throw StateError('editor is not ready to export');
    }
    final service = ref.read(exportServiceProvider);
    state = state.copyWith(exporting: true);
    try {
      await _saving;
      return await service.export(item, doc);
    } finally {
      _emit(state.copyWith(exporting: false));
    }
  }

  Future<void> share(String uri) => ref.read(mediaGatewayProvider).share(uri);

  void _updateRecipe(ExportRecipe recipe) =>
      _updateDoc((d) => d.copyWith(recipe: recipe));

  void _updateDoc(EditDocument Function(EditDocument) change) {
    final doc = state.doc;
    if (doc == null) return;
    final next = change(doc).copyWith(updatedAt: DateTime.now());
    state = state.copyWith(doc: next);
    final store = ref.read(darkroomStoreProvider);
    final revision = ref.read(darkroomRevisionProvider.notifier);
    // Serialised so a slow write never overwrites a newer one.
    _saving = _saving.then<void>((_) async {
      await store.saveEdit(next);
      revision.state++;
    }).catchError((Object e) {
      _emit(state.copyWith(error: () => '编辑保存失败：$e'));
    });
  }
}
