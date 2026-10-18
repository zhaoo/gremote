import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_type.dart';

class CameraImportRecord {
  const CameraImportRecord(
      {required this.uri,
      required this.name,
      required this.mime,
      required this.dateAdded});
  final String uri;
  final String name;
  final String mime;

  /// MediaStore import/publication time in epoch seconds, not EXIF capture time.
  final int dateAdded;
  DateTime get importedAt =>
      DateTime.fromMillisecondsSinceEpoch(dateAdded * 1000);
}

class CameraImportPhoto {
  CameraImportPhoto(
      {required this.name, required this.importedAt, required this.records});
  final String name;
  final DateTime importedAt;
  final List<CameraImportRecord> records;
  Set<String> get formats => records
      .map((record) =>
          record.name.toLowerCase().endsWith('.dng') ? 'RAW' : 'JPG')
      .toSet();
}

/// RAW/JPG pairs and duplicate saved copies represent one photo per import day.
List<CameraImportPhoto> groupCameraImports(List<CameraImportRecord> records) {
  final groups = <String, List<CameraImportRecord>>{};
  final names = <String, String>{};
  for (final record in records) {
    final time = record.importedAt;
    final stem = record.name
        .replaceFirst(RegExp(r'\.[^.]+$'), '')
        .replaceFirst(RegExp(r'(?:_\d+|\s*\(\d+\))$'), '')
        .toUpperCase();
    final key = '${time.year}-${time.month}-${time.day}/$stem';
    groups.putIfAbsent(key, () => []).add(record);
    names[key] = stem;
  }
  return groups.entries.map((entry) {
    final files = entry.value
      ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    return CameraImportPhoto(
        name: names[entry.key]!,
        importedAt: files.first.importedAt,
        records: List.unmodifiable(files));
  }).toList()
    ..sort((a, b) => b.importedAt.compareTo(a.importedAt));
}

int countTodayImports(List<CameraImportPhoto> photos, DateTime now) =>
    photos.where((photo) {
      final date = photo.importedAt;
      return date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    }).length;

final importHistoryProvider =
    FutureProvider<List<CameraImportPhoto>>((ref) async {
  const channel = MethodChannel('gremote/import_history');
  final rows = await channel.invokeListMethod<Object?>('query');
  if (rows == null) throw const FormatException('Missing import history');
  final records = rows.map((row) {
    final data = Map<Object?, Object?>.from(row! as Map);
    return CameraImportRecord(
        uri: data['uri']! as String,
        name: data['name']! as String,
        mime: data['mime']! as String,
        dateAdded: (data['dateAdded']! as num).toInt());
  }).toList();
  return groupCameraImports(records);
});

final todayImportCountProvider = Provider<AsyncValue<int>>((ref) => ref
    .watch(importHistoryProvider)
    .whenData((photos) => countTodayImports(photos, DateTime.now())));

class ImportStatusTile extends ConsumerStatefulWidget {
  const ImportStatusTile({super.key});
  @override
  ConsumerState<ImportStatusTile> createState() => _ImportStatusTileState();
}

class _ImportStatusTileState extends ConsumerState<ImportStatusTile>
    with WidgetsBindingObserver {
  Timer? _midnight;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(importHistoryProvider);
    });
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    _midnight =
        Timer(DateTime(now.year, now.month, now.day + 1).difference(now), () {
      if (!mounted) return;
      ref.invalidate(todayImportCountProvider);
      _scheduleMidnight();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(importHistoryProvider);
      _scheduleMidnight();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(todayImportCountProvider);
    return Material(
      color: GRemoteColors.navy,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: const BorderSide(color: GRemoteColors.divider)),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ImportHistoryPage())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            const Icon(Icons.download_done_rounded,
                size: 19, color: GRemoteColors.goldSoft),
            const SizedBox(width: 12),
            const Expanded(
                child:
                    Text('今日导入', style: TextStyle(color: GRemoteColors.text))),
            Text(
                count.when(
                    data: (value) => '$value 张',
                    loading: () => '…',
                    error: (_, __) => '读取失败'),
                style: GRemoteType.numeric
                    .copyWith(color: GRemoteColors.goldSoft)),
            const SizedBox(width: 5),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: GRemoteColors.muted),
          ]),
        ),
      ),
    );
  }
}

class ImportHistoryPage extends ConsumerWidget {
  const ImportHistoryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(importHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('导入历史'), actions: [
        IconButton(
            tooltip: '刷新导入记录',
            onPressed: () => ref.invalidate(importHistoryProvider),
            icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('读取导入记录失败，请重试'),
          TextButton(
              onPressed: () => ref.invalidate(importHistoryProvider),
              child: const Text('重试')),
        ])),
        data: (photos) => photos.isEmpty
            ? const Center(child: Text('还没有导入记录'))
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(importHistoryProvider);
                  await ref.read(importHistoryProvider.future);
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: photos.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                              '按导入日期记录 · RAW/JPG 与重复保存合并为一张\n仅显示仍保存在本机的相机原图',
                              style: TextStyle(
                                  color: GRemoteColors.muted, fontSize: 12)));
                    }
                    final photo = photos[index - 1];
                    final time = photo.importedAt;
                    String pad(int value) => value.toString().padLeft(2, '0');
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.photo_outlined,
                          color: GRemoteColors.goldSoft),
                      title: Text(photo.name),
                      subtitle: Text(
                          '${time.year}-${pad(time.month)}-${pad(time.day)} ${pad(time.hour)}:${pad(time.minute)}'),
                      trailing: Text(
                          photo.formats.containsAll({'RAW', 'JPG'})
                              ? 'RAW+JPG'
                              : photo.formats.single,
                          style: const TextStyle(
                              color: GRemoteColors.goldSoft, fontSize: 12)),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
