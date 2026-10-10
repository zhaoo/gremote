import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/lut/builtin_looks.dart';
import 'package:gremote/darkroom/lut/cube_writer.dart';
import 'package:gremote/darkroom/lut/lut_library.dart';
import 'package:gremote/darkroom/store/darkroom_store.dart';
import 'package:gremote/imaging/imaging_exception.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_imaging_engine.dart';

Uint8List identity(int size) => Uint8List.fromList(
    writeCube(title: 'id', size: size, map: (r, g, b) => [r, g, b]).codeUnits);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late Directory dir;
  late FakeImagingEngine engine;
  late LutLibrary library;

  setUp(() async {
    db = await GRemoteDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    dir = await Directory.systemTemp.createTemp('gremote-luts');
    engine = FakeImagingEngine();
    library = LutLibrary(
      store: DarkroomStore(db),
      engine: engine,
      dataDir: () async => dir,
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('lists the five builtin looks first', () async {
    final entries = await library.entries();
    expect(entries.map((e) => e.id), [for (final l in builtinLooks) l.id]);
    expect(entries.every((e) => !e.imported && e.size == 33), isTrue);
  });

  test('loads builtin cube bytes from assets', () async {
    final bytes = await library.load('builtin:pale');
    expect(
        String.fromCharCodes(bytes.take(60)), contains('gremote original look'));
  });

  test('imports a valid cube once and can delete it', () async {
    engine.lutSize = 17;
    final first = await library.import('Kodak-ish.cube', identity(17));
    final again = await library.import('copy.cube', identity(17));
    expect(again.id, first.id);
    expect(first.name, 'Kodak-ish');
    expect(first.size, 17);
    final entries = await library.entries();
    expect(entries.last.id, first.id);
    expect(entries.last.imported, isTrue);
    expect(await library.load(first.id), identity(17));

    await library.delete(first.id);
    expect((await library.entries()).where((e) => e.imported), isEmpty);
    expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('rejects oversized files before validation', () async {
    final huge = Uint8List(16 * 1024 * 1024 + 1);
    await expectLater(
      library.import('huge.cube', huge),
      throwsA(isA<LutImportException>()
          .having((e) => e.reason, 'reason', contains('16 MiB'))),
    );
    expect(engine.validated, isEmpty);
  });

  test('explains unsupported sizes and row mismatches', () async {
    engine.validateError = ImagingErrorCode.lutParse;
    await expectLater(
      library.import(
          'a.cube', Uint8List.fromList('LUT_3D_SIZE 129\n'.codeUnits)),
      throwsA(isA<LutImportException>()
          .having((e) => e.reason, 'reason', contains('2–128'))),
    );
    final short = Uint8List.fromList('LUT_3D_SIZE 17\n0 0 0\n'.codeUnits);
    await expectLater(
      library.import('b.cube', short),
      throwsA(isA<LutImportException>()
          .having((e) => e.reason, 'reason', contains('4913'))),
    );
  });

  test('explains out-of-range values', () async {
    engine.validateError = ImagingErrorCode.lutRange;
    await expectLater(
      library.import('c.cube', identity(17)),
      throwsA(isA<LutImportException>()
          .having((e) => e.reason, 'reason', contains('超出'))),
    );
    expect(await library.entries(), hasLength(5));
  });
}
