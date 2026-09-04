import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// The app's one `ThemeData` — cream, used by every screen. There is no
/// dark variant and no `ThemeMode` switch; `main.dart` applies this
/// unconditionally.
abstract class AppTheme {
  AppTheme._();

  static ThemeData get light {
    const scheme = ColorScheme.light(
      brightness: Brightness.light,
      primary: AppColors.primaryMaroon,
      onPrimary: AppColors.onMaroon,
      secondary: AppColors.accentRoseDeep,
      onSecondary: AppColors.primaryMaroonDeep,
      surface: AppColors.surfaceCard,
      onSurface: AppColors.inkText,
      error: AppColors.error,
      onError: Colors.white,
      outline: AppColors.borderSubtle,
    );

    return _base(scheme, AppTypography.light, AppColors.backgroundCream);
  }

  static ThemeData _base(
    ColorScheme scheme,
    TextTheme textTheme,
    Color scaffoldBg,
  ) {
    const hairline = AppColors.borderSubtle;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: scheme.outline,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: textTheme.titleLarge,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryMaroon,
          foregroundColor: AppColors.onMaroon,
          disabledBackgroundColor: scheme.outline,
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryMaroon,
          textStyle: textTheme.labelMedium,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: AppSpacing.ml,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: hairline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: hairline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.primaryMaroon, width: 1.5),
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(color: AppColors.mutedText),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // iOS keeps the platform default (Task 23): overriding it with
          // the custom builder below silently drops
          // CupertinoPageTransitionsBuilder's edge-swipe-to-go-back
          // gesture, since GoRouter's routes resolve their transition
          // through this theme rather than the route class itself —
          // there's no separate opt-in for the gesture alone.
          TargetPlatform.android: _RouteFadeSlideTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Coordinated slide + fade between screens on Android — replaces the
/// default platform push transition there (auth steps included, since
/// they use the same `GoRouter`/`Navigator` push mechanism). iOS uses
/// `CupertinoPageTransitionsBuilder` instead (Task 23) to keep its native
/// swipe-back gesture; Android has no equivalent gesture tied to this
/// builder, so the custom transition stays without that tradeoff.
class _RouteFadeSlideTransitionsBuilder extends PageTransitionsBuilder {
  const _RouteFadeSlideTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
