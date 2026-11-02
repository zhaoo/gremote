import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Keep native image coordinates intact; change the workspace around the image.
class ShootWorkspaceLayout extends StatelessWidget {
  const ShootWorkspaceLayout(
      {required this.header,
      required this.viewfinder,
      required this.controls,
      super.key});
  final List<Widget> header, controls;
  final Widget viewfinder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth <= box.maxHeight) {
          return Column(
              children: [...header, Expanded(child: viewfinder), ...controls]);
        }
        return Column(children: [
          ...header,
          Expanded(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Expanded(child: viewfinder),
                SizedBox(
                    width: math.min(310, box.maxWidth * .38),
                    child: Column(children: [
                      Expanded(
                          child: SingleChildScrollView(
                              child: Column(
                                  children: controls
                                      .take(controls.length - 1)
                                      .toList()))),
                      controls.last,
                    ])),
              ])),
        ]);
      });
}
