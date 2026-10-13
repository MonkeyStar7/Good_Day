import 'package:flutter/material.dart';

const cloudYellowAccent = Color(0xFF8D742B);
const whiteGlassAccent = Color(0xFF54606D);

class AppGlassStyle extends ThemeExtension<AppGlassStyle> {
  const AppGlassStyle(this.transparency);
  final double transparency;
  @override
  AppGlassStyle copyWith({double? transparency}) =>
      AppGlassStyle(transparency ?? this.transparency);
  @override
  AppGlassStyle lerp(covariant AppGlassStyle? other, double t) => AppGlassStyle(
    transparency + ((other?.transparency ?? transparency) - transparency) * t,
  );
}

/// Application chrome follows the accent; user-selected goal colors stay intact.
class AppColors {
  const AppColors(this.accent, {this.transparency = 0});
  final Color accent;
  final double transparency;
  bool get _cloudYellow => accent == cloudYellowAccent;
  bool get _white => accent == whiteGlassAccent;
  Color _glass(Color color) => color.withValues(alpha: 1 - transparency);

  Color get paper => _glass(
    _white
        ? Colors.white
        : _cloudYellow
        ? const Color(0xFFFFFDF5)
        : Color.lerp(Colors.white, accent, 0.09)!,
  );
  Color get panel => _glass(
    _white
        ? const Color(0xFFF3F5F7)
        : _cloudYellow
        ? const Color(0xFFFFF8E6)
        : Color.lerp(Colors.white, accent, 0.16)!,
  );
  Color get line => _white
      ? const Color(0xFFD8DDE2)
      : _cloudYellow
      ? const Color(0xFFEAE1C9)
      : Color.lerp(Colors.white, accent, 0.29)!;
  Color get ink => _white
      ? const Color(0xFF24282D)
      : _cloudYellow
      ? const Color(0xFF3F3A2D)
      : Color.lerp(const Color(0xFF24282C), accent, 0.16)!;
  Color get muted => _white
      ? const Color(0xFF69727C)
      : _cloudYellow
      ? const Color(0xFF81765D)
      : Color.lerp(const Color(0xFF59616A), accent, 0.18)!;
  Color get hover => accent.withValues(alpha: 0.09);
  Color get controlFill =>
      paper.withValues(alpha: 0.12 + 0.10 * (1 - transparency));
  Color get controlLine => muted.withValues(alpha: 0.22);
  Color note(int index) => _glass(
    _white
        ? const Color(0xFFF5F7FA)
        : _cloudYellow
        ? Color.lerp(
            const Color(0xFFFFFAE9),
            const Color(0xFFF1E2B7),
            0.15 + index * 0.13,
          )!
        : Color.lerp(Colors.white, accent, 0.20 + index * 0.035)!,
  );
}

extension GoodDayColors on BuildContext {
  AppColors get appColors => AppColors(
    Theme.of(this).colorScheme.primary,
    transparency: Theme.of(this).extension<AppGlassStyle>()?.transparency ?? 0,
  );
}
