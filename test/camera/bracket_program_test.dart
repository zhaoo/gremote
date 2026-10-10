import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/program/bracket_program.dart';
import 'package:gremote/camera/program/program.dart';
import 'package:gremote/camera/protocol/props_parser.dart';
import 'package:gremote/camera/recipe/combo_recipe.dart';
import 'package:gremote/camera/sync/camera_state.dart';

CameraState _state() => CameraState.offline.applyProps(parseProps({
      'xv': '0.0',
      'xvList': ['-1.0', '-0.7', '-0.3', '0.0', '+0.3', '+0.7', '+1.0'],
      'effect': 'standard',
      'effectList': ['standard', 'vivid', 'positiveFilm'],
    }));

ProgramContext _context(int index) =>
    ProgramContext(state: _state(), nudgeEv: 0, index: index);

void main() {
  test('offset order is center, negative, positive', () {
    expect(CustomBracketProgram.offsets(7, 1), [0, -1, 1, -2, 2, -3, 3]);
    expect(CustomBracketProgram.offsets(4, 2), [0, -2, 2, -4]);
  });

  test('custom bracket drops values outside the camera list', () async {
    final program = CustomBracketProgram(
      wireKey: 'xv',
      options: const ['-1', '0', '+1'],
      centerIndex: 0,
      count: 5,
      stepIndices: 1,
    );

    expect(program.frameCount, 3);
    expect([
      for (var i = 0; i < program.frameCount; i++)
        (await program.step(_context(i))).params['xv'],
    ], [
      '-1',
      '0',
      '+1'
    ]);
  });

  test('custom bracket refuses invalid counts or a non-writable key', () {
    expect(
        () => CustomBracketProgram(
            wireKey: 'xv',
            options: const ['0', '1'],
            centerIndex: 0,
            count: 1,
            stepIndices: 1),
        throwsArgumentError);
    final program = CustomBracketProgram(
        wireKey: 'av',
        options: const ['2.8', '4.0'],
        centerIndex: 0,
        count: 2,
        stepIndices: 1);
    expect(program.refusal(_state()), isNotNull);
  });

  test('recipe bracket writes effects and carries recipe IDs', () async {
    final recipes = [
      ComboRecipe(
          id: 'a',
          name: 'A',
          effect: 'vivid',
          sort: 0,
          createdAt: DateTime.utc(2026)),
      ComboRecipe(
          id: 'b',
          name: 'B',
          effect: 'positiveFilm',
          sort: 1,
          createdAt: DateTime.utc(2026)),
    ];
    final program = RecipeBracketProgram(recipes);

    expect(program.refusal(_state()), isNull);
    final second = await program.step(_context(1));
    expect(second.params, {'effect': 'positiveFilm'});
    expect(second.recipeId, 'b');
  });
}
