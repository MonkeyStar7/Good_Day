import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Layout the entire Navigator (including overlays) at its logical size, then
/// redraw its vector content at the chosen scale. No bitmap filter is used.
class AppViewport extends StatelessWidget {
  const AppViewport({super.key, required this.scale, required this.child});
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(
        constraints.maxWidth / scale,
        constraints.maxHeight / scale,
      );
      final query = MediaQuery.of(context);
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: MediaQuery(
              data: query.copyWith(
                size: size,
                devicePixelRatio: query.devicePixelRatio * scale,
                padding: query.padding * (1 / scale),
                viewPadding: query.viewPadding * (1 / scale),
                viewInsets: query.viewInsets * (1 / scale),
              ),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// The OS supplies the desktop blur; this filter also frosts route content
/// behind dialogs without reducing the opacity of their text or controls.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 12,
    this.material = false,
  });
  final Widget child;
  final double radius;
  final bool material;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: material
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(context.appColors.paper, Colors.white, 0.09)!,
                    context.appColors.paper,
                    context.appColors.paper.withValues(
                      alpha: (context.appColors.paper.a - 0.045).clamp(0, 1),
                    ),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
              child: CustomPaint(painter: _GlassTexture(radius), child: child),
            )
          : child,
    ),
  );
}

/// A subtle, stationary grain and edge highlight. Drawn behind the content,
/// so translucent material never fades text or interactive controls.
class _GlassTexture extends CustomPainter {
  const _GlassTexture(this.radius);
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(17);
    final light = Paint()..color = Colors.white.withValues(alpha: 0.08);
    final dark = Paint()
      ..color = const Color(0xFF243039).withValues(alpha: 0.022);
    final count = (size.width * size.height / 48).round();
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        0.45,
        i.isEven ? light : dark,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.7),
        Radius.circular(radius),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassTexture oldDelegate) =>
      radius != oldDelegate.radius;
}
