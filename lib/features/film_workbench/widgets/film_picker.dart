import 'package:flutter/material.dart';
import '../../../film/catalog/film_catalog.dart';
import 'workbench_style.dart';

class FilmPicker extends StatelessWidget {
  const FilmPicker(
      {super.key,
      required this.films,
      required this.selectedId,
      required this.onSelect});
  final List<FilmDefinition> films;
  final int selectedId;
  final ValueChanged<FilmDefinition> onSelect;
  @override
  Widget build(BuildContext context) => SizedBox(
      height: 128,
      child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          itemCount: films.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final film = films[index], selected = film.id == selectedId;
            return Semantics(
                selected: selected,
                button: true,
                label: '选择${film.name}',
                child: InkWell(
                    onTap: () => onSelect(film),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: MediaQuery.of(context).disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      width: 86,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 5),
                      decoration: BoxDecoration(
                          color: selected
                              ? context.palette.raised
                              : context.palette.raised,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: selected
                                  ? context.palette.accent
                                  : Colors.transparent)),
                      child: Column(children: [
                        Image.asset(film.icon,
                            height: 44,
                            width: 44,
                            filterQuality: FilterQuality.none),
                        const SizedBox(height: 8),
                        Text(film.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.palette.text, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(film.group,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.palette.muted, fontSize: 10))
                      ]),
                    )));
          }));
}

Future<FilmDefinition?> showFilmPicker(
        BuildContext context, FilmCatalog catalog) =>
    showModalBottomSheet<FilmDefinition>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        sheetAnimationStyle: workbenchSheetAnimation(context),
        builder: (context) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: .8,
            minChildSize: .4,
            maxChildSize: .95,
            builder: (context, scroll) =>
                _SearchFilms(catalog: catalog, scroll: scroll)));

class _SearchFilms extends StatefulWidget {
  const _SearchFilms({required this.catalog, required this.scroll});
  final FilmCatalog catalog;
  final ScrollController scroll;
  @override
  State<_SearchFilms> createState() => _SearchFilmsState();
}

class _SearchFilmsState extends State<_SearchFilms> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final films = widget.catalog.entries
        .where((f) => '${f.name} ${f.group}'
            .toLowerCase()
            .contains(_search.toLowerCase()))
        .toList();
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索胶卷',
                  border: OutlineInputBorder()))),
      Expanded(
          child: ListView.builder(
              controller: widget.scroll,
              itemCount: films.length,
              itemBuilder: (context, i) => ListTile(
                  leading: Image.asset(films[i].icon, width: 40, height: 40),
                  title: Text(films[i].name),
                  subtitle: Text(films[i].group),
                  onTap: () => Navigator.pop(context, films[i]))))
    ]);
  }
}
