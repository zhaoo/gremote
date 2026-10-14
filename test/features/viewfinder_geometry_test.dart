import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/features/shoot/widgets/viewfinder.dart';

void main() {
  test(
      'contain geometry excludes bars and maps all edges for every orientation',
      () {
    for (final image in [
      const Size(600, 400),
      const Size(400, 600),
      const Size(1200, 300)
    ]) {
      for (final viewport in [const Size(300, 500), const Size(800, 200)]) {
        final rect = liveViewImageRect(viewport, image);
        expect(liveViewFocusPoint(rect.topLeft, rect), Offset.zero);
        expect(liveViewFocusPoint(rect.bottomRight, rect), const Offset(1, 1));
        expect(liveViewFocusPoint(rect.center, rect)!.dx, closeTo(.5, 1e-10));
        expect(liveViewFocusPoint(rect.center, rect)!.dy, closeTo(.5, 1e-10));
        expect(liveViewFocusPoint(rect.topLeft - const Offset(1, 1), rect),
            isNull);
      }
    }
  });
}
