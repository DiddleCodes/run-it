import 'package:flutter/material.dart';
import 'app_colors.dart';

/// GeneralSans carries display/headline moments, Satoshi carries body and
/// UI copy. Both are geometric-but-warm, which is what keeps the type feel
/// distinct from the default-system look most template apps ship with.
abstract class AppTypography {
  AppTypography._();

  static const _display = 'GeneralSans';
  static const _body = 'Satoshi';

  static TextTheme textTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: _display,
        fontSize: 36,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: primary,
      ),
      headlineLarge: TextStyle(
        fontFamily: _display,
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: primary,
      ),
      headlineMedium: TextStyle(
        fontFamily: _display,
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontFamily: _display,
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: TextStyle(
        fontFamily: _body,
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodyMedium: TextStyle(
        fontFamily: _body,
        fontSize: 14,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      labelLarge: TextStyle(
        fontFamily: _body,
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: primary,
      ),
      labelSmall: TextStyle(
        fontFamily: _body,
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: secondary,
      ),
    );
  }

  static TextTheme get dark =>
      textTheme(AppColors.darkTextPrimary, AppColors.darkTextSecondary);

  static TextTheme get light =>
      textTheme(AppColors.lightTextPrimary, AppColors.lightTextSecondary);
}
