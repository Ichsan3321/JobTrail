import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF5B5BF0);
  static const primaryDark = Color(0xFF4343C9);
  static const primaryLight = Color(0xFFEEEEFF);
  static const mint = Color(0xFF2DD4A7);
  static const mintDark = Color(0xFF10A982);
  static const peach = Color(0xFFFFB37A);
  static const peachTint = Color(0xFFFFF4EC);
  static const error = Color(0xFFB91C1C);
  static const errorTint = Color(0xFFFFF1F2);
  static const navy = Color(0xFF1E2A4A);
  static const gray = Color(0xFF5A6380);
  static const background = Color(0xFFF7F7FC);
  static const surfaceLow = Color(0xFFFAFAFF);
  static const surfaceHigh = Color(0xFFEEEEF6);
  static const border = Color(0xFFE4E4F0);
  static const white = Color(0xFFFFFFFF);
}

abstract final class AppSpacing {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class AppRadius {
  static const card = 20.0;
  static const button = 14.0;
  static const chip = 999.0;
}

abstract final class AppTypography {
  static const headingFamily = 'Poppins';
  static const bodyFamily = 'Plus Jakarta Sans';
  static const heading = TextStyle(
    fontFamily: headingFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.navy,
  );
  static const section = TextStyle(
    fontFamily: headingFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.navy,
  );
  static const body = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 14,
    color: AppColors.navy,
  );
  static const label = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.gray,
  );
}
