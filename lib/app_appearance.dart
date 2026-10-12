import 'dart:ui';

import 'package:flutter/material.dart';

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
  const GlassSurface({super.key, required this.child, this.radius = 12});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: child,
    ),
  );
}
