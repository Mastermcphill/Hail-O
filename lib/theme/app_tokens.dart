import 'package:flutter/material.dart';

class HailoSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
  static const double section = 28;
}

class HailoRadii {
  static const BorderRadius sm = BorderRadius.all(Radius.circular(16));
  static const BorderRadius md = BorderRadius.all(Radius.circular(22));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(28));
  static const BorderRadius xl = BorderRadius.all(Radius.circular(36));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

class HailoDurations {
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 520);
}

@immutable
class HailoThemeTokens extends ThemeExtension<HailoThemeTokens> {
  const HailoThemeTokens({
    required this.canvas,
    required this.canvasStrong,
    required this.surfacePrimary,
    required this.surfaceSecondary,
    required this.surfaceMuted,
    required this.outlineSoft,
    required this.glow,
    required this.success,
    required this.warning,
    required this.pageGradient,
    required this.heroGradient,
    required this.panelGradient,
  });

  final Color canvas;
  final Color canvasStrong;
  final Color surfacePrimary;
  final Color surfaceSecondary;
  final Color surfaceMuted;
  final Color outlineSoft;
  final Color glow;
  final Color success;
  final Color warning;
  final Gradient pageGradient;
  final Gradient heroGradient;
  final Gradient panelGradient;

  static const HailoThemeTokens light = HailoThemeTokens(
    canvas: Color(0xFFF3F8FC),
    canvasStrong: Color(0xFFE8F0F9),
    surfacePrimary: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFFF8FBFF),
    surfaceMuted: Color(0xFFEFF4FA),
    outlineSoft: Color(0xFFD5E0EC),
    glow: Color(0xFF7BD7FF),
    success: Color(0xFF0F9F6E),
    warning: Color(0xFFB8740E),
    pageGradient: LinearGradient(
      colors: <Color>[Color(0xFFF4F9FD), Color(0xFFE8F2FB), Color(0xFFF9FCFF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    heroGradient: LinearGradient(
      colors: <Color>[Color(0xFF062748), Color(0xFF0B4F86), Color(0xFF1591E8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    panelGradient: LinearGradient(
      colors: <Color>[Color(0xF2FFFFFF), Color(0xEAF6FDFF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  @override
  HailoThemeTokens copyWith({
    Color? canvas,
    Color? canvasStrong,
    Color? surfacePrimary,
    Color? surfaceSecondary,
    Color? surfaceMuted,
    Color? outlineSoft,
    Color? glow,
    Color? success,
    Color? warning,
    Gradient? pageGradient,
    Gradient? heroGradient,
    Gradient? panelGradient,
  }) {
    return HailoThemeTokens(
      canvas: canvas ?? this.canvas,
      canvasStrong: canvasStrong ?? this.canvasStrong,
      surfacePrimary: surfacePrimary ?? this.surfacePrimary,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      outlineSoft: outlineSoft ?? this.outlineSoft,
      glow: glow ?? this.glow,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      pageGradient: pageGradient ?? this.pageGradient,
      heroGradient: heroGradient ?? this.heroGradient,
      panelGradient: panelGradient ?? this.panelGradient,
    );
  }

  @override
  HailoThemeTokens lerp(ThemeExtension<HailoThemeTokens>? other, double t) {
    if (other is! HailoThemeTokens) {
      return this;
    }
    return HailoThemeTokens(
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      canvasStrong:
          Color.lerp(canvasStrong, other.canvasStrong, t) ?? canvasStrong,
      surfacePrimary:
          Color.lerp(surfacePrimary, other.surfacePrimary, t) ?? surfacePrimary,
      surfaceSecondary:
          Color.lerp(surfaceSecondary, other.surfaceSecondary, t) ??
          surfaceSecondary,
      surfaceMuted:
          Color.lerp(surfaceMuted, other.surfaceMuted, t) ?? surfaceMuted,
      outlineSoft: Color.lerp(outlineSoft, other.outlineSoft, t) ?? outlineSoft,
      glow: Color.lerp(glow, other.glow, t) ?? glow,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      pageGradient:
          Gradient.lerp(pageGradient, other.pageGradient, t) ?? pageGradient,
      heroGradient:
          Gradient.lerp(heroGradient, other.heroGradient, t) ?? heroGradient,
      panelGradient:
          Gradient.lerp(panelGradient, other.panelGradient, t) ?? panelGradient,
    );
  }
}

extension HailoThemeContext on BuildContext {
  HailoThemeTokens get hailoTokens =>
      Theme.of(this).extension<HailoThemeTokens>() ?? HailoThemeTokens.light;
}
