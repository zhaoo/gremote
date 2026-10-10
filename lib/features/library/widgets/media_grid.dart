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
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return MediaTile(
            key: ValueKey('media-${item.id}'),
            item: item,
            selected: selected.contains(item.id),
            tagMatch: tags[item.id],
            onTap: () => onTap(item),
            onLongPress: () => onLongPress(item),
          );
        },
      );
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
                  child: Text(
                    match.usable ? '◍' : '待确认',
                    style: TextStyle(
                      color: match.usable ? GRemoteColors.gold : GRemoteColors.muted,
                      fontSize: match.usable ? 15 : 9,
                    ),
                  ),
                ),
              ),
            ),
          if (selected) ...[
            const ColoredBox(color: Color(0x66000000)),
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.check_circle, color: GRemoteColors.gold, size: 22),
            ),
          ],
        ]),
      ),
    );
  }
}
