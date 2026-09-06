import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Fraunces carries display/headline moments — screen titles, KYC status
/// headlines, the account-type choice — used sparingly (one or two lines
/// per screen), never for body copy. Manrope carries everything else: body
/// text, labels, button text, form fields — at a heavier SemiBold/Bold
/// weight specifically for button and category-chip labels ([labelLarge]/
/// [labelMedium]), since those need real visual weight where the rest of
/// Manrope's range stays regular. JetBrains Mono is reserved for
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
      titleLarge: GoogleFonts.manrope(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: GoogleFonts.manrope(
        fontSize: 16,
        height: 1.55,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 14,
        height: 1.55,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      // CTA / primary button label + the active category-chip label —
      // Bold, not just SemiBold: at Manrope's own metrics, w600 alone read
      // noticeably lighter here than Inter's old w600 did, so button/chip
      // text needs the full step up to carry the same visual weight.
      labelLarge: GoogleFonts.manrope(
        fontSize: 16,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      // Ghost / secondary button + inline link label + inactive
      // category-chip labels — SemiBold, one step up from the old Inter
      // w500, for the same "give buttons/chips real weight" reason above.
      labelMedium: GoogleFonts.manrope(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: secondary,
      ),
      labelSmall: GoogleFonts.manrope(
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
