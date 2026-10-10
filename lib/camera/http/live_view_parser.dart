import 'dart:convert';
import 'dart:typed_data';

typedef LiveViewDiagnostic = void Function(String code);

enum _ParserState { seekingBoundary, readingHeaders, readingBody }

/// GR `multipart/x-mixed-replace` JPEG 流的增量解析器。
class LiveViewParser {
  LiveViewParser({LiveViewDiagnostic? onDiagnostic})
      : _onDiagnostic = onDiagnostic;

  static const maxFrameBytes = 4 * 1024 * 1024;
  static const maxBufferBytes = 5 * 1024 * 1024;
  static const _maxHeaderBytes = 8 * 1024;
  static final _marker = ascii.encode('--boundary');
  static final _rfcMarker = ascii.encode('----boundary');
  static final _lineEnd = ascii.encode('\r\n');
  static final _headerEnd = ascii.encode('\r\n\r\n');

  final LiveViewDiagnostic? _onDiagnostic;
  final _buffer = <int>[];
  var _state = _ParserState.seekingBoundary;
  int? _contentLength;
  var _searchFrom = 0;

  List<Uint8List> add(Uint8List chunk) {
    _buffer.addAll(chunk);
    final frames = <Uint8List>[];
    while (_step(frames)) {}
    if (_buffer.length > maxBufferBytes) {
      _diagnose('bufferOverflow');
      reset();
    }
    return frames;
  }

  List<Uint8List> finish() {
    if (_state != _ParserState.seekingBoundary) {
      _diagnose('truncatedFrame');
    }
    reset();
    return const [];
  }

  void reset() {
    _buffer.clear();
    _state = _ParserState.seekingBoundary;
    _contentLength = null;
    _searchFrom = 0;
  }

  bool _step(List<Uint8List> frames) => switch (_state) {
        _ParserState.seekingBoundary => _seekBoundary(),
        _ParserState.readingHeaders => _readHeaders(),
        _ParserState.readingBody => _readBody(frames),
      };

  bool _seekBoundary() {
    final markerIndex = _indexOf(_marker, _searchFrom);
    if (markerIndex < 0) {
      _discardKeepingTail();
      return false;
    }
    final lineStart = markerIndex + _marker.length;
    final lineEnd = _indexOf(_lineEnd, lineStart);
    if (lineEnd < 0) {
      _consume(markerIndex);
      return false;
    }
    final suffix =
        ascii.decode(_buffer.sublist(lineStart, lineEnd), allowInvalid: true);
    _consume(lineEnd + _lineEnd.length);
    if (suffix != '--') _state = _ParserState.readingHeaders;
    return true;
  }

  bool _readHeaders() {
    final end = _indexOf(_headerEnd, 0);
    if (end < 0) {
      if (_buffer.length > _maxHeaderBytes) _dropPart('malformedHeader');
      return _state == _ParserState.seekingBoundary;
    }

    final headers = latin1.decode(_buffer.sublist(0, end)).split('\r\n');
    _consume(end + _headerEnd.length);
    int? contentLength;
    for (final line in headers) {
      final separator = line.indexOf(':');
      if (separator <= 0) {
        _dropPart('malformedHeader');
        return true;
      }
      final name = line.substring(0, separator).trim().toLowerCase();
      if (name != 'content-length') continue;
      contentLength = int.tryParse(line.substring(separator + 1).trim());
      if (contentLength == null || contentLength < 0) {
        _dropPart('malformedHeader');
        return true;
      }
    }

    if (contentLength != null && contentLength > maxFrameBytes) {
      _dropPart('frameTooLarge');
      return true;
    }
    _contentLength = contentLength;
    _state = _ParserState.readingBody;
    return true;
  }

  bool _readBody(List<Uint8List> frames) {
    final length = _contentLength;
    if (length != null) {
      if (_buffer.length < length) return false;
      _emit(frames, _buffer.sublist(0, length));
      _consume(length);
      _finishPart();
      return true;
    }

    final markerIndex = _bodyBoundaryIndex(_searchFrom);
    if (markerIndex < 0) {
      _searchFrom =
          (_buffer.length - _rfcMarker.length - 1).clamp(0, _buffer.length);
      if (_buffer.length > maxFrameBytes) _dropPart('frameTooLarge');
      return false;
    }
    _emit(frames, _trimToJpegEnd(_buffer.sublist(0, markerIndex)));
    _consume(markerIndex);
    _finishPart();
    return true;
  }

  void _emit(List<Uint8List> frames, List<int> bytes) {
    final valid = bytes.length >= 4 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[bytes.length - 2] == 0xff &&
        bytes[bytes.length - 1] == 0xd9;
    if (valid) {
      frames.add(Uint8List.fromList(bytes));
    } else {
      _diagnose('invalidJpeg');
    }
  }

  List<int> _trimToJpegEnd(List<int> bytes) {
    for (var index = bytes.length - 2; index >= 0; index--) {
      if (bytes[index] == 0xff && bytes[index + 1] == 0xd9) {
        return bytes.sublist(0, index + 2);
      }
    }
    return bytes;
  }

  void _dropPart(String code) {
    _diagnose(code);
    _finishPart();
  }

  void _finishPart() {
    _state = _ParserState.seekingBoundary;
    _contentLength = null;
    _searchFrom = 0;
  }

  void _discardKeepingTail() {
    final keep = _marker.length - 1;
    if (_buffer.length > keep) _consume(_buffer.length - keep);
  }

  void _consume(int count) {
    _buffer.removeRange(0, count);
    _searchFrom = 0;
  }

  int _bodyBoundaryIndex(int start) {
    var earliest = -1;
    for (final marker in [_rfcMarker, _marker]) {
      var index = _indexOf(marker, start < 2 ? 2 : start);
      while (index >= 0) {
        final precededByLineEnd =
            _buffer[index - 2] == 13 && _buffer[index - 1] == 10;
        final precededByJpegEnd =
            _buffer[index - 2] == 0xff && _buffer[index - 1] == 0xd9;
        if (precededByLineEnd || precededByJpegEnd) {
          if (earliest < 0 || index < earliest) earliest = index;
          break;
        }
        index = _indexOf(marker, index + 1);
      }
    }
    return earliest;
  }

  int _indexOf(List<int> pattern, int start) {
    final last = _buffer.length - pattern.length;
    outer:
    for (var index = start; index <= last; index++) {
      for (var offset = 0; offset < pattern.length; offset++) {
        if (_buffer[index + offset] != pattern[offset]) continue outer;
      }
      return index;
    }
    return -1;
  }

  void _diagnose(String code) => _onDiagnostic?.call(code);
}
