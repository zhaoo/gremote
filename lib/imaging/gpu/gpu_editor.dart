import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../../darkroom/model/photo_edits.dart';
import '../imaging_engine.dart';
import 'gpu_render_descriptor.dart';

typedef _CloseNative = Int32 Function(Int32);
void closeOwnedFd(int fd) {
  DynamicLibrary.process()
      .lookupFunction<_CloseNative, int Function(int)>('close')(fd);
}

class GpuFrame {
  const GpuFrame(
      {required this.textureId,
      required this.generation,
      required this.width,
      required this.height,
      required this.descriptor,
      this.original = false});
  final int textureId, generation, width, height;
  final GpuRenderDescriptor descriptor;
  final bool original;
}

/// One application channel; only parameters and small analysis/thumbnail data
/// cross it. Full-resolution pixels remain owned by native EGL.
class GpuEditor {
  GpuEditor({MethodChannel? channel, void Function(int)? closeFd})
      : channel = channel ?? const MethodChannel('gremote/gpu_editor'),
        _closeFd = closeFd ?? closeOwnedFd {
    this.channel.setMethodCallHandler(_event);
  }
  final MethodChannel channel;
  final void Function(int) _closeFd;
  final _sessions = <int, GpuEditorSession>{};
  static int _jobId = DateTime.now().microsecondsSinceEpoch;
  bool _closed = false;
  Future<GpuEditorSession> open(
      {required int fd,
      required int mediaId,
      required int orientation,
      required int processVersion}) async {
    try {
      if (_closed) throw StateError('GPU service closed');
      final data = await channel.invokeMapMethod<String, dynamic>('open', {
        'fd': fd,
        'orientation': orientation,
        'processVersion': processVersion,
        'maxEdge': 1600
      });
      if (data == null) throw StateError('GPU source unavailable');
      final session = GpuEditorSession._(this, mediaId, processVersion, data);
      if (_closed) {
        await channel.invokeMethod<void>('close', {'sessionId': session.id});
        throw StateError('GPU service closed');
      }
      _sessions[session.id] = session;
      return session;
    } finally {
      _closeFd(fd);
    }
  }

  Future<void> _event(MethodCall call) async {
    final data = Map<Object?, Object?>.from(call.arguments as Map);
    final session = _sessions[data['sessionId']];
    if (session == null || session.closed) return;
    if (call.method == 'invalidated') {
      session._invalidated();
      return;
    }
    if (data['generation'] != session._generation) return;
    if (call.method == 'frame') {
      final descriptor = session._descriptor;
      if (descriptor == null) return;
      final frame = GpuFrame(
          textureId: session.textureId,
          generation: session._generation,
          width: data['width'] as int,
          height: data['height'] as int,
          descriptor: descriptor,
          original: data['original'] == true);
      session._frames.add(frame);
      session._waiting?.complete(frame);
      session._waiting = null;
    } else if (call.method == 'error') {
      final error = PlatformException(
          code: data['code'] as String? ?? 'gpuPreviewFailed',
          message: data['message'] as String?,
          details: data['detail']);
      session._frames.addError(error);
      session._waiting?.completeError(error);
      session._waiting = null;
    }
  }

  GpuEditorSession? sessionFor(int? mediaId, int version) {
    for (final session in _sessions.values) {
      if (!session.closed &&
          session.mediaId == mediaId &&
          session.processVersion == version) return session;
    }
    return null;
  }

  Future<void> export(ExportJob job, {ImagingCancelToken? cancel}) async {
    final id = ++_jobId;
    bool done = false;
    try {
      if (cancel?.isCancelled ?? false) {
        throw PlatformException(code: 'cancelled');
      }
      final parameters = job.adjustments ?? const PhotoEdits().nativeParameters;
      final session = sessionFor(job.mediaId, parameters[0].toInt());
      final pending = channel.invokeMethod<void>('export', {
        'jobId': id,
        'sessionId': session?.id ?? 0,
        'fd': job.fd,
        'orientation': job.orientation,
        'viewport': job.viewport,
        'parameters': parameters,
        'cube': job.cube,
        'strength': job.lutStrength,
        'geometry': Int32List.fromList([
          job.photoWidth,
          job.photoHeight,
          job.photoX,
          job.photoY,
          job.canvasWidth,
          job.canvasHeight,
          job.quality,
          job.background
        ]),
        'rectangles': Int32List.fromList([
          for (final overlay in job.overlays) ...[
            overlay.x,
            overlay.y,
            overlay.width,
            overlay.height
          ]
        ]),
        'images': [for (final overlay in job.overlays) overlay.rgba],
        'path': job.outputPath,
      });
      if (cancel != null) {
        unawaited(cancel.whenCancelled.then((_) async {
          if (!done) {
            await channel.invokeMethod<void>('cancelExport', {'jobId': id});
          }
        }).catchError((Object _) {}));
      }
      await pending;
    } finally {
      done = true;
      _closeFd(job.fd);
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final session in _sessions.values.toList()) {
      unawaited(session.close());
    }
    channel.setMethodCallHandler(null);
  }
}

