import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../darkroom/darkroom_providers.dart';
import 'home_cover_providers.dart';
import 'home_cover_settings.dart';
import '../../media/local/local_media_repository.dart';

class HomeCoverManager extends ConsumerStatefulWidget {
  const HomeCoverManager(
      {required this.data, this.aspectRatio = 390 / 232, super.key});
  final HomeCoverData data;
  final double aspectRatio;
  @override
  ConsumerState<HomeCoverManager> createState() => _HomeCoverManagerState();
}

class _HomeCoverManagerState extends ConsumerState<HomeCoverManager> {
  late List<HomeCoverEntry> _entries;
  late bool _autoplay, _default, _manual;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final s = widget.data.settings;
    _entries = s.entries.isEmpty
        ? widget.data.recentFrames.map((f) => f.entry).toList()
        : s.entries.toList();
    _autoplay = s.autoplay;
    _default = s.useDefault;
    _manual = s.entries.isNotEmpty;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(homeCoverRepositoryProvider).save(HomeCoverSettings(
          useDefault: _default,
          autoplay: _autoplay,
          entries: _manual ? _entries : const []));
      ref.read(homeCoverRevisionProvider.notifier).state++;
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '保存失败，请重试';
          _saving = false;
        });
      }
    }
  }

  void _toggle(HomeCoverEntry item) {
    setState(() {
      _default = false;
      _manual = true;
      final at =
          _entries.indexWhere((e) => e.id == item.id && e.uri == item.uri);
      if (at >= 0) {
        _entries.removeAt(at);
        if (_entries.isEmpty) _default = true;
      } else if (_entries.length < 5) {
        _entries.add(item);
      } else {
        _error = '最多选择 5 张';
      }
    });
  }

  Future<void> _frame(int index) async {
    final item = _entries[index];
    final current = await ref.read(homeCoverDataProvider.future);
    if (!current.available.any((e) => e.id == item.id && e.uri == item.uri)) {
      throw StateError('照片暂不可读');
    }
    final bytes = await ref.read(mediaGatewayProvider).thumbnail(item.id, 1024);
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _error = '照片暂不可读');
      return;
    }
    final changed = await showDialog<HomeCoverEntry>(
        context: context,
        builder: (_) => _FramingDialog(
            entry: item, bytes: bytes, aspectRatio: widget.aspectRatio));
    if (changed != null && mounted) {
      setState(() {
        _manual = true;
        _entries[index] = changed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(homeCoverDataProvider);
    final available = current.isLoading
        ? <LocalMediaItem>[]
        : current.valueOrNull?.available ?? <LocalMediaItem>[];
    return FractionallySizedBox(
        heightFactor: .88,
        child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AbsorbPointer(
                  absorbing: _saving,
                  child: Column(children: [
                    Row(children: [
                      const Expanded(
                          child: Text('作品封面', style: TextStyle(fontSize: 20))),
                      TextButton(
                          onPressed: _save,
                          child: Text(_saving ? '保存中…' : '完成'))
                    ]),
                    if (widget.data.configError)
                      const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text('原封面配置无法读取，请重新选择或恢复默认。')),
                    if (_error != null)
                      Text(_error!,
                          style: const TextStyle(color: Colors.redAccent)),
                    Expanded(
                        child: CustomScrollView(slivers: [
                      SliverToBoxAdapter(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Wrap(spacing: 8, children: [
                              ChoiceChip(
                                  label: const Text('最近导入'),
                                  selected: !_default && !_manual,
                                  onSelected: (_) => setState(() {
                                        _default = false;
                                        _manual = false;
                                        _entries = (current.valueOrNull
                                                    ?.recentFrames ??
                                                widget.data.recentFrames)
                                            .map((f) => f.entry)
                                            .toList();
                                      })),
                              ChoiceChip(
                                  label: const Text('默认街景'),
                                  selected: _default,
                                  onSelected: (_) => setState(() {
                                        _default = true;
                                        _manual = false;
                                        _entries = [];
                                      })),
                            ]),
                            SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('自动轮播'),
                                subtitle: const Text('每 8 秒切换，触摸暂停'),
                                value: _autoplay,
                                onChanged: (v) =>
                                    setState(() => _autoplay = v)),
                            if (!_default) ...[
                              const SizedBox(height: 8),
                              Text(
                                  _manual
                                      ? '已选 ${_entries.length} / 5 · 单张即固定封面'
                                      : '最近导入的最多 5 张',
                                  style: const TextStyle(fontSize: 12)),
                              for (var i = 0; i < _entries.length; i++)
                                ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                        available
                                                .where((e) =>
                                                    e.id == _entries[i].id &&
                                                    e.uri == _entries[i].uri)
                                                .firstOrNull
                                                ?.displayName ??
                                            '照片暂不可用',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    leading: Text('${i + 1}'),
                                    trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                              tooltip: '调整取景位置',
                                              onPressed: () async {
                                                try {
                                                  await _frame(i);
                                                } catch (_) {
                                                  if (mounted) {
                                                    setState(() =>
                                                        _error = '照片暂不可读');
                                                  }
                                                }
                                              },
                                              icon: const Icon(Icons.crop)),
                                          IconButton(
                                              tooltip: '前移',
                                              onPressed: i == 0
                                                  ? null
                                                  : () => setState(() {
                                                        _manual = true;
                                                        final e = _entries
                                                            .removeAt(i);
                                                        _entries.insert(
                                                            i - 1, e);
                                                      }),
                                              icon: const Icon(
                                                  Icons.arrow_upward)),
                                          IconButton(
                                              tooltip: '移除封面',
                                              onPressed: () =>
                                                  _toggle(_entries[i]),
                                              icon: const Icon(Icons.close)),
                                        ])),
                            ],
                            const SizedBox(height: 16),
                            const Text('从相册选择', style: TextStyle(fontSize: 14)),
                            if (available.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Text('导入照片后可选择作品封面')),
                          ])),
                      SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 4,
                                  mainAxisSpacing: 4),
                          delegate:
                              SliverChildBuilderDelegate((context, index) {
                            final item = available[index];
                            final selected = !_default &&
                                _entries.any((e) =>
                                    e.id == item.id && e.uri == item.uri);
                            return Semantics(
                                selected: selected,
                                button: true,
                                label: item.displayName,
                                child: InkWell(
                                    onTap: () => _toggle(HomeCoverEntry(
                                        id: item.id, uri: item.uri)),
                                    child:
                                        Stack(fit: StackFit.expand, children: [
                                      _CoverThumbnail(id: item.id),
                                      if (selected)
                                        const Positioned(
                                            top: 6,
                                            right: 6,
                                            child: Icon(Icons.check_circle,
                                                color: Colors.white,
                                                shadows: [
                                                  Shadow(
                                                      color: Colors.black,
                                                      blurRadius: 5)
                                                ])),
                                    ])));
                          }, childCount: available.length)),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ])),
                  ])),
            )));
  }
}

