import 'package:flutter/material.dart';
import 'trial_page.dart';
import 'rolls_page.dart';
import 'camera_films_page.dart';
import 'widgets/workbench_style.dart';

class FilmWorkbenchPage extends StatefulWidget {
  const FilmWorkbenchPage({super.key, this.initialSection = 0});
  final int initialSection;
  @override
  State<FilmWorkbenchPage> createState() => _FilmWorkbenchPageState();
}

class _FilmWorkbenchPageState extends State<FilmWorkbenchPage> {
  late int _section = widget.initialSection.clamp(0, 2);
  @override
  Widget build(BuildContext context) => Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: context.palette.background,
        colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: context.palette.accent, surface: context.palette.raised),
      ),
      child: Scaffold(
        appBar: AppBar(
            backgroundColor: context.palette.background,
            surfaceTintColor: Colors.transparent,
            title: Text.rich(
                TextSpan(children: [
                  const TextSpan(
                      text: 'GRemote',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                  TextSpan(
                      text: '  × M10V',
                      style: TextStyle(
                          color: context.palette.accent,
                          fontSize: 10,
                          letterSpacing: 1)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            actions: [
              Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Center(
                      child: Text('离线可用',
                          style: TextStyle(
                              color: context.palette.muted, fontSize: 11))))
            ]),
        body: SafeArea(
            top: false,
            child: IndexedStack(index: _section, children: [
              TrialPage(
                  active: _section == 0,
                  onStartRoll: () => setState(() => _section = 1),
                  onLoadCamera: () => setState(() => _section = 2)),
              const RollsPage(),
              CameraFilmsPage(active: _section == 2)
            ])),
        bottomNavigationBar: NavigationBar(
            animationDuration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 230),
            backgroundColor: context.palette.background,
            indicatorColor: context.palette.raised,
            selectedIndex: _section,
            onDestinationSelected: (i) => setState(() => _section = i),
            destinations: [
              NavigationDestination(
                  icon: Icon(Icons.tune_outlined, color: context.palette.muted),
                  selectedIcon:
                      Icon(Icons.tune_outlined, color: context.palette.accent),
                  label: '试卷台'),
              NavigationDestination(
                  icon: Icon(Icons.local_movies_outlined,
                      color: context.palette.muted),
                  selectedIcon: Icon(Icons.local_movies_outlined,
                      color: context.palette.accent),
                  label: '数字胶卷'),
              NavigationDestination(
                  icon: Icon(Icons.camera_alt_outlined,
                      color: context.palette.muted),
                  selectedIcon: Icon(Icons.camera_alt_outlined,
                      color: context.palette.accent),
                  label: '相机胶卷'),
            ]),
      ));
}