class GpuEditorSession {
  GpuEditorSession._(
      this.owner, this.mediaId, this.processVersion, Map<String, dynamic> data)
      : id = data['sessionId'] as int,
        textureId = data['textureId'] as int,
        sourceWidth = data['sourceWidth'] as int,
        sourceHeight = data['sourceHeight'] as int,
        capabilities = data['capabilities'] as String;
  final GpuEditor owner;
  final int id, mediaId, processVersion, textureId, sourceWidth, sourceHeight;
  final String capabilities;
  bool closed = false;
  int _generation = 0;
  final _frames = StreamController<GpuFrame>.broadcast(sync: true);
  Stream<GpuFrame> get frames => _frames.stream;
  Completer<GpuFrame?>? _waiting;
  GpuRenderDescriptor? _descriptor;
  Future<void> _call(String method, [Map<String, Object?> args = const {}]) =>
      owner.channel.invokeMethod<void>(method, {'sessionId': id, ...args});
  void invalidate() {
    if (closed) return;
    _generation++;
    _waiting?.complete(null);
    _waiting = null;
    unawaited(_call('invalidate', {'generation': _generation})
        .catchError((Object _) {}));
  }

  Future<GpuFrame?> update(
      {required PhotoEdits edits,
      String lutKey = '',
      Uint8List? cube,
      required double strength,
      required int width,
      required int height}) async {
    invalidate();
    final reserved = _generation;
    if (closed) return null;
    if (cube != null && lutKey.isNotEmpty) {
      await _call('prepareLut', {'key': lutKey, 'bytes': cube});
    }
    if (closed || reserved != _generation) return null;
    _descriptor = GpuRenderDescriptor(
        edits: edits,
        width: width,
        height: height,
        lutKey: lutKey,
        strength: strength);
    final generation = ++_generation;
    final completion = _waiting = Completer<GpuFrame?>();
    unawaited(completion.future
        .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    try {
      final accepted = await owner.channel.invokeMethod<bool>('update', {
        'sessionId': id,
        'generation': generation,
        'parameters': edits.nativeParameters,
        'lutKey': lutKey,
        'strength': strength,
        'width': width,
        'height': height
      });
      if (accepted != true && _waiting == completion) {
        completion.complete(null);
        _waiting = null;
      }
      return await completion.future.timeout(const Duration(seconds: 20));
    } catch (e) {
      if (_waiting == completion) {
        _waiting = null;
        if (!completion.isCompleted) completion.complete(null);
      }
      rethrow;
    }
  }

  Future<void> compare(bool original) =>
      closed ? Future.value() : _call('compare', {'original': original});
  Future<List<List<double>>?> histogram() async {
    if (closed) return null;
    final generation = _generation;
    final bins = await owner.channel.invokeListMethod<dynamic>(
        'histogram', {'sessionId': id, 'generation': generation});
    if (closed || generation != _generation || bins == null) return null;
    return List.generate(4,
        (c) => List.generate(64, (i) => (bins[c * 64 + i] as num).toDouble()));
  }

  Future<PreviewImage?> thumbnail(
      PhotoEdits edits, Uint8List? cube, double strength) async {
    if (closed) return null;
    final (cw, ch) = edits.crop.outputSize(sourceWidth, sourceHeight);
    final scale = 200 / (cw > ch ? cw : ch);
    final w = (cw * scale).round().clamp(1, cw),
        h = (ch * scale).round().clamp(1, ch);
    final bytes = await owner.channel.invokeMethod<Uint8List>('thumbnail', {
      'sessionId': id,
      'parameters': edits.nativeParameters,
      'cube': cube,
      'strength': strength,
      'width': w,
      'height': h
    });
    return closed || bytes == null
        ? null
        : PreviewImage(width: w, height: h, rgba: bytes);
  }

  void _invalidated() {
    if (closed) return;
    closed = true;
    _waiting?.complete(null);
    _waiting = null;
    _frames.addError(StateError('GPU resources released'));
  }

  Future<void> close() async {
    if (!closed) {
      closed = true;
      _generation++;
      _waiting?.complete(null);
      _waiting = null;
      try {
        await _call('close');
      } on PlatformException catch (_) {/* engine already disposed */}
    }
    owner._sessions.remove(id);
    await _frames.close();
  }
}
