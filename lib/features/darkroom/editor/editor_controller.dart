import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' show Rect;
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import '../../../imaging/gpu/gpu_detail.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../../darkroom/darkroom_providers.dart';
import '../../../darkroom/export/export_service.dart';
import '../../../darkroom/frame/frame_layout.dart';
import '../../../darkroom/lut/lut_library.dart';
import '../../../darkroom/model/edit_document.dart';
import '../../../darkroom/model/export_recipe.dart';
import '../../../darkroom/model/photo_meta.dart';
import '../../../darkroom/model/photo_edits.dart';
import '../../../imaging/imaging_engine.dart';
import '../../../imaging/gpu/gpu_editor.dart';
import '../../../media/local/local_media_repository.dart';

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
    this.saveError,
    this.rendering = false,
    this.saving = false,
    this.canUndo = false,
    this.canRedo = false,
    this.cropEditing = false,
    this.renderedEdits,
    this.gpuFrame,
    this.gpuSession,
    this.histogram,
    this.detail,
  });

  final LocalMediaItem? item;
  final EditDocument? doc;

  /// Decoded photo without LUT, and with the current LUT applied.
  final PreviewImage? base;
  final PreviewImage? graded;
  final List<LutEntry> luts;
  final bool locationAccess;
  final bool exporting;
  final String? error, saveError;
  final bool rendering, saving, canUndo, canRedo, cropEditing;
  final PhotoEdits? renderedEdits;
  final GpuFrame? gpuFrame;
  final GpuEditorSession? gpuSession;
  final List<List<double>>? histogram;
  final GpuDetail? detail;

  PhotoMeta? get meta => item?.meta;
  ExportRecipe get recipe => doc?.recipe ?? const ExportRecipe();

  /// Export-resolution geometry; the preview draws it scaled down.
  FrameLayout? get layout {
    final meta = this.meta;
    final doc = this.doc;
    if (meta == null || doc == null) return null;
    final (cw, ch) = (renderedEdits ?? recipe.edits)
        .crop
        .outputSize(meta.orientedWidth, meta.orientedHeight);
    final (w, h) = scaledPhotoSize(cw, ch, recipe.size);
    return computeFrameLayout(
      photoWidth: w,
      photoHeight: h,
      style: cropEditing ? FrameStyle.none : recipe.frame,
      ratio: cropEditing ? FrameRatio.original : recipe.ratio,
      borderWidth: recipe.frameWidth,
      dateStamp: !cropEditing && recipe.dateStamp,
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
    String? Function()? saveError,
    bool? rendering,
    bool? saving,
    bool? canUndo,
    bool? canRedo,
    bool? cropEditing,
    PhotoEdits? renderedEdits,
    GpuFrame? Function()? gpuFrame,
    GpuEditorSession? Function()? gpuSession,
    List<List<double>>? histogram,
    GpuDetail? Function()? detail,
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
        saveError: saveError == null ? this.saveError : saveError(),
        rendering: rendering ?? this.rendering,
        saving: saving ?? this.saving,
        canUndo: canUndo ?? this.canUndo,
        canRedo: canRedo ?? this.canRedo,
        cropEditing: cropEditing ?? this.cropEditing,
        renderedEdits: renderedEdits ?? this.renderedEdits,
        gpuFrame: gpuFrame == null ? this.gpuFrame : gpuFrame(),
        gpuSession: gpuSession == null ? this.gpuSession : gpuSession(),
        histogram: histogram ?? this.histogram,
        detail: detail == null ? this.detail : detail(),
      );
}

final editorProvider = NotifierProvider.autoDispose
    .family<EditorController, EditorState, int>(EditorController.new);

