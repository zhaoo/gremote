import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../darkroom/darkroom_providers.dart';
import '../../../darkroom/model/export_recipe.dart';
import '../../../darkroom/store/darkroom_store.dart';

/// Lets the user pick the default recipe or a saved preset; pops the recipe.
class RecipeSheet extends ConsumerStatefulWidget {
  const RecipeSheet({required this.count, super.key});

  final int count;

  @override
  ConsumerState<RecipeSheet> createState() => _RecipeSheetState();
}

class _RecipeSheetState extends ConsumerState<RecipeSheet> {
  late final Future<List<ExportPreset>> _presets =
      ref.read(darkroomStoreProvider).presets();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('为 ${widget.count} 张照片选择出图方案',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text('标题与地点沿用每张照片已保存的编辑',
                  style: TextStyle(color: GRemoteColors.muted, fontSize: 12)),
              const SizedBox(height: 12),
              _option(context, '默认方案', describeRecipe(const ExportRecipe()),
                  const ExportRecipe()),
              FutureBuilder(
                future: _presets,
                builder: (context, snapshot) => Column(children: [
                  for (final preset in snapshot.data ?? const <ExportPreset>[])
                    _option(context, preset.name, describeRecipe(preset.recipe),
                        preset.recipe),
                ]),
              ),
            ],
          ),
        ),
      );

  Widget _option(BuildContext context, String title, String subtitle,
          ExportRecipe recipe) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(subtitle,
            style: const TextStyle(color: GRemoteColors.muted, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: GRemoteColors.muted),
        onTap: () => Navigator.of(context).pop(recipe),
      );
}

String describeRecipe(ExportRecipe recipe) => [
      recipe.lutId == null
          ? '无 LUT'
          : 'LUT ${(recipe.strength * 100).round()}%',
      recipe.frame.label,
      recipe.ratio.label,
      recipe.size.label,
      '质量 ${recipe.quality}',
      if (recipe.keepGps) '保留 GPS',
    ].join(' · ');