class _CoverThumbnail extends ConsumerWidget {
  const _CoverThumbnail({required this.id});
  final int id;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(thumbnailProvider(id)).when(
          data: (bytes) => bytes == null
              ? const ColoredBox(color: Color(0xFF24282B))
              : Image.memory(bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined)),
          loading: () => const ColoredBox(color: Color(0xFF24282B)),
          error: (_, __) => const Icon(Icons.broken_image_outlined));
}

class _FramingDialog extends StatefulWidget {
  const _FramingDialog(
      {required this.entry, required this.bytes, required this.aspectRatio});
  final HomeCoverEntry entry;
  final Uint8List bytes;
  final double aspectRatio;
  @override
  State<_FramingDialog> createState() => _FramingDialogState();
}

class _FramingDialogState extends State<_FramingDialog>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    }
  }

  late double x = widget.entry.x, y = widget.entry.y;
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('调整取景位置'),
          content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                AspectRatio(
                    aspectRatio: widget.aspectRatio,
                    child: LayoutBuilder(
                        builder: (_, size) => GestureDetector(
                            onPanUpdate: (d) => setState(() {
                                  x = (x - d.delta.dx / size.maxWidth * 2)
                                      .clamp(-1, 1);
                                  y = (y - d.delta.dy / size.maxHeight * 2)
                                      .clamp(-1, 1);
                                }),
                            child: Image.memory(widget.bytes,
                                fit: BoxFit.cover,
                                alignment: Alignment(x, y),
                                errorBuilder: (_, __, ___) =>
                                    const Center(child: Text('照片暂不可读')))))),
                const Text('水平位置'),
                Slider(
                    value: x,
                    min: -1,
                    max: 1,
                    onChanged: (v) => setState(() => x = v)),
                const Text('垂直位置'),
                Slider(
                    value: y,
                    min: -1,
                    max: 1,
                    onChanged: (v) => setState(() => y = v)),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(
                    context,
                    HomeCoverEntry(
                        id: widget.entry.id,
                        uri: widget.entry.uri,
                        x: x,
                        y: y)),
                child: const Text('确定'))
          ]);
}
