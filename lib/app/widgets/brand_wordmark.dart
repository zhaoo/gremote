import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// Retains the existing aperture and type contours. The source is RGB, so the
/// inner filter extracts a continuous alpha mask before the outer filter tints
/// the foreground. Dark paper texture becomes transparent rather than inverted.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({this.width = 108, super.key});
  final double width;

  static const _mask = ColorFilter.matrix([
    0,
    0,
    0,
    0,
    255,
    0,
    0,
    0,
    0,
    255,
    0,
    0,
    0,
    0,
    255,
    .354333,
    1.192,
    .120333,
    0,
    -85,
  ]);

  @override
  Widget build(BuildContext context) => ColorFiltered(
        colorFilter: ColorFilter.mode(context.palette.text, BlendMode.srcIn),
        child: ColorFiltered(
          colorFilter: _mask,
          child: Image.asset('assets/images/gremote_brand_editorial.png',
              width: width,
              height: width * 271 / 1153,
              fit: BoxFit.contain,
              semanticLabel: 'GRemote'),
        ),
      );
}
