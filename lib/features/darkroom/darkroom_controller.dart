import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../darkroom/darkroom_providers.dart';
import '../../darkroom/lut/lut_library.dart';
import '../../darkroom/model/edit_document.dart';
import '../../darkroom/store/darkroom_store.dart';

@immutable
class DarkroomOverview {
  const DarkroomOverview({
    required this.edits,
    required this.luts,
    required this.presets,
  });

  final List<EditDocument> edits;
  final List<LutEntry> luts;
  final List<ExportPreset> presets;
}

final darkroomOverviewProvider = FutureProvider((ref) async {
  ref.watch(darkroomRevisionProvider);
  final store = ref.watch(darkroomStoreProvider);
  return DarkroomOverview(
    edits: await store.recentEdits(),
    luts: await ref.watch(lutLibraryProvider).entries(),
    presets: await store.presets(),
  );
});

abstract interface class LutFilePicker {
  Future<(String name, Uint8List bytes)?> pick();
}

class SystemLutFilePicker implements LutFilePicker {
  const SystemLutFilePicker();

  @override
  Future<(String name, Uint8List bytes)?> pick() async {
    const types = XTypeGroup(
      label: '3D LUT (.cube)',
      extensions: ['cube'],
      mimeTypes: ['text/plain', 'application/octet-stream'],
    );
    final file = await openFile(acceptedTypeGroups: const [types]);
    return file == null ? null : (file.name, await file.readAsBytes());
  }
}

final lutFilePickerProvider =
    Provider<LutFilePicker>((ref) => const SystemLutFilePicker());

class DarkroomActions {
  DarkroomActions(this.ref);

  final Ref ref;

  Future<LutEntry?> importLut() async {
    final picked = await ref.read(lutFilePickerProvider).pick();
    if (picked == null) return null;
    final (name, bytes) = picked;
    final lut = await ref.read(lutLibraryProvider).import(name, bytes);
    _changed();
    return lut;
  }

  Future<void> deleteLut(String id) async {
    await ref.read(lutLibraryProvider).delete(id);
    _changed();
  }

  Future<void> renamePreset(String id, String name) async {
    await ref.read(darkroomStoreProvider).renamePreset(id, name);
    _changed();
  }

  Future<void> deletePreset(String id) async {
    await ref.read(darkroomStoreProvider).deletePreset(id);
    _changed();
  }

  void _changed() => ref.read(darkroomRevisionProvider.notifier).state++;
}

final darkroomActionsProvider = Provider(DarkroomActions.new);
