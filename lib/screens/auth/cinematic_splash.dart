import 'package:flutter/material.dart';

import '../../core/constants/app_tokens.dart';
import 'auth_brand.dart';

class CinematicSplash extends StatefulWidget {
  const CinematicSplash({super.key, required this.onComplete});

  static const duration = Duration(milliseconds: 2650);
  static const backgroundColor = Color(0xFF100E28);
  final VoidCallback onComplete;

  @override
  State<CinematicSplash> createState() => _CinematicSplashState();
}

class _CinematicSplashState extends State<CinematicSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: CinematicSplash.duration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _finish();
        });
  bool _started = false, _completed = false;

  void _finish() {
    if (!mounted || _completed) return;
    _completed = true;
    widget.onComplete();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else if (!_started && !_completed) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CinematicSplash.backgroundColor,
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) =>
            SplashV2Scene(seconds: _controller.value * 2.65),
      ),
    ),
  );
}

/// The production scene is a pure timeline frame, so exact storyboard stages can
/// also be rendered and compared without timer-dependent screenshot captures.
class SplashV2Scene extends StatelessWidget {
  const SplashV2Scene({super.key, required this.seconds});
  final double seconds;

  // V2: Spark 0s, Trail .5s, Reveal 1.3s, Ready 2.2s, then a short branded hold.
  // Figma supplies storyboard states, not exported prototype easing tracks.
  double _track(List<double> values) {
    const times = [0.0, .5, 1.3, 2.2];
    final time = seconds.clamp(0.0, 2.65);
    for (var i = 1; i < times.length; i++) {
      if (time <= times[i]) {
        final fraction = (time - times[i - 1]) / (times[i] - times[i - 1]);
        final eased = (i == 2 ? Curves.easeInOutCubic : Curves.easeOutCubic)
            .transform(fraction);
        return values[i - 1] + (values[i] - values[i - 1]) * eased;
      }
    }
    return values.last;
  }

