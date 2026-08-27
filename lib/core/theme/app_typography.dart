import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Fraunces carries display/headline moments — screen titles, KYC status
/// headlines, the account-type choice — used sparingly (one or two lines
/// per screen), never for body copy. Inter carries everything else: body
/// text, labels, button text, form fields. JetBrains Mono is reserved for
/// numeric/data display — OTP digits, prices, order codes — exposed via
/// [AppTypography.mono] since Flutter's TextTheme has no dedicated slot
/// for it.
abstract class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: GoogleFonts.fraunces(
        fontSize: 40,
        height: 1.08,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: primary,
      ),
      headlineLarge: GoogleFonts.fraunces(
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: primary,
      ),
      headlineMedium: GoogleFonts.fraunces(
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        height: 1.55,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        height: 1.55,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      // CTA / primary button label.
      labelLarge: GoogleFonts.inter(
        fontSize: 16,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      // Ghost / secondary button + inline link label.
      labelMedium: GoogleFonts.inter(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w500,
        color: secondary,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 12,
        height: 1.5,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        color: secondary,
      ),
    );
  }

  static TextTheme get light =>
      textTheme(AppColors.inkText, AppColors.mutedText);

  /// Numeric/data face — OTP digit boxes, price displays, order/reference
  /// codes. Called directly rather than through a TextTheme slot.
  static TextStyle mono({
    required double fontSize,
    required Color color,
    FontWeight fontWeight = FontWeight.w600,
    double? letterSpacing,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: fontSize,
    color: color,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
  );
}
