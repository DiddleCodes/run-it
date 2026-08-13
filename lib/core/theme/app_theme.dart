import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

abstract class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final scheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: AppColors.amber,
      onPrimary: AppColors.darkOnAmber,
      secondary: AppColors.amberDeep,
      onSecondary: AppColors.darkOnAmber,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      error: AppColors.errorDark,
      onError: AppColors.darkOnAmber,
      outline: AppColors.darkBorder,
    );

    return _base(scheme, AppTypography.dark, AppColors.darkBg);
  }

  static ThemeData get light {
    final scheme = const ColorScheme.light(
      brightness: Brightness.light,
      primary: AppColors.amberDeeper,
      onPrimary: Colors.white,
      secondary: AppColors.amberDeep,
      onSecondary: Colors.white,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightTextPrimary,
      error: AppColors.error,
      onError: Colors.white,
      outline: AppColors.lightBorder,
    );

    return _base(scheme, AppTypography.light, AppColors.lightBg);
  }

  static ThemeData _base(
    ColorScheme scheme,
    TextTheme textTheme,
    Color scaffoldBg,
  ) {
    final isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      fontFamily: 'Satoshi',
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: scheme.outline,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: isDark
              ? AppColors.darkOnAmber
              : AppColors.lightOnAmber,
          disabledBackgroundColor: scheme.outline,
          minimumSize: const Size.fromHeight(56),
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface.withValues(alpha: 0.7),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AppColors.darkSurfaceHigh
            : AppColors.lightSurfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.amber, width: 1.5),
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: isDark
              ? AppColors.darkTextTertiary
              : AppColors.lightTextTertiary,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
