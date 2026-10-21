import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../darkroom/darkroom_providers.dart';
import '../../film/export/canvas_contact_sheet_rasterizer.dart';
import '../../film/export/contact_sheet_exporter.dart';
import '../../film/export/contact_sheet_layout.dart';
import '../../film/export/ffi_generated_jpeg_encoder.dart';
import '../../film/export/recipe_card_codec.dart';
import '../../film/model/film_recipe.dart';
import '../../film/model/film_roll.dart';
import '../../imaging/imaging_engine.dart';

final contactSheetExporterProvider = Provider((ref) => ContactSheetExporter(
    gateway: ref.watch(mediaGatewayProvider),
    rasterizer: const CanvasContactSheetRasterizer(),
    encoder: const FfiGeneratedJpegEncoder()));

class RollExportPage extends ConsumerStatefulWidget {
  const RollExportPage(
      {super.key,
      required this.roll,
      required this.items,
      required this.recipe});
  final FilmRoll roll;
  final List<RollItem> items;
  final FilmRecipe recipe;
  @override
  ConsumerState<RollExportPage> createState() => _RollExportPageState();
}

class _RollExportPageState extends ConsumerState<RollExportPage> {
  bool _selectedOnly = false, _busy = false;
  ImagingCancelToken? _token;
  final _pages = <int, ContactSheetProgress>{};
  String? _error;
  List<RollItem> get _items =>
      widget.items.where((i) => !_selectedOnly || i.selected).toList();
  Future<void> _start({bool retry = false}) async {
    if (_busy) return;
    final failed = retry
        ? _pages.entries
            .where((e) => e.value.status == ContactSheetStatus.failed)
            .map((e) => e.key)
            .toSet()
        : null;
    setState(() {
      _busy = true;
      _error = null;
      if (!retry) _pages.clear();
    });
    final token = _token = ImagingCancelToken();
    try {
      await for (final progress in ref
          .read(contactSheetExporterProvider)
          .export(widget.roll, _items, cancel: token, pageIndices: failed)) {
        if (mounted) setState(() => _pages[progress.pageIndex] = progress);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '无法导出：$error');
    } finally {
      _token = null;
      token.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareRecipe() async {
    try {
      await ref
          .read(mediaGatewayProvider)
          .shareRecipe(RecipeCardCodec.encode(widget.recipe));
    } catch (error) {
      if (mounted) setState(() => _error = '配方卡分享失败：$error');
    }
  }

  Future<void> _share(String uri) async {
    try {
      await ref.read(mediaGatewayProvider).share(uri);
    } catch (error) {
      if (mounted) setState(() => _error = '分享失败：$error');
    }
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.items.where((i) => i.selected).length;
    return Scaffold(
        appBar: AppBar(title: const Text('胶卷出片')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text(widget.roll.name,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('${widget.items.length} 张照片 · $selected 张精选'),
          const SizedBox(height: 28),
          SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('整卷')),
                ButtonSegment(value: true, label: Text('仅精选'))
              ],
              selected: {
                _selectedOnly
              },
              onSelectionChanged: _busy
                  ? null
                  : (values) => setState(() {
                        _selectedOnly = values.single;
                        _pages.clear();
                      })),
          const SizedBox(height: 20),
          Text(
              '每页最多 24 张，预计 ${ContactSheetLayout.pages(_items).length} 页。印样保留原片色彩，缺图会留出位置。'),
          const SizedBox(height: 24),
          FilledButton(
              onPressed: _busy || _items.isEmpty ? null : () => _start(),
              child: Text(_busy ? '正在生成印样…' : '保存联系印样')),
          if (_busy)
            TextButton(
                onPressed: () => _token?.cancel(), child: const Text('取消导出')),
          if (_pages.values.any((p) => p.status == ContactSheetStatus.failed) &&
              !_busy)
            OutlinedButton(
                onPressed: () => _start(retry: true),
                child: const Text('仅重试失败页')),
          for (final progress in _pages.values)
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                    '第 ${progress.pageIndex + 1} / ${progress.totalPages} 页'),
                subtitle: Text(switch (progress.status) {
                  ContactSheetStatus.running => '生成中',
                  ContactSheetStatus.done =>
                    '已保存 · ${progress.missingCount} 张原片暂不可用',
                  ContactSheetStatus.failed => '保存失败，请释放空间或重试',
                  ContactSheetStatus.cancelled => '已取消'
                }),
                trailing: progress.uri == null
                    ? null
                    : IconButton(
                        tooltip: '分享印样',
                        onPressed: () => _share(progress.uri!),
                        icon: const Icon(Icons.ios_share))),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text('把这卷的味道带走', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('配方卡只包含胶卷和效果参数，可在试卷台导入。'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: _shareRecipe,
              icon: const Icon(Icons.ios_share),
              label: const Text('分享配方卡')),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
        ]));
  }
}
