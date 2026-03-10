import 'package:flutter/material.dart';

import 'app_tokens.dart';

class BrandTheme {
  static ThemeData light() {
    const seed = Color(0xFF0A7CFF);
    const baseText = Color(0xFF10233A);
    const surface = Color(0xFFFFFFFF);
    const background = Color(0xFFF3F8FC);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      primary: seed,
      secondary: const Color(0xFF18A8FF),
      tertiary: const Color(0xFF00A4C7),
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
    );

    final textTheme = base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.4,
        color: baseText,
      ),
      displayMedium: base.textTheme.displayMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        color: baseText,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        color: baseText,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: baseText,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: baseText,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: baseText,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: baseText,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: baseText,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        height: 1.5,
        color: baseText,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        height: 1.5,
        color: baseText,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        height: 1.45,
        color: const Color(0xFF566C86),
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
        foregroundColor: baseText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
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
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
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
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.18)),
          shape: RoundedRectangleBorder(borderRadius: HailoRadii.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: HailoSpacing.lg,
            vertical: HailoSpacing.md,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
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
        fillColor: Colors.white.withValues(alpha: 0.88),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF6B8098),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF5C7590),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HailoSpacing.md,
          vertical: HailoSpacing.md,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: HailoRadii.sm,
          borderSide: const BorderSide(color: Color(0xFFD6E1EC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: HailoRadii.sm,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
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
          borderSide: const BorderSide(color: Color(0xFFD6E1EC)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.94),
        indicatorColor: colorScheme.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (states) => textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : const Color(0xFF6C8098),
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : const Color(0xFF6C8098),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0B2441),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: HailoRadii.sm),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: colorScheme.primary.withValues(alpha: 0.12),
      ),
      chipTheme: base.chipTheme.copyWith(
        padding: const EdgeInsets.symmetric(
          horizontal: HailoSpacing.sm,
          vertical: HailoSpacing.xs,
        ),
        backgroundColor: Colors.white,
        selectedColor: colorScheme.primary.withValues(alpha: 0.10),
        side: const BorderSide(color: Color(0xFFD6E1EC)),
        shape: RoundedRectangleBorder(borderRadius: HailoRadii.pill),
        labelStyle: textTheme.labelMedium,
      ),
    );
  }
}
