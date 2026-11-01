import 'package:flutter/material.dart';
import '../../../film/catalog/film_catalog.dart';
import '../../../film/model/film_recipe.dart';

class TextureSheet extends StatefulWidget {
  const TextureSheet(
      {super.key,
      required this.film,
      required this.recipe,
      required this.onChanged,
      this.readOnlyParameters = const {}});
  final Set<String> readOnlyParameters;
  final FilmDefinition film;
  final FilmRecipe recipe;
  final ValueChanged<Map<String, int>> onChanged;
  @override
  State<TextureSheet> createState() => _TextureSheetState();
}

class _TextureSheetState extends State<TextureSheet> {
  late final _values = {...widget.recipe.resolvedParameters};
  @override
  Widget build(BuildContext context) => SafeArea(
      child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(children: [
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(children: [
                  Expanded(
                      child: Text('调整质感',
                          style: Theme.of(context).textTheme.titleLarge)),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('完成'))
                ])),
            Expanded(
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                    children: [
                  const Text('效果仅用于近似预览，开卷或装入相机后才保存配方。'),
                  const SizedBox(height: 20),
                  for (final entry in widget.film.parameters.entries
                      .where((e) => !widget.readOnlyParameters.contains(e.key)))
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text(entry.value.label)),
                                Text(
                                    '${_values[entry.key] ?? entry.value.defaultValue}')
                              ]),
                              Slider(
                                  semanticFormatterCallback: (v) =>
                                      '${entry.value.label} ${v.round()}',
                                  value: (_values[entry.key] ??
                                          entry.value.defaultValue)
                                      .toDouble(),
                                  min: entry.value.minimum.toDouble(),
                                  max: entry.value.maximum.toDouble(),
                                  divisions:
                                      entry.value.maximum - entry.value.minimum,
                                  onChanged: (v) {
                                    setState(
                                        () => _values[entry.key] = v.round());
                                    widget.onChanged(Map.of(_values));
                                  }),
                            ])),
                ])),
          ])));
}
