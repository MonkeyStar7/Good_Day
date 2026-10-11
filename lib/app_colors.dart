import 'package:flutter/material.dart';

/// Application chrome follows the accent; user-selected goal colors stay intact.
class AppColors {
  const AppColors(this.accent);
  final Color accent;

  Color get paper => Color.lerp(Colors.white, accent, 0.09)!;
  Color get panel => Color.lerp(Colors.white, accent, 0.16)!;
  Color get line => Color.lerp(Colors.white, accent, 0.29)!;
  Color get ink => Color.lerp(const Color(0xFF202020), accent, 0.52)!;
  Color get muted => Color.lerp(const Color(0xFF787878), accent, 0.58)!;
  Color get hover => accent.withValues(alpha: 0.09);
  Color note(int index) =>
      Color.lerp(Colors.white, accent, 0.20 + index * 0.035)!;
}

extension GoodDayColors on BuildContext {
  AppColors get appColors => AppColors(Theme.of(this).colorScheme.primary);
}
