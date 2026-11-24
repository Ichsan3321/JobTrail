import 'package:flutter/material.dart';

import '../constants/app_tokens.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      fontFamily: AppTypography.bodyFamily,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.white,
        primaryContainer: AppColors.primaryLight,
        onPrimaryContainer: AppColors.primaryDark,
        secondary: AppColors.mint,
        onSecondary: AppColors.navy,
        tertiary: AppColors.peach,
        onTertiary: AppColors.navy,
        error: AppColors.error,
        onError: AppColors.white,
        errorContainer: AppColors.errorTint,
        onErrorContainer: AppColors.error,
        surface: AppColors.white,
        onSurface: AppColors.navy,
        surfaceContainerLowest: AppColors.white,
        surfaceContainerLow: AppColors.surfaceLow,
        surfaceContainer: AppColors.background,
        surfaceContainerHigh: AppColors.surfaceHigh,
        surfaceContainerHighest: AppColors.border,
        outline: AppColors.border,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: AppTypography.heading.copyWith(fontSize: 32),
        headlineMedium: AppTypography.heading,
        headlineSmall: AppTypography.section,
        titleLarge: AppTypography.section,
        bodyLarge: AppTypography.body.copyWith(fontSize: 16),
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.label.copyWith(fontWeight: FontWeight.w400),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.navy,
        titleTextStyle: AppTypography.section,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.primaryLight,
        labelTextStyle: WidgetStatePropertyAll(AppTypography.label),
      ),
    );
  }
}
