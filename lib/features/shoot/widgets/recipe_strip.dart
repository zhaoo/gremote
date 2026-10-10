import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../camera/recipe/combo_recipe.dart';
import '../../../camera/recipe/recipe_session.dart';

class RecipeStrip extends StatelessWidget {
  const RecipeStrip({
    required this.recipes,
    required this.session,
    required this.onSelect,
    required this.onAdd,
    super.key,
  });

  final List<ComboRecipe> recipes;
  final RecipeSessionState session;
  final ValueChanged<ComboRecipe> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
        height: 72,
        color: const Color(0xF20C100E),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          children: [
            _item(ComboRecipe.factory),
            for (final recipe in recipes) _item(recipe),
            InkWell(
              onTap: onAdd,
              child: const SizedBox(
                width: 74,
                child: Center(
                  child: Text('＋ 新建',
                      style: TextStyle(color: GRemoteColors.gold, fontSize: 11)),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _item(ComboRecipe recipe) {
    final selected = session.active.id == recipe.id;
    return InkWell(
      onTap: () => onSelect(recipe),
      child: SizedBox(
        width: 76,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 32,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: const LinearGradient(
                colors: [Color(0xFF605341), Color(0xFF222923)],
              ),
              border: Border.all(
                color: selected ? GRemoteColors.gold : GRemoteColors.divider,
              ),
            ),
            child: Center(
              child: Text(recipe.effect?.substring(0, 1).toUpperCase() ?? 'R',
                  style: const TextStyle(fontSize: 9)),
            ),
          ),
          const SizedBox(height: 4),
          Text(recipe.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? GRemoteColors.gold : GRemoteColors.text,
                fontSize: 10,
              )),
        ]),
      ),
    );
  }
}
