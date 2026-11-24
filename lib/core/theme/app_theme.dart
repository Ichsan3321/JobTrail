import 'package:flutter/material.dart';

import '../constants/app_tokens.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      fontFamily: AppTypography.bodyFamily,
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
    final colors = base.colorScheme;
    final text = base.textTheme;
    return base.copyWith(
      scaffoldBackgroundColor: colors.surfaceContainer,
      textTheme: text.copyWith(
        displayLarge: text.displayLarge?.copyWith(
          fontFamily: AppTypography.headingFamily,
        ),
        displayMedium: text.displayMedium?.copyWith(
          fontFamily: AppTypography.headingFamily,
        ),
        displaySmall: text.displaySmall?.copyWith(
          fontFamily: AppTypography.headingFamily,
        ),
        headlineLarge: AppTypography.heading.copyWith(fontSize: 32),
        headlineMedium: AppTypography.heading,
        headlineSmall: AppTypography.section,
        titleLarge: AppTypography.section,
        bodyLarge: AppTypography.body.copyWith(fontSize: 16),
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.caption,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surfaceContainer,
        foregroundColor: colors.onSurface,
        titleTextStyle: AppTypography.section,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainerLowest,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: colors.outline),
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
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: colors.outline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        labelTextStyle: const WidgetStatePropertyAll(AppTypography.label),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        modalBackgroundColor: colors.surface,
      ),
    );
  }
}
