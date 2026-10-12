import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Change the outer window by the same ratio as its contents, preserving a
/// manually resized window and its right edge. Fit to the current work area.
Rect scaledWindowBounds(
  Rect current,
  double oldScale,
  double newScale,
  Rect work,
) {
  final area = work.deflate(12);
  final ratio = newScale / oldScale;
  final width = (current.width * ratio)
      .clamp(math.min(396 * newScale, area.width), area.width)
      .toDouble();
  final height = (current.height * ratio)
      .clamp(math.min(500 * newScale, area.height), area.height)
      .toDouble();
  return Rect.fromLTWH(
    (current.right - width).clamp(area.left, area.right - width),
    current.top.clamp(area.top, area.bottom - height),
    width,
    height,
  );
}

class DesktopWindowSurface {
  static const channel = MethodChannel('good_day/window_surface');
  double scale = 1;
  bool notesVisible = true;
  int selectedNote = 0;
  int noteCount = 3;
  Size? _logicalSize;
  Size? _appliedSize;

  Future<void> resize(double nextScale, {bool initial = false}) async {
    final data = await channel.invokeMapMethod<String, num>('workArea');
    if (data == null) throw StateError('Window work area unavailable');
    final work = Rect.fromLTWH(
      data['left']!.toDouble(),
      data['top']!.toDouble(),
      data['width']!.toDouble(),
      data['height']!.toDouble(),
    );
    final current = await windowManager.getBounds();
    if (initial) {
      _logicalSize = const Size(456, 720);
    } else if (_appliedSize == null ||
        (current.width - _appliedSize!.width).abs() > 1 ||
        (current.height - _appliedSize!.height).abs() > 1) {
      _logicalSize = Size(current.width / scale, current.height / scale);
    }
    final previousScale = initial ? 1.0 : scale;
    final base = Rect.fromLTWH(
      current.right - _logicalSize!.width * previousScale,
      current.top,
      _logicalSize!.width * previousScale,
      _logicalSize!.height * previousScale,
    );
    final bounds = scaledWindowBounds(
      base,
      initial ? 1 : scale,
      nextScale,
      work,
    );
    await windowManager.setMinimumSize(
      Size(
        math.min(396 * nextScale, work.width - 24),
        math.min(500 * nextScale, work.height - 24),
      ),
    );
    await windowManager.setBounds(bounds);
    scale = nextScale;
    _appliedSize = bounds.size;
    await updateShape();
  }

  Future<void> updateShape() => channel.invokeMethod<void>('shape', {
    'scale': scale,
    'notesVisible': notesVisible,
    'selected': selectedNote,
    'count': noteCount,
  });
}

class WindowSurfaceObserver extends NavigatorObserver {
  WindowSurfaceObserver(this.surface);
  final DesktopWindowSurface surface;
  void _update(Route<dynamic>? route) {
    surface.notesVisible = route?.isFirst ?? true;
    // Route changes do not resize the window; only the silhouette changes.
    surface.updateShape().catchError((Object error) {
      debugPrint('Window shape update failed: $error');
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _update(newRoute);
}
