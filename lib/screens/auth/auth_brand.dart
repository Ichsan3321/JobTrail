import 'package:flutter/material.dart';

/// Official Figma mark (172:1877), rasterized without altering its SVG layers.
class AuthBrand extends StatelessWidget {
  const AuthBrand({super.key, this.size = 46, this.wordmark = true});
  final double size;
  final bool wordmark;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        label: 'JobTrail',
        image: true,
        child: SizedBox.square(
          dimension: size,
          child: Image.asset(
            'assets/home/auth-official-mark.png',
            excludeFromSemantics: true,
            fit: BoxFit.contain,
          ),
        ),
      ),
      if (wordmark) ...[
        const SizedBox(width: 11),
        const Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'JobTrail',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              Text('Your career, on track.', style: TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ],
    ],
  );
}