  @override
  Widget build(BuildContext context) {
    final logoSize = _track([52, 92, 148, 148]);
    final logoTop = _track([269, 245, 223, 217]);
    final brand = _track([0, 0, 1, 1]);
    final stages = _track([0, .06, .67, 1]);
    final outer = _track([180, 325, 380, 390]);
    final middle = _track([87.15, 215.8, 265.6, 268.92]);
    final orbit = _track([105, 260, 320, 324]);
    final innerOrbit = _track([70.35, 174.2, 214.4, 217.08]);
    final dot = _trackingDot();
    return Semantics(
      label: 'JobTrail. Your career, on track.',
      child: ExcludeSemantics(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 393, maxHeight: 852),
            child: AspectRatio(
              aspectRatio: 393 / 852,
              child: FittedBox(
                fit: BoxFit.contain,
                child: RepaintBoundary(
                  child: SizedBox(
                    key: const ValueKey('splash-v2-canvas'),
                    width: 393,
                    height: 852,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        const Positioned.fill(
                          child: ColoredBox(
                            color: CinematicSplash.backgroundColor,
                          ),
                        ),
                        _art('upper-ambience', -154, -157, 510, 510),
                        _art('right-ambience', 262, 311, 300, 300),
                        _art('lower-aura', -108, 612, 316, 316),
                        _art(
                          'outer-halo',
                          196 - outer / 2,
                          295 - outer / 2,
                          outer,
                          outer,
                          opacity: _track([.6, .9, 1, 1]),
                        ),
                        _art(
                          'mid-halo',
                          196 - middle / 2,
                          295 - middle / 2,
                          middle,
                          middle,
                          opacity: _track([.5, .85, 1, 1]),
                        ),
                        _art(
                          'orbit',
                          196 - orbit / 2,
                          295 - orbit / 2,
                          orbit,
                          orbit,
                          opacity: _track([.4, .85, 1, 1]),
                        ),
                        _art(
                          'secondary-orbit',
                          196 - innerOrbit / 2,
                          295 - innerOrbit / 2,
                          innerOrbit,
                          innerOrbit,
                          opacity: _track([.4, .85, 1, 1]),
                        ),
                        _art(
                          'career-path',
                          31,
                          226,
                          330,
                          260,
                          opacity: _track([.05, .72, 1, 1]),
                        ),
                        _art(
                          'path-start',
                          61,
                          428,
                          7,
                          7,
                          opacity: _track([.05, .75, 1, 1]),
                        ),
                        _art(
                          'path-checkpoint',
                          231,
                          329,
                          10,
                          10,
                          opacity: _track([.05, .8, 1, 1]),
                        ),
                        _art(
                          'marker-glow',
                          dot.dx - 18,
                          dot.dy - 18,
                          36,
                          36,
                          opacity: _track([.5, .9, 1, 1]),
                        ),
                        _art(
                          'marker',
                          dot.dx - 7,
                          dot.dy - 7,
                          14,
                          14,
                          key: const ValueKey('splash-v2-tracking-dot'),
                          opacity: _track([.4, .9, 1, 1]),
                        ),
                        _art(
                          'spark',
                          269,
                          191,
                          20,
                          20,
                          opacity: _track([.08, .7, 1, 1]),
                        ),
                        _text(
                          'JOBTRAIL / YOUR JOURNEY',
                          101,
                          10,
                          left: 37,
                          right: 37,
                          alignment: TextAlign.left,
                          spacing: 1.8,
                          color: const Color(0xFFB9B8D2),
                          opacity: _track([.32, .7, 1, 1]),
                        ),
                        Positioned(
                          left: 196 - (logoSize + 20) / 2,
                          top: logoTop + 10,
                          width: logoSize + 20,
                          height: logoSize + 20,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(
                                alpha: _track([.05, .10, .14, .14]),
                              ),
                              borderRadius: BorderRadius.circular(
                                (logoSize + 20) * .247,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 196 - logoSize / 2,
                          top: logoTop,
                          child: Opacity(
                            opacity: _track([.28, .95, 1, 1]),
                            child: AuthBrand(size: logoSize, wordmark: false),
                          ),
                        ),
                        _text(
                          'JobTrail',
                          _track([506, 498, 493, 484]),
                          42,
                          key: const ValueKey('splash-v2-wordmark'),
                          weight: FontWeight.w700,
                          opacity: brand,
                        ),
                        _text(
                          'Your career, on track.',
                          _track([580, 567, 552, 544]),
                          14,
                          color: const Color(0xFFD1CFFC),
                          opacity: brand,
                        ),
                        Positioned(
                          left: 154,
                          top: _track([619, 606, 593, 585]),
                          width: 85,
                          height: 3,
                          child: Opacity(
                            opacity: brand * .85,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.mint,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        _text(
                          'One journey. Every opportunity.',
                          _track([624, 624, 623, 623]),
                          13,
                          color: const Color(0xFFD0CAE9),
                          opacity: stages,
                        ),
                        Positioned(
                          left: 35,
                          top: 676,
                          width: 323,
                          height: 76,
                          child: Opacity(
                            opacity: _track([0, .05, .58, .86]),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xFF25214A),
                                borderRadius: BorderRadius.circular(21),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 58,
                          top: 686,
                          width: 277,
                          height: 28,
                          child: Opacity(
                            opacity: stages,
                            child: Row(
                              children: [
                                for (var i = 0; i < 3; i++) ...[
                                  if (i != 0)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: Text(
                                        '•',
                                        style: TextStyle(
                                          color: AppColors.mint,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        const ['DISCOVER', 'APPLY', 'GROW'][i],
                                        style: const TextStyle(
                                          fontFamily: AppTypography.bodyFamily,
                                          fontSize: 10,
                                          height: 1.4,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 58,
                          top: 723,
                          width: 277,
                          height: 3,
                          child: Opacity(
                            opacity: stages,
                            child: Stack(
                              children: [
                                const Positioned.fill(
                                  child: ColoredBox(color: Color(0xFF4D4777)),
                                ),
                                SizedBox(
                                  width: _track([0, 80, 220, 277]),
                                  height: 3,
                                  child: const ColoredBox(
                                    color: AppColors.mint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _text(
                          'MADE FOR THE NEXT CHAPTER',
                          _track([796, 796, 789, 789]),
                          10,
                          color: const Color(0xFFA5A1CE),
                          opacity: _track([0, .05, .6, .9]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _art(
    String name,
    double x,
    double y,
    double width,
    double height, {
    double opacity = 1,
    Key? key,
  }) => Positioned(
    key: key,
    left: x,
    top: y,
    width: width,
    height: height,
    child: Opacity(
      opacity: opacity,
      child: Image.asset(
        'assets/home/splash-v2-$name.png',
        fit: BoxFit.fill,
        excludeFromSemantics: true,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );

  Widget _text(
    String text,
    double top,
    double size, {
    Key? key,
    double opacity = 1,
    Color color = Colors.white,
    FontWeight weight = FontWeight.w500,
    double left = 24,
    double right = 24,
    double? spacing,
    TextAlign alignment = TextAlign.center,
  }) => Positioned(
    key: key,
    left: left,
    right: right,
    top: top,
    child: Opacity(
      opacity: opacity,
      child: Text(
        text,
        textAlign: alignment,
        style: TextStyle(
          fontFamily: AppTypography.bodyFamily,
          fontSize: size,
          height: 1.4,
          fontWeight: weight,
          letterSpacing: spacing,
          color: color,
        ),
      ),
    ),
  );

  Offset _trackingDot() {
    if (seconds <= .5) {
      return Offset.lerp(
        const Offset(195, 293),
        _curve.first,
        _track([0, 1, 1, 1]),
      )!;
    }
    final progress = _track([0, 0, .901, 1]) * (_curve.length - 1);
    final index = progress.floor().clamp(0, _curve.length - 2);
    return Offset.lerp(_curve[index], _curve[index + 1], progress - index)!;
  }

  // Arc-length samples of the official V2 SVG curve, not a separately drawn path.
  // Keep the rendered tracking dot on that artwork between storyboard anchors.
  static const _curve = [
    Offset(237.27, 338.11),
    Offset(242.55, 339.66),
    Offset(247.97, 340.58),
    Offset(253.46, 340.74),
    Offset(258.92, 340.06),
    Offset(264.19, 338.52),
    Offset(269.17, 336.19),
    Offset(273.81, 333.23),
    Offset(278.10, 329.79),
    Offset(282.10, 326.01),
    Offset(285.85, 321.99),
    Offset(289.43, 317.81),
    Offset(292.88, 313.52),
    Offset(296.27, 309.19),
    Offset(299.64, 304.84),
    Offset(303.06, 300.53),
    Offset(306.57, 296.29),
    Offset(310.23, 292.19),
    Offset(314.12, 288.30),
    Offset(318.29, 284.71),
    Offset(322.80, 281.57),
    Offset(327.69, 279.05),
    Offset(332.91, 277.32),
    Offset(338.34, 276.51),
    Offset(343.84, 276.63),
  ];
}
