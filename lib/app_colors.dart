import 'package:flutter/material.dart';

const cloudYellowAccent = Color(0xFF8D742B);

/// Application chrome follows the accent; user-selected goal colors stay intact.
class AppColors {
  const AppColors(this.accent);
  final Color accent;
  bool get _cloudYellow => accent == cloudYellowAccent;

  Color get paper => _cloudYellow
      ? const Color(0xFFFFFDF5)
      : Color.lerp(Colors.white, accent, 0.09)!;
  Color get panel => _cloudYellow
      ? const Color(0xFFFFF8E6)
      : Color.lerp(Colors.white, accent, 0.16)!;
  Color get line => _cloudYellow
      ? const Color(0xFFEAE1C9)
      : Color.lerp(Colors.white, accent, 0.29)!;
  Color get ink => _cloudYellow
      ? const Color(0xFF3F3A2D)
      : Color.lerp(const Color(0xFF202020), accent, 0.52)!;
  Color get muted => _cloudYellow
      ? const Color(0xFF81765D)
      : Color.lerp(const Color(0xFF787878), accent, 0.58)!;
  Color get hover => accent.withValues(alpha: 0.09);
  Color note(int index) => _cloudYellow
      ? Color.lerp(
          const Color(0xFFFFFAE9),
          const Color(0xFFF1E2B7),
          0.15 + index * 0.13,
        )!
      : Color.lerp(Colors.white, accent, 0.20 + index * 0.035)!;
}

extension GoodDayColors on BuildContext {
  AppColors get appColors => AppColors(Theme.of(this).colorScheme.primary);
}
