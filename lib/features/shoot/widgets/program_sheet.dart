import 'package:flutter/material.dart';

import '../../../camera/params/camera_param.dart';
import '../../../camera/program/bracket_program.dart';
import '../../../camera/program/program.dart';
import '../../../camera/program/ramp_program.dart';
import '../../../camera/recipe/combo_recipe.dart';
import '../../../camera/sync/camera_state.dart';

class ProgramSheet extends StatefulWidget {
  const ProgramSheet({
    required this.kind,
    required this.camera,
    required this.recipes,
    required this.meter,
    super.key,
  });

  final String kind;
  final CameraState camera;
  final List<ComboRecipe> recipes;
  final Future<double?> Function() meter;

  @override
  State<ProgramSheet> createState() => _ProgramSheetState();
}

class _ProgramSheetState extends State<ProgramSheet> {
  var _frames = 3;
  var _interval = 2;
  var _step = 1;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (widget.kind != 'recipeBracket') ...[
              _slider('张数', _frames.toDouble(), 2, 15,
                  (value) => setState(() => _frames = value.round())),
              if (widget.kind == 'customBracket')
                _slider('步长', _step.toDouble(), 1, 3,
                    (value) => setState(() => _step = value.round())),
              if (widget.kind.contains('Ramp'))
                _slider('间隔（秒）', _interval.toDouble(), 2, 30,
                    (value) => setState(() => _interval = value.round())),
            ] else
              Text('将使用前 ${widget.recipes.length.clamp(0, 8)} 个含机内配方的组合配方'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _buildProgram() == null
                    ? null
                    : () => Navigator.pop(context, _buildProgram()),
                child: const Text('开始'),
              ),
            ),
          ]),
        ),
      );

  String get _title => switch (widget.kind) {
        'customBracket' => '自定义包围',
        'recipeBracket' => '配方包围',
        'meteredRamp' => '测光渐变延时（实验）',
        _ => '计划渐变延时',
      };

  Widget _slider(String label, double value, double min, double max,
          ValueChanged<double> onChanged) =>
      Row(children: [
        SizedBox(width: 76, child: Text('$label ${value.round()}')),
        Expanded(
          child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).round(),
              onChanged: onChanged),
        ),
      ]);

  Program? _buildProgram() {
    final camera = widget.camera;
    if (widget.kind == 'customBracket') {
      final param = camera.param(ParamKey.exposureComp);
      if (param == null || param.options.length < 2) return null;
      final center = param.options.indexOf(param.current ?? '');
      return CustomBracketProgram(
        wireKey: param.wireKey,
        options: param.options,
        centerIndex: center < 0 ? param.options.length ~/ 2 : center,
        count: _frames,
        stepIndices: _step,
      );
    }
    if (widget.kind == 'recipeBracket') {
      final recipes = widget.recipes
          .where((recipe) => recipe.effect != null)
          .take(8)
          .toList();
      return recipes.length < 2 ? null : RecipeBracketProgram(recipes);
    }
    final tv = camera.param(ParamKey.shutter);
    final sv = camera.param(ParamKey.iso);
    if (tv?.current == null || sv?.current == null) return null;
    final start = ExposurePair(tv: tv!.current!, sv: sv!.current!);
    final end = ExposurePair(
      tv: tv.options.isEmpty ? tv.current! : tv.options.last,
      sv: sv.options.where((value) => value != 'auto').lastOrNull ??
          sv.current!,
    );
    if (widget.kind == 'meteredRamp') {
      return MeteredRampProgram(
        start: start,
        end: end,
        frames: _frames,
        interval: Duration(seconds: _interval),
        meter: widget.meter,
      );
    }
    return PlannedRampProgram(
      start: start,
      end: end,
      frames: _frames,
      interval: Duration(seconds: _interval),
    );
  }
}
