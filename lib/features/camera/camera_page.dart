import 'package:flutter/material.dart';
import 'film_library_page.dart';
import 'extensions_page.dart';

class CameraPage extends StatelessWidget {
  const CameraPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('相机'),
              bottom: const TabBar(tabs: [Tab(text: '胶卷库'), Tab(text: '扩展')])),
          body: const TabBarView(
              children: [FilmLibraryPage(), CameraExtensions()]),
        ),
      );
}
