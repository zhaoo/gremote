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
        scaffoldBackgroundColor: workbenchBackground,
        colorScheme: Theme.of(context)
            .colorScheme
            .copyWith(primary: workbenchGold, surface: workbenchSurface),
      ),
      child: Scaffold(
        appBar: AppBar(
            backgroundColor: workbenchBackground,
            surfaceTintColor: Colors.transparent,
            title: const Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: 'GRemote',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                  TextSpan(
                      text: '  × M10V',
                      style: TextStyle(
                          color: workbenchGold,
                          fontSize: 10,
                          letterSpacing: 1)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            actions: const [
              Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: Center(
                      child: Text('离线可用',
                          style:
                              TextStyle(color: workbenchMuted, fontSize: 11))))
            ]),
        body: SafeArea(
            top: false,
            child: IndexedStack(index: _section, children: [
              TrialPage(
                  active: _section == 0,
                  onStartRoll: () => setState(() => _section = 1),
                  onLoadCamera: () => setState(() => _section = 2)),
              const RollsPage(),
              const CameraFilmsPage()
            ])),
        bottomNavigationBar: NavigationBar(
            animationDuration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 230),
            backgroundColor: workbenchBackground,
            indicatorColor: workbenchSurface,
            selectedIndex: _section,
            onDestinationSelected: (i) => setState(() => _section = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.tune_outlined), label: '试卷台'),
              NavigationDestination(
                  icon: Icon(Icons.local_movies_outlined), label: '数字胶卷'),
              NavigationDestination(
                  icon: Icon(Icons.camera_alt_outlined), label: '相机胶卷'),
            ]),
      ));
}