class EditorController extends AutoDisposeFamilyNotifier<EditorState, int> {
  final _cubes = <String, Uint8List>{};
  final _undo = <EditDocument>[];
  final _redo = <EditDocument>[];
  EditDocument? _toolStart, _gestureStart;
  List<EditDocument>? _toolUndo, _toolRedo;
  GpuEditorSession? _gpu;
  StreamSubscription<GpuFrame>? _gpuFrames;
  int _gpuOpen = 0;
  int _detailEpoch = 0;
  ImagingCancelToken? _detailCancel;
  String? _detailPath;
  bool _comparing = false;
  DateTime _histogramAt = DateTime.fromMillisecondsSinceEpoch(0);
  var _gradeTicket = 0;
  var _previewEpoch = 0;
  var _toolEpoch = 0;
  var _lutEpoch = 0;
  var _alive = true;
  var _dirtyPreview = false;
  var _saveTicket = 0;
  Future<void>? _renderFuture;
  Future<void> _saving = Future<void>.value();

  @override
  EditorState build(int arg) {
    ref.onDispose(() {
      _alive = false;
      _clearDetail();
      ++_gpuOpen;
      unawaited(_gpuFrames?.cancel());
      unawaited(_gpu?.close());
    });
    Future.microtask(_load);
    return const EditorState();
  }

  void _emit(EditorState next) {
    if (_alive) state = next;
  }

