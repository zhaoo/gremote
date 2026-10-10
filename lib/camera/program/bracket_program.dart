import '../recipe/combo_recipe.dart';
import '../sync/camera_state.dart';
import 'program.dart';

class CustomBracketProgram implements Program {
  CustomBracketProgram({
    required this.wireKey,
    required List<String> options,
    required this.centerIndex,
    required this.count,
    required this.stepIndices,
  }) : _values = _buildValues(
          options,
          centerIndex,
          count,
          stepIndices,
        ) {
    if (count < 2 || count > 15) {
      throw ArgumentError.value(count, 'count', 'must be 2–15');
    }
    if (stepIndices < 1) {
      throw ArgumentError.value(stepIndices, 'stepIndices', 'must be positive');
    }
    if (centerIndex < 0 || centerIndex >= options.length) {
      throw RangeError.index(centerIndex, options, 'centerIndex');
    }
  }

  final String wireKey;
  final int centerIndex;
  final int count;
  final int stepIndices;
  final List<String> _values;

  static List<int> offsets(int count, int step) {
    if (count <= 0 || step <= 0) return const [];
    final values = <int>[0];
    for (var distance = step; values.length < count; distance += step) {
      values.add(-distance);
      if (values.length < count) values.add(distance);
    }
    return values;
  }

  static List<String> _buildValues(
      List<String> options, int center, int count, int step) {
    if (count < 2 ||
        count > 15 ||
        step < 1 ||
        center < 0 ||
        center >= options.length) {
      return const [];
    }
    return [
      for (final offset in offsets(count, step))
        if (center + offset >= 0 && center + offset < options.length)
          options[center + offset],
    ];
  }

  @override
  String get kind => 'customBracket';
  @override
  String get label => '自定义包围';
  @override
  int get frameCount => _values.length;
  @override
  Duration? get interval => null;
  @override
  bool get supportsNudge => false;

  @override
  String? refusal(CameraState state) {
    final param = state.params[wireKey];
    if (param?.writable != true) return '参数不可写';
    if (_values.length < 2) return '可用档位不足';
    if (_values.any((value) => !param!.options.contains(value))) {
      return '相机档位已变化';
    }
    return null;
  }

  @override
  Future<ProgramStep> step(ProgramContext context) async =>
      ProgramStep(params: {wireKey: _values[context.index]});
}

class RecipeBracketProgram implements Program {
  RecipeBracketProgram(List<ComboRecipe> recipes)
      : recipes = List.unmodifiable(recipes) {
    if (recipes.length < 2 || recipes.length > 8) {
      throw ArgumentError.value(recipes.length, 'recipes', 'must contain 2–8');
    }
    if (recipes.any((recipe) => recipe.effect == null)) {
      throw ArgumentError('every bracket recipe must select a camera effect');
    }
  }

  final List<ComboRecipe> recipes;

  @override
  String get kind => 'recipeBracket';
  @override
  String get label => '配方包围';
  @override
  int get frameCount => recipes.length;
  @override
  Duration? get interval => null;
  @override
  bool get supportsNudge => false;

  @override
  String? refusal(CameraState state) {
    final effect = state.params['effect'];
    if (effect?.writable != true) return '机内配方不可写';
    if (recipes.any((recipe) => !effect!.options.contains(recipe.effect))) {
      return '配方不受当前相机支持';
    }
    return null;
  }

  @override
  Future<ProgramStep> step(ProgramContext context) async {
    final recipe = recipes[context.index];
    return ProgramStep(
      params: {'effect': recipe.effect!},
      recipeId: recipe.id,
    );
  }
}
