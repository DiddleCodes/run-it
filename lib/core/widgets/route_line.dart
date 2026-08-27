import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The app's signature visual motif: a continuous curved line with dots
/// along it, standing for an order's journey. [StatusStepper] expresses
/// this vocabulary as discrete step nodes; the widgets here express it as
/// a single flowing curve — used for empty-state illustrations, a
/// decorative backdrop, and the KYC-approved "journey complete" moment.

Path _dashedPath(Path source, {double dashLength = 6, double gapLength = 6}) {
  final dashed = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var draw = true;
    while (distance < metric.length) {
      final next = distance + (draw ? dashLength : gapLength);
      if (draw) {
        dashed.addPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          Offset.zero,
        );
      }
      distance = next;
      draw = !draw;
    }
  }
  return dashed;
}

Path _journeyCurve(Size size) {
  final path = Path()..moveTo(0, size.height * 0.75);
  path.cubicTo(
    size.width * 0.28,
    size.height * 0.75,
    size.width * 0.22,
    size.height * 0.1,
    size.width * 0.52,
    size.height * 0.22,
  );
  path.cubicTo(
    size.width * 0.78,
    size.height * 0.32,
    size.width * 0.74,
    size.height * 0.85,
    size.width,
    size.height * 0.7,
  );
  return path;
}

/// A quiet, low-opacity curved line meant to sit behind foreground
/// content (e.g. the account-type entry screen) — pure decoration, never
/// interactive.
class RouteLineBackdrop extends StatelessWidget {
  const RouteLineBackdrop({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final line = color ?? AppColors.primaryMaroon;
    return IgnorePointer(
      child: CustomPaint(
        painter: _BackdropPainter(line.withValues(alpha: 0.10)),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(_dashedPath(_journeyCurve(size), dashLength: 5, gapLength: 9), paint);

    final dotPaint = Paint()..color = color;
    canvas.drawCircle(Offset(size.width * 0.52, size.height * 0.22), 3.5, dotPaint);
    canvas.drawCircle(Offset(size.width, size.height * 0.7), 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => oldDelegate.color != color;
}

/// Empty-state illustration: a dotted route with no destination yet,
/// ending in a gently pulsing dot rather than a generic icon. Respects
/// reduced-motion — the pulse simply doesn't run when disabled.
class RouteLineEmptyIllustration extends StatefulWidget {
  const RouteLineEmptyIllustration({super.key, this.width = 220, this.height = 130});
  final double width;
  final double height;

  @override
  State<RouteLineEmptyIllustration> createState() => _RouteLineEmptyIllustrationState();
}

class _RouteLineEmptyIllustrationState extends State<RouteLineEmptyIllustration>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (!MediaQuery.of(context).disableAnimations) {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const line = AppColors.borderSubtle;
    const dot = AppColors.primaryMaroon;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final pulse = reduceMotion ? 1.0 : (1.0 + _controller.value * 0.18);
          final glow = reduceMotion ? 0.5 : (0.35 + _controller.value * 0.4);
          return CustomPaint(
            painter: _EmptyRoutePainter(
              lineColor: line,
              dotColor: dot,
              pulseScale: pulse,
              dotOpacity: glow,
            ),
          );
        },
      ),
    );
  }
}

class _EmptyRoutePainter extends CustomPainter {
  _EmptyRoutePainter({
    required this.lineColor,
    required this.dotColor,
    required this.pulseScale,
    required this.dotOpacity,
  });
  final Color lineColor;
  final Color dotColor;
  final double pulseScale;
  final double dotOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(size.width * 0.06, size.height * 0.55);
    path.cubicTo(
      size.width * 0.3,
      size.height * 0.1,
      size.width * 0.55,
      size.height * 0.95,
      size.width * 0.82,
      size.height * 0.45,
    );

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(_dashedPath(path, dashLength: 5, gapLength: 7), linePaint);

    // Start marker — where the "route" begins, deliberately unremarkable.
    canvas.drawCircle(
      Offset(size.width * 0.06, size.height * 0.55),
      3,
      Paint()..color = lineColor,
    );

    // The pulsing "no destination yet" dot at the open end of the route.
    final end = Offset(size.width * 0.82, size.height * 0.45);
    canvas.drawCircle(end, 10 * pulseScale, Paint()..color = dotColor.withValues(alpha: dotOpacity * 0.3));
    canvas.drawCircle(end, 5, Paint()..color = dotColor.withValues(alpha: dotOpacity + 0.3));
  }

  @override
  bool shouldRepaint(covariant _EmptyRoutePainter oldDelegate) =>
      oldDelegate.pulseScale != pulseScale || oldDelegate.dotOpacity != dotOpacity;
}

/// The KYC-approval signature moment: the route line literally draws
/// itself from start to a filled, checkmarked destination dot. Skips
/// straight to the finished state when reduced-motion is requested.
class RouteLineReveal extends StatefulWidget {
  const RouteLineReveal({super.key, this.size = 140, this.onComplete});
  final double size;
  final VoidCallback? onComplete;

  @override
  State<RouteLineReveal> createState() => _RouteLineRevealState();
}

class _RouteLineRevealState extends State<RouteLineReveal>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onComplete?.call());
    } else {
      _controller.forward().whenComplete(() => widget.onComplete?.call());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dot = AppColors.primaryMaroon;
    const onDot = AppColors.onMaroon;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final drawT = Curves.easeOutCubic.transform(
            (_controller.value / 0.75).clamp(0, 1).toDouble(),
          );
          final dotT = Curves.easeOutBack.transform(
            ((_controller.value - 0.7) / 0.3).clamp(0, 1).toDouble(),
          );
          return CustomPaint(
            painter: _RevealPainter(lineColor: dot, drawT: drawT, dotT: dotT),
            child: dotT > 0
                ? Align(
                    alignment: const Alignment(0.6, -0.5),
                    child: Transform.scale(
                      scale: dotT,
                      child: Icon(Icons.check_rounded, color: onDot, size: widget.size * 0.16),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}

class _RevealPainter extends CustomPainter {
  _RevealPainter({required this.lineColor, required this.drawT, required this.dotT});
  final Color lineColor;
  final double drawT;
  final double dotT;

  @override
  void paint(Canvas canvas, Size size) {
    final full = _journeyCurve(size);
    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (final metric in full.computeMetrics()) {
      final drawn = metric.extractPath(0, metric.length * drawT);
      canvas.drawPath(drawn, paint);
    }

    if (dotT > 0) {
      final end = Offset(size.width, size.height * 0.7);
      canvas.drawCircle(end, 14 * dotT, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant _RevealPainter oldDelegate) =>
      oldDelegate.drawT != drawT || oldDelegate.dotT != dotT;
}
