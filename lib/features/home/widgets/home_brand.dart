import 'package:flutter/material.dart';

class HomeBrand extends StatelessWidget {
  const HomeBrand({super.key});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/gremote_brand_editorial.png',
        width: 108,
        height: 26,
        fit: BoxFit.contain,
        semanticLabel: 'GRemote',
      );
}
