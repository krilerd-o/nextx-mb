import 'package:flutter/material.dart';

class NxAppLogo extends StatelessWidget {
  const NxAppLogo({super.key, this.size = 88});

  final double size;

  static const assetPath = 'assets/app_icon.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      semanticLabel: 'MOAI NEXT',
    );
  }
}
