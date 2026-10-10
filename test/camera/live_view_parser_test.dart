import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/http/live_view_parser.dart';

void main() {
  final firstFrame = Uint8List.fromList([0xff, 0xd8, 1, 2, 0xff, 0xd9]);
  final secondFrame = Uint8List.fromList([0xff, 0xd8, 3, 4, 5, 0xff, 0xd9]);

  test('parses frames when boundaries headers lengths and JPEGs are split', () {
    final parser = LiveViewParser();
    final payload = _multipart([
      _part(firstFrame, includeLength: true),
      _part(secondFrame, includeLength: false),
    ]);
    final frames = <Uint8List>[];
    const chunkSizes = [1, 2, 5, 3, 8, 1, 13];
    var offset = 0;
    var index = 0;

    while (offset < payload.length) {
      final end = (offset + chunkSizes[index % chunkSizes.length])
          .clamp(0, payload.length);
      frames.addAll(parser.add(Uint8List.sublistView(payload, offset, end)));
      offset = end;
      index++;
    }

    expect(frames, hasLength(2));
    expect(frames[0], orderedEquals(firstFrame));
    expect(frames[1], orderedEquals(secondFrame));
    expect(parser.finish(), isEmpty);
  });

  test('does not treat boundary-like JPEG bytes as a delimiter', () {
    final parser = LiveViewParser();
    final frame = Uint8List.fromList([
      0xff,
      0xd8,
      ...ascii.encode('--boundary'),
      0xff,
      0xd9,
    ]);
    final payload = _multipart([_part(frame, includeLength: false)]);

    expect(parser.add(payload).single, orderedEquals(frame));
  });

  test('accepts RFC delimiters derived from boundary=--boundary', () {
    final parser = LiveViewParser();
    final payload = Uint8List.fromList([
      ...ascii.encode('----boundary\r\nContent-Type: image/jpeg\r\n\r\n'),
      ...firstFrame,
      ...ascii.encode('\r\n----boundary--\r\n'),
    ]);

    expect(parser.add(payload).single, orderedEquals(firstFrame));
  });

  test('parses camera stream with boundary immediately after JPEG end', () {
    final parser = LiveViewParser();
    final payload = Uint8List.fromList([
      ...ascii.encode('--boundary\r\nContent-Type: image/jpeg\r\n\r\n'),
      ...firstFrame,
      ...ascii.encode('--boundary\r\nContent-Type: image/jpeg\r\n\r\n'),
      ...secondFrame,
      ...ascii.encode('--boundary--\r\n'),
    ]);
    final frames = <Uint8List>[];
    for (var offset = 0; offset < payload.length; offset += 5) {
      final end = (offset + 5).clamp(0, payload.length);
      frames.addAll(parser.add(Uint8List.sublistView(payload, offset, end)));
    }

    expect(frames, hasLength(2));
    expect(frames[0], orderedEquals(firstFrame));
    expect(frames[1], orderedEquals(secondFrame));
  });

  test('drops malformed headers and resumes at the next boundary', () {
    final diagnostics = <String>[];
    final parser = LiveViewParser(onDiagnostic: diagnostics.add);
    final malformed = <int>[
      ...ascii.encode('--boundary\r\nBroken header\r\n\r\nnoise\r\n'),
      ..._part(firstFrame, includeLength: true),
      ...ascii.encode('--boundary--\r\n'),
    ];

    final frames = parser.add(Uint8List.fromList(malformed));

    expect(frames.single, orderedEquals(firstFrame));
    expect(diagnostics, contains('malformedHeader'));
  });

  test('rejects an oversized frame and recovers', () {
    final diagnostics = <String>[];
    final parser = LiveViewParser(onDiagnostic: diagnostics.add);
    final payload = Uint8List.fromList([
      ...ascii.encode(
        '--boundary\r\nContent-Type: image/jpeg\r\n'
        'Content-Length: ${4 * 1024 * 1024 + 1}\r\n\r\nignored\r\n',
      ),
      ..._part(secondFrame, includeLength: true),
      ...ascii.encode('--boundary--\r\n'),
    ]);

    final frames = parser.add(payload);

    expect(frames.single, orderedEquals(secondFrame));
    expect(diagnostics, contains('frameTooLarge'));
  });

  test('reports a truncated frame on finish', () {
    final diagnostics = <String>[];
    final parser = LiveViewParser(onDiagnostic: diagnostics.add);

    parser.add(
      Uint8List.fromList(
        ascii.encode(
          '--boundary\r\nContent-Type: image/jpeg\r\nContent-Length: 99\r\n\r\n',
        ),
      ),
    );

    expect(parser.finish(), isEmpty);
    expect(diagnostics, contains('truncatedFrame'));
  });

  test('reset drops an old partial stream', () {
    final parser = LiveViewParser();
    parser.add(Uint8List.fromList(ascii.encode('--bound')));

    parser.reset();
    final frames = parser.add(
      Uint8List.fromList([
        ..._part(firstFrame, includeLength: true),
        ...ascii.encode('--boundary--\r\n'),
      ]),
    );

    expect(frames.single, orderedEquals(firstFrame));
  });
}

Uint8List _multipart(List<List<int>> parts) => Uint8List.fromList([
      ...parts.expand((part) => part),
      ...ascii.encode('--boundary--\r\n'),
    ]);

List<int> _part(Uint8List frame, {required bool includeLength}) => [
      ...ascii.encode('--boundary\r\nContent-Type: image/jpeg\r\n'),
      if (includeLength) ...ascii.encode('Content-Length: ${frame.length}\r\n'),
      ...ascii.encode('\r\n'),
      ...frame,
      ...ascii.encode('\r\n'),
    ];
