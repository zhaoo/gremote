import 'package:flutter/material.dart';

import '../shoot_labels.dart';

import '../../../camera/recipe/recipe_store.dart';
import '../../../darkroom/store/darkroom_store.dart';

class RecipeEditorDialog extends StatefulWidget {
  const RecipeEditorDialog({
    required this.effects,
    required this.presets,
    required this.store,
    super.key,
  });

  final List<String> effects;
  final List<ExportPreset> presets;
  final RecipeStore store;

  @override
  State<RecipeEditorDialog> createState() => _RecipeEditorDialogState();
}

class _RecipeEditorDialogState extends State<RecipeEditorDialog> {
  final _name = TextEditingController();
  String? _effect;
  String? _preset;
  String? _error;

  @override
  void initState() {
    super.initState();
    _effect = widget.effects.firstOrNull;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('新建组合配方'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('recipe-name'),
              controller: _name,
              maxLength: 24,
              decoration: InputDecoration(labelText: '名称', errorText: _error),
            ),
            DropdownButtonFormField<String>(
              key: const Key('recipe-effect'),
              value: _effect,
              decoration: const InputDecoration(labelText: '机内配方'),
              onTap: () => FocusScope.of(context).unfocus(),
              items: [
                for (final effect in widget.effects)
                  DropdownMenuItem(
                      value: effect,
                      child: Text(shootValueLabel('effect', effect))),
              ],
              onChanged: (value) {
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() => _effect = value);
              },
            ),
            DropdownButtonFormField<String?>(
              value: _preset,
              decoration: const InputDecoration(labelText: '出图方案'),
              onTap: () => FocusScope.of(context).unfocus(),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('不自动出图')),
                for (final preset in widget.presets)
                  DropdownMenuItem(value: preset.id, child: Text(preset.name)),
              ],
              onChanged: (value) {
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() => _preset = value);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: _save, child: const Text('保存')),
        ],
      );

  Future<void> _save() async {
    try {
      final recipe = await widget.store.create(
        name: _name.text,
        effect: _effect,
        exportPresetId: _preset,
      );
      if (mounted) Navigator.pop(context, recipe);
    } on ArgumentError {
      setState(() => _error = '请输入 1–24 个字符');
    }
  }
}
