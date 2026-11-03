import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../film/capture/active_roll_context.dart';
import '../../film/model/film_recipe.dart';
import '../../film/model/film_roll.dart';
import '../../film/store/film_repository.dart';
import 'roll_detail_page.dart';
import 'workbench_providers.dart';
import 'widgets/roll_card.dart';
import 'widgets/workbench_style.dart';

class RollsPage extends ConsumerWidget {
  const RollsPage({super.key});
  Future<void> _new(BuildContext context, WidgetRef ref) async {
    try {
      final catalog = await ref.read(filmCatalogProvider.future);
      if (!context.mounted) return;
      final recipe = ref.read(selectedFilmRecipeProvider) ?? catalog.recipe(33);
      final roll = await showCreateRollSheet(
          context, ref.read(filmRepositoryProvider), recipe);
      if (roll != null) {
        ref.read(filmRollRevisionProvider.notifier).state++;
        ref.read(activeRollCaptureContextProvider.notifier).state =
            FrozenRollContext(
                rollId: roll.id, recipeJson: jsonEncode(recipe.toJson()));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolls = ref.watch(filmRollsProvider);
    return rolls.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('胶卷读取失败：$error')),
        data: (rolls) =>
            ListView(key: const PageStorageKey('film-rolls'), children: [
              WorkbenchHeading('数字胶卷', '把一天，拍成一卷。', 'A DAY, A ROLL.',
                  action: IconButton(
                      tooltip: '新建胶卷',
                      onPressed: () => _new(context, ref),
                      icon: Icon(Icons.add, color: context.palette.text))),
              if (rolls.isEmpty)
                Padding(
                    padding: const EdgeInsets.fromLTRB(30, 52, 30, 40),
                    child: Column(children: [
                      Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                              color: context.palette.raised,
                              borderRadius: BorderRadius.circular(24)),
                          child: Icon(Icons.local_movies_outlined,
                              size: 40, color: context.palette.accent)),
                      const SizedBox(height: 26),
                      Text('第一卷，从今天开始',
                          style: TextStyle(
                              fontSize: 22,
                              color: context.palette.text,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Text('选一种颜色，留下一段日常。\n开卷后可导入真实照片，再整理成联系印样。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: context.palette.muted, height: 1.8)),
                      const SizedBox(height: 30),
                      FilledButton(
                          onPressed: () => _new(context, ref),
                          child: const Text('新建胶卷')),
                    ])),
              for (final roll in rolls)
                RollCard(
                    roll: roll,
                    cover: roll.confirmedCount > 0 ? _RollCover(roll.id) : null,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => RollDetailPage(rollId: roll.id)))),
              if (rolls.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('胶卷配方随照片保存 · 原片保留',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11, color: context.palette.muted))),
            ]));
  }
}

Future<FilmRoll?> showCreateRollSheet(
        BuildContext context, FilmRepository repository, FilmRecipe recipe) =>
    showModalBottomSheet<FilmRoll>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        sheetAnimationStyle: workbenchSheetAnimation(context),
        builder: (_) =>
            _CreateRollSheet(repository: repository, recipe: recipe));

class _CreateRollSheet extends StatefulWidget {
  const _CreateRollSheet({required this.repository, required this.recipe});
  final FilmRepository repository;
  final FilmRecipe recipe;
  @override
  State<_CreateRollSheet> createState() => _CreateRollSheetState();
}

class _CreateRollSheetState extends State<_CreateRollSheet> {
  final _name = TextEditingController(),
      _count = TextEditingController(text: '36');
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final roll = await widget.repository.createRoll(
          name: _name.text,
          targetCount: int.tryParse(_count.text) ?? 0,
          recipe: widget.recipe);
      if (mounted) Navigator.pop(context, roll);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              24, 6, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('给这一天起个名字',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text('本卷配方 · ${widget.recipe.name}'),
                const SizedBox(height: 24),
                TextField(
                    controller: _name,
                    maxLength: 24,
                    decoration: const InputDecoration(
                        labelText: '胶卷名称',
                        hintText: '例如：沿河散步',
                        border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(
                    controller: _count,
                    keyboardType: TextInputType.number,
                    maxLength: 3,
                    decoration: const InputDecoration(
                        labelText: '计划张数（1–999）',
                        border: OutlineInputBorder())),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 20),
                FilledButton(
                    onPressed: _busy ? null : _create,
                    child: Text(_busy ? '正在开卷…' : '开始这一卷')),
              ])));
}

class _RollCover extends ConsumerWidget {
  const _RollCover(this.rollId);
  final String rollId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(rollItemsProvider(rollId)).valueOrNull;
    if (items == null || items.isEmpty) {
      return Center(
          child: Icon(Icons.photo_outlined, color: context.palette.muted));
    }
    final image = ref.watch(rollThumbnailProvider(items.first)).valueOrNull;
    return image == null
        ? Center(
            child:
                Icon(Icons.hide_image_outlined, color: context.palette.muted))
        : Image.memory(image, fit: BoxFit.cover, cacheWidth: 640);
  }
}
