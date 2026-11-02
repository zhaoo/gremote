import 'package:flutter/material.dart';

class DefaultHomeCover extends StatelessWidget {
  const DefaultHomeCover({super.key});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.5);
    return SizedBox(
      height: 232 + (scale - 1) * 115,
      child: Stack(fit: StackFit.expand, children: [
        Image.asset('assets/images/home_header.jpg', fit: BoxFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0x77111411), Color(0x00111411)])),
        ),
        Positioned(
          left: 24,
          right: 20,
          top: 22,
          bottom: 19,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('走上',
                style: TextStyle(
                    fontFamily: 'GRemoteEditorial',
                    fontFamilyFallback: ['Noto Serif CJK SC'],
                    fontSize: 21,
                    letterSpacing: 5,
                    color: Color(0xFFF0EEE7))),
            const Padding(
              padding: EdgeInsets.only(left: 19, top: 5),
              child: Text('街头',
                  style: TextStyle(
                      fontFamily: 'GRemoteEditorial',
                      fontFamilyFallback: ['Noto Serif CJK SC'],
                      fontSize: 43,
                      height: 1.15,
                      letterSpacing: 4,
                      color: Color(0xFFF0EEE7))),
            ),
            const Spacer(),
            Container(width: 22, height: 1, color: const Color(0x99E1E0DA)),
            const SizedBox(height: 9),
            const Text('让平凡的日子，\n留下不平凡的眼光。',
                style: TextStyle(
                    fontSize: 11,
                    height: 1.8,
                    letterSpacing: .8,
                    color: Color(0xFFE1E0DA))),
          ]),
        ),
      ]),
    );
  }
}