  bool _same(EditDocument a, EditDocument b) =>
      a.recipe == b.recipe &&
      a.title == b.title &&
      a.location == b.location &&
      a.hidden.length == b.hidden.length &&
      a.hidden.containsAll(b.hidden);
  void _historyState() => _emit(
      state.copyWith(canUndo: _undo.isNotEmpty, canRedo: _redo.isNotEmpty));
  void _push(EditDocument doc) {
    _undo.add(doc);
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  Future<void> _load() async {
    final gateway = ref.read(mediaGatewayProvider);
    final engine = ref.read(imagingEngineProvider);
    final store = ref.read(darkroomStoreProvider);
    final library = ref.read(lutLibraryProvider);
    try {
      final item = await ref.read(localMediaRepositoryProvider).find(arg);
      if (!_alive) return;
      if (item == null || item.meta == null) {
        _emit(state.copyWith(error: () => '照片不存在，或无法读取它的 EXIF'));
        return;
      }
      final doc = await store.loadEdit(arg) ??
          EditDocument(
              mediaId: arg,
              updatedAt: DateTime.now(),
              recipe: const ExportRecipe(frame: FrameStyle.none));
      final luts = await library.entries();
      final access = await gateway.hasLocationAccess();
      if (!_alive) return;
      _emit(state.copyWith(
          item: item, doc: doc, luts: luts, locationAccess: access));
      if (ref.read(gpuEditorProvider) != null) {
        await _openGpu();
        return;
      }
      final fd = await gateway.openReadFd(arg);
      final base = await engine.decodePreview(
          fd: fd, orientation: item.meta!.orientation, maxEdge: previewEdge);
      if (!_alive) return;
      _emit(state.copyWith(
          base: base, graded: base, renderedEdits: const PhotoEdits()));
      await regrade();
    } on Object catch (e) {
      _emit(state.copyWith(error: () => '无法读取照片：$e'));
    }
  }

  void _clearDetail() {
    ++_detailEpoch;
    _detailCancel?.cancel();
    _detailCancel = null;
    final path = _detailPath;
    _detailPath = null;
    if (path != null) {
      unawaited(File(path).delete().catchError((Object _) => File(path)));
    }
    if (_alive && state.detail != null) {
      _emit(state.copyWith(detail: () => null));
    }
  }

  Future<void> detailAt(Rect region) async {
    final session = _gpu,
        meta = state.meta,
        service = ref.read(gpuEditorProvider);
    if (!_alive ||
        session == null ||
        session.closed ||
        service == null ||
        meta == null ||
        state.exporting ||
        _toolStart != null) return;
    region = region.intersect(const Rect.fromLTWH(0, 0, 1, 1));
    if (region.isEmpty) return;
    _clearDetail();
    final epoch = _detailEpoch, recipe = state.recipe;
    final token = _detailCancel = ImagingCancelToken();
    String? path;
    try {
      final (cw, ch) =
          recipe.edits.crop.outputSize(meta.orientedWidth, meta.orientedHeight);
      final scale = math.min(
          1.0,
          math.sqrt(
              4 * 1024 * 1024 / (cw * ch * region.width * region.height)));
      final w = (cw * scale).round().clamp(1, cw),
          h = (ch * scale).round().clamp(1, ch);
      final left = (region.left * w).floor().clamp(0, w - 1),
          top = (region.top * h).floor().clamp(0, h - 1);
      final right = (region.right * w).ceil().clamp(left + 1, w),
          bottom = (region.bottom * h).ceil().clamp(top + 1, h);
      // Round back to exact pixel bounds, so the patch never shifts at its edge.
      final actual = Rect.fromLTRB(left / w, top / h, right / w, bottom / h);
      final key = recipe.lutId;
      final cube = key == null
          ? null
          : _cubes[key] ??= await ref.read(lutLibraryProvider).load(key);
      final temp = await getTemporaryDirectory();
      path =
          '${temp.path}/gr-detail-$arg-${DateTime.now().microsecondsSinceEpoch}.jpg';
      final fd = await ref.read(mediaGatewayProvider).openReadFd(arg);
      await service.export(
          ExportJob(
              fd: fd,
              mediaId: arg,
              orientation: meta.orientation,
              viewport: true,
              photoWidth: w,
              photoHeight: h,
              photoX: -left,
              photoY: -top,
              canvasWidth: right - left,
              canvasHeight: bottom - top,
              background: 0xff000000,
              quality: 100,
              outputPath: path,
              cube: cube,
              lutStrength: recipe.strength,
              adjustments: recipe.edits.nativeParameters),
          cancel: token);
      if (!_alive ||
          epoch != _detailEpoch ||
          session != _gpu ||
          token.isCancelled) {
        await File(path).delete();
        return;
      }
      _detailPath = path;
      _emit(state.copyWith(detail: () => GpuDetail(path!, actual)));
    } catch (e) {
      if (path != null && await File(path).exists()) await File(path).delete();
      if (_alive && epoch == _detailEpoch && !token.isCancelled) {
        _emit(state.copyWith(error: () => '高清预览失败：$e'));
      }
    } finally {
      if (_detailCancel == token) _detailCancel = null;
      token.dispose();
    }
  }

  Future<void> _openGpu() async {
    final service = ref.read(gpuEditorProvider), meta = state.meta;
    if (service == null || meta == null || !_alive) return;
    final open = ++_gpuOpen;
    _invalidatePreviews();
    await _gpuFrames?.cancel();
    await _gpu?.close();
    _gpu = null;
    _emit(state.copyWith(
        gpuFrame: () => null, gpuSession: () => null, rendering: true));
    final fd = await ref.read(mediaGatewayProvider).openReadFd(arg);
    final session = await service.open(
        fd: fd,
        mediaId: arg,
        orientation: meta.orientation,
        processVersion: state.recipe.edits.processVersion);
    if (!_alive || open != _gpuOpen) {
      await session.close();
      return;
    }
    _gpu = session;
    _gpuFrames = session.frames.listen((frame) {
      if (_alive &&
          _comparing == frame.original &&
          (frame.original || state.gpuFrame?.original == true)) {
        _emit(state.copyWith(gpuFrame: () => frame));
      }
    }, onError: (Object e) {
      if (_alive) {
        _emit(state.copyWith(error: () => '预览不可用，请重试：$e', rendering: false));
      }
    });
    _emit(state.copyWith(gpuSession: () => session, error: () => null));
    await regrade();
  }

  Future<void> recoverPreview() async {
    if (!_alive || ref.read(gpuEditorProvider) == null || state.exporting) {
      return;
    }
    try {
      await _openGpu();
    } catch (e) {
      _emit(state.copyWith(error: () => '无法恢复预览：$e', rendering: false));
    }
  }

  void compareOriginal(bool value) {
    _comparing = value;
    unawaited(_gpu?.compare(value).catchError((Object e) {
      _emit(state.copyWith(error: () => '无法显示原图：$e'));
    }));
  }

  Future<void> _drainGpuPreviews() async {
    final library = ref.read(lutLibraryProvider);
    _emit(state.copyWith(rendering: true));
    while (_alive && _dirtyPreview) {
      _dirtyPreview = false;
      final recipe = state.recipe, epoch = _previewEpoch, ticket = _gradeTicket;
      var edits = recipe.edits;
      if (state.cropEditing) {
        edits = edits.copyWith(
            crop: edits.crop.copyWith(left: 0, top: 0, width: 1, height: 1));
      }
      final session = _gpu;
      if (session == null || session.closed) break;
      if (session.processVersion != edits.processVersion) {
        unawaited(recoverPreview());
        break;
      }
      try {
        final key = recipe.lutId;
        Uint8List? cube;
        if (key != null) cube = _cubes[key] ??= await library.load(key);
        if (!_alive || epoch != _previewEpoch) {
          _dirtyPreview = true;
          continue;
        }
        final (cw, ch) =
            edits.crop.outputSize(session.sourceWidth, session.sourceHeight);
        final edge = _gestureStart != null ? 960 : previewEdge;
        final scale = (edge / (cw > ch ? cw : ch)).clamp(0.0, 1.0);
        final frame = await session.update(
            edits: edits,
            lutKey: key ?? '',
            cube: cube,
            strength: recipe.strength,
            width: (cw * scale).round().clamp(1, cw),
            height: (ch * scale).round().clamp(1, ch));
        if (_alive &&
            frame != null &&
            epoch == _previewEpoch &&
            (ticket == _gradeTicket || _gestureStart != null)) {
          _emit(state.copyWith(
              gpuFrame: () => frame,
              renderedEdits: frame.descriptor.edits,
              error: () => null));
          if (DateTime.now().difference(_histogramAt).inMilliseconds > 150) {
            _histogramAt = DateTime.now();
            unawaited(session.histogram().then((bins) {
              if (_alive && session == _gpu && bins != null) {
                _emit(state.copyWith(histogram: bins));
              }
            }).catchError((Object _) {}));
          }
        }
      } catch (e) {
        if (_alive && epoch == _previewEpoch) {
          _emit(state.copyWith(error: () => '预览处理失败：$e'));
        }
      }
    }
    if (_alive) _emit(state.copyWith(rendering: false));
  }

  // Discrete changes revoke in-flight draft publication. Keep a newest job
  // queued even when the document did not change (for example selecting the
  // same LUT), so revoking a render can never leave the preview stranded.
  void _invalidatePreviews() {
    _clearDetail();
    ++_previewEpoch;
    _gpu?.invalidate();
    if (_renderFuture != null) _dirtyPreview = true;
  }

  /// At most one native job in flight; updates during it collapse to newest.
  Future<void> regrade() {
    if (!_alive || (state.base == null && _gpu == null)) {
      return Future<void>.value();
    }
    ++_gradeTicket;
    _dirtyPreview = true;
    return _renderFuture ??= Future<void>.microtask(
            _gpu == null ? _drainPreviews : _drainGpuPreviews)
        .whenComplete(() {
      _renderFuture = null;
      if (_alive && _dirtyPreview) unawaited(regrade());
    });
  }

  Future<void> _drainPreviews() async {
    final library = ref.read(lutLibraryProvider);
    final engine = ref.read(imagingEngineProvider);
    _emit(state.copyWith(rendering: true));
    while (_alive && _dirtyPreview) {
      _dirtyPreview = false;
      final ticket = _gradeTicket, recipe = state.recipe, base = state.base!;
      final epoch = _previewEpoch;
      final progressive = _toolStart != null || _gestureStart != null;
      var edits = recipe.edits;
      if (state.cropEditing) {
        edits = edits.copyWith(
            crop: edits.crop.copyWith(left: 0, top: 0, width: 1, height: 1));
      }
      try {
        final id = recipe.lutId;
        Uint8List? cube;
        if (id != null) cube = _cubes[id] ??= await library.load(id);
        final (w, h) = edits.crop.outputSize(base.width, base.height);
        final graded = edits == const PhotoEdits() && cube == null
            ? base
            : await engine.renderPhoto(base,
                adjustments: edits.nativeParameters,
                cube: cube,
                strength: recipe.strength,
                width: w,
                height: h);
        // A completed draft is useful feedback while the same tool keeps
        // changing. Waiting for a ticket with no newer input starves every
        // frame during a drag. Epochs still reject cancelled/replaced work.
        if (_alive &&
            epoch == _previewEpoch &&
            (ticket == _gradeTicket || progressive)) {
          _emit(state.copyWith(
              graded: graded, renderedEdits: edits, error: () => null));
        }
      } on Object catch (e) {
        if (_alive && epoch == _previewEpoch && ticket == _gradeTicket) {
          _emit(state.copyWith(error: () => '预览处理失败：$e'));
        }
      }
    }
    if (_alive) _emit(state.copyWith(rendering: false));
  }

  Future<void> flushPreview() async {
    while (_renderFuture != null) {
      await _renderFuture;
    }
  }

  Future<void> retrySave() async {
    final confirmed = _toolStart ?? state.doc;
    if (confirmed != null) _persist(confirmed);
    await _saving;
  }

  Future<void> flushEdits() async {
    await _saving;
  }

  void beginTool({bool crop = false}) {
    if (state.exporting || state.doc == null) return;
    if (_toolStart != null) commitTool();
    _invalidatePreviews();
    ++_toolEpoch;
    _toolStart = state.doc;
    _toolUndo = List.of(_undo);
    _toolRedo = List.of(_redo);
    _emit(state.copyWith(cropEditing: crop));
    if (crop) unawaited(regrade());
  }

  void commitTool() {
    if (_toolStart == null) return;
    endGesture();
    ++_toolEpoch;
    final crop = state.cropEditing;
    if (crop) _invalidatePreviews();
    _toolStart = null;
    _toolUndo = null;
    _toolRedo = null;
    _emit(state.copyWith(cropEditing: false));
    if (state.doc != null) _persist(state.doc!);
    if (crop) unawaited(regrade());
  }

  void cancelTool() {
    final start = _toolStart;
    if (start == null || state.exporting) return;
    _invalidatePreviews();
    ++_toolEpoch;
    _gestureStart = null;
    _undo
      ..clear()
      ..addAll(_toolUndo!);
    _redo
      ..clear()
      ..addAll(_toolRedo!);
    _toolStart = null;
    _toolUndo = null;
    _toolRedo = null;
    _emit(state.copyWith(doc: start, cropEditing: false));
    _historyState();
    unawaited(regrade());
  }

  void beginGesture() {
    if (!state.exporting) _gestureStart ??= state.doc;
  }

  void endGesture() {
    final start = _gestureStart;
    _gestureStart = null;
    if (start != null && _gpu != null) unawaited(regrade());
    if (start != null && state.doc != null && !_same(start, state.doc!)) {
      _push(start);
      _historyState();
      if (_toolStart == null) _persist(state.doc!);
    }
  }

  void undo() {
    if (state.exporting || _undo.isEmpty || state.doc == null) return;
    endGesture();
    _invalidatePreviews();
    _redo.add(state.doc!);
    _emit(state.copyWith(doc: _undo.removeLast()));
    _historyState();
    unawaited(regrade());
    if (_toolStart == null) _persist(state.doc!);
  }

  void redo() {
    if (state.exporting || _redo.isEmpty || state.doc == null) return;
    _invalidatePreviews();
    _undo.add(state.doc!);
    _emit(state.copyWith(doc: _redo.removeLast()));
    _historyState();
    unawaited(regrade());
    if (_toolStart == null) _persist(state.doc!);
  }

  void setEdits(PhotoEdits edits) =>
      _updateRecipe(state.recipe.copyWith(edits: edits));
  Future<void> setLut(String? id) async {
    _invalidatePreviews();
    ++_lutEpoch;
    _updateRecipe(state.recipe.copyWith(lutId: () => id));
    await flushPreview();
  }

  void setStrength(double strength) =>
      _updateRecipe(state.recipe.copyWith(strength: strength.clamp(0, 1)));
  void setFrame(FrameStyle frame) =>
      _updateRecipe(state.recipe.copyWith(frame: frame));
  void setFrameWidth(double width) =>
      _updateRecipe(state.recipe.copyWith(frameWidth: width.clamp(0, .2)));
  void setDateStamp(bool value) =>
      _updateRecipe(state.recipe.copyWith(dateStamp: value));
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
  void resetAll() {
    _invalidatePreviews();
    _updateDoc((d) => d.copyWith(
        recipe: const ExportRecipe(frame: FrameStyle.none),
        title: '',
        location: '',
        hidden: const {}));
  }

  void applyPreset(ExportRecipe recipe) {
    _invalidatePreviews();
    final meta = state.meta;
    if (meta != null) {
      recipe = recipe.copyWith(
          edits: recipe.edits.copyWith(
              crop: recipe.edits.crop
                  .adaptToSource(meta.orientedWidth, meta.orientedHeight)));
    }
    _updateRecipe(recipe);
  }

  Future<void> importLut(String name, Uint8List bytes) async {
    final library = ref.read(lutLibraryProvider);
    final selection = ++_lutEpoch, tool = _toolEpoch;
    final entry = await library.import(name, bytes);
    if (!_alive) return;
    final luts = await library.entries();
    if (!_alive) return;
    _emit(state.copyWith(luts: luts));
    if (selection == _lutEpoch && tool == _toolEpoch && !state.exporting) {
      await setLut(entry.id);
    }
  }

  Future<void> requestLocationAccess() async {
    final granted =
        await ref.read(mediaGatewayProvider).requestLocationAccess();
    _emit(state.copyWith(locationAccess: granted));
  }

  Future<void> savePreset(String name) async {
    final store = ref.read(darkroomStoreProvider);
    final revision = ref.read(darkroomRevisionProvider.notifier);
    await store.savePreset(name, state.recipe);
    revision.state++;
  }

  Future<ExportOutcome> export() async {
    if (state.item == null || state.doc == null || state.exporting) {
      throw StateError('editor is not ready to export');
    }
    commitTool();
    final service = ref.read(exportServiceProvider),
        item = state.item!,
        doc = state.doc!;
    _emit(state.copyWith(exporting: true));
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
    if (doc == null || state.exporting || !_alive) return;
    final next = change(doc).copyWith(updatedAt: DateTime.now());
    if (_same(doc, next)) return;
    if (_gestureStart == null) _push(doc);
    final pixelsChanged = doc.recipe.edits != next.recipe.edits ||
        doc.recipe.lutId != next.recipe.lutId ||
        doc.recipe.strength != next.recipe.strength;
    _emit(state.copyWith(doc: next));
    _historyState();
    if (_toolStart == null && _gestureStart == null) _persist(next);
    if (pixelsChanged) {
      _clearDetail();
      unawaited(regrade());
    }
  }

  void _persist(EditDocument doc) {
    final store = ref.read(darkroomStoreProvider);
    final revision = ref.read(darkroomRevisionProvider.notifier);
    final ticket = ++_saveTicket;
    _emit(state.copyWith(saving: true));
    _saving = _saving.then<void>((_) async {
      await store.saveEdit(doc);
      revision.state++;
      if (_alive && ticket == _saveTicket) {
        _emit(state.copyWith(saving: false, saveError: () => null));
      }
    }).catchError((Object e) {
      if (_alive && ticket == _saveTicket) {
        _emit(state.copyWith(saving: false, saveError: () => '编辑保存失败：$e'));
      }
    });
  }
}
