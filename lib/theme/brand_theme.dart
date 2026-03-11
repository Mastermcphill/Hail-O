import 'package:flutter/material.dart';

import 'app_tokens.dart';

class BrandTheme {
  static ThemeData light() {
    const primary = Color(0xFF0B3C5D);
    const electricBlue = Color(0xFF1F7AE0);
    const baseText = Color(0xFF10233A);
    const background = Color(0xFFF5F8FC);
    const surface = Color(0xFFFFFFFF);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: electricBlue,
      brightness: Brightness.light,
      primary: electricBlue,
      secondary: const Color(0xFF5DAEFF),
      tertiary: const Color(0xFF0B3C5D),
      surface: surface,
      error: const Color(0xFFC53754),
      onPrimary: Colors.white,
      onSurface: baseText,
      onError: Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Inter',
    );

    final textTheme = base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.6,
        color: baseText,
      ),
      displayMedium: base.textTheme.displayMedium?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.3,
        color: baseText,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        color: baseText,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: baseText,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: baseText,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
        color: baseText,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: baseText,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: baseText,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.55,
        color: baseText,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 15,
        height: 1.5,
        color: baseText,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 13,
        height: 1.45,
        color: const Color(0xFF586E86),
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      extensions: const <ThemeExtension<dynamic>>[HailoThemeTokens.light],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: primary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: HailoSpacing.lg,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: HailoRadii.md),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFD8E3EE),
        space: 1,
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(56),
          backgroundColor: electricBlue,
          foregroundColor: Colors.white,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: HailoRadii.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: HailoSpacing.lg,
            vertical: HailoSpacing.md,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: primary,
          textStyle: textTheme.labelLarge,
          side: const BorderSide(color: Color(0xFFD8E2EC)),
          shape: RoundedRectangleBorder(borderRadius: HailoRadii.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: HailoSpacing.lg,
            vertical: HailoSpacing.md,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: electricBlue,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: HailoRadii.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: HailoSpacing.md,
            vertical: HailoSpacing.sm,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.94),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF6D8298),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF5E748A),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HailoSpacing.md,
          vertical: HailoSpacing.md,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: HailoRadii.sm,
          borderSide: const BorderSide(color: Color(0xFFD8E2EC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: HailoRadii.sm,
          borderSide: const BorderSide(color: electricBlue, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: HailoRadii.sm,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: HailoRadii.sm,
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: HailoRadii.sm,
          borderSide: const BorderSide(color: Color(0xFFD8E2EC)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.96),
        indicatorColor: electricBlue.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (states) => textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? electricBlue
                : const Color(0xFF6C8098),
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? electricBlue
                : const Color(0xFF6C8098),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: primary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: HailoRadii.sm),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: electricBlue,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: HailoRadii.pill),
        side: const BorderSide(color: Color(0xFFD8E2EC)),
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        selectedColor: electricBlue.withValues(alpha: 0.12),
        labelStyle: textTheme.labelMedium,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
