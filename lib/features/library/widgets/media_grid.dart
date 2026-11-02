import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../camera/recipe/tag_matcher.dart';
import '../../../media/local/local_media_repository.dart';
import '../../../darkroom/darkroom_providers.dart';

class MediaGrid extends StatelessWidget {
  const MediaGrid({
    required this.items,
    required this.selected,
    this.tags = const {},
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final List<LocalMediaItem> items;
  final Set<int> selected;
  final Map<int, TagMatch> tags;
  final ValueChanged<LocalMediaItem> onTap;
  final ValueChanged<LocalMediaItem> onLongPress;

  @override
  Widget build(BuildContext context) {
    final groups = <DateTime, List<LocalMediaItem>>{};
    for (final item in items) {
      final time = DateTime.fromMillisecondsSinceEpoch(
          item.dateTaken ?? item.dateModified * 1000);
      groups
          .putIfAbsent(DateTime(time.year, time.month, time.day), () => [])
          .add(item);
    }
    final now = DateTime.now();
    return CustomScrollView(slivers: [
      for (final group in groups.entries) ...[
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
                child: Text(
                    '${group.key.year == now.year && group.key.month == now.month && group.key.day == now.day ? '今天 · ' : ''}${group.key.year == now.year ? '' : '${group.key.year} 年 '}${group.key.month} 月 ${group.key.day} 日',
                    style: Theme.of(context).textTheme.bodyMedium))),
        SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, mainAxisSpacing: 3, crossAxisSpacing: 3),
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = group.value[index];
                return MediaTile(
                    key: ValueKey('media-${item.id}'),
                    item: item,
                    selected: selected.contains(item.id),
                    tagMatch: tags[item.id],
                    onTap: () => onTap(item),
                    onLongPress: () => onLongPress(item));
              }, childCount: group.value.length),
            )),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ]);
  }
}

class MediaTile extends ConsumerWidget {
  const MediaTile({
    required this.item,
    required this.selected,
    this.tagMatch,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final LocalMediaItem item;
  final bool selected;
  final TagMatch? tagMatch;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(thumbnailProvider(item.id)).valueOrNull;
    return Semantics(
      label: item.displayName,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(fit: StackFit.expand, children: [
          if (bytes != null)
            Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
          else
            const ColoredBox(
              color: GRemoteColors.raised,
              child: Icon(Icons.photo_outlined, color: GRemoteColors.divider),
            ),
          if (tagMatch case final TagMatch match)
            Positioned(
              left: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xCC0C100E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: match.usable
                      ? const Tooltip(message: '胶卷配方', child: Icon(
                          Icons.tune, color: GRemoteColors.text, size: 16))
                      : const Text('待确认', style: TextStyle(
                          color: GRemoteColors.muted, fontSize: 11)),
                ),
              ),
            ),
          if (selected) ...[
            const ColoredBox(color: Color(0x66000000)),
            const Positioned(
              top: 6,
              right: 6,
              child:
                  Icon(Icons.check_circle, color: GRemoteColors.gold, size: 22),
            ),
          ],
        ]),
      ),
    );
  }
}
