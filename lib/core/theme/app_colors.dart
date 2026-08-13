import 'package:flutter/material.dart';

/// RUN-It's palette is built around one warm amber brand hue carried
/// consistently across both modes. Light mode is a deliberate cream/paper
/// palette (not an inverted dark theme) and dark mode avoids true black,
/// both to read as considered rather than a default Material swap.
abstract class AppColors {
  AppColors._();

  // Brand hue — identical across themes, this is what makes the two modes
  // feel like the same product rather than two different apps.
  static const amber = Color(0xFFF0A94E);
  static const amberDeep = Color(0xFFD9862B);
  static const amberDeeper = Color(0xFFB8651C);

  static const success = Color(0xFF3FA372);
  static const successDark = Color(0xFF4FC08A);
  static const error = Color(0xFFE2604F);
  static const errorDark = Color(0xFFF07A68);

  // ---- Dark (matches the supplied designs) ----
  static const darkBg = Color(0xFF0F0D0C);
  static const darkSurface = Color(0xFF1A1714);
  static const darkSurfaceHigh = Color(0xFF221D18);
  static const darkBorder = Color(0xFF2E2822);
  static const darkTextPrimary = Color(0xFFF7F4EF);
  static const darkTextSecondary = Color(0xFFA39C92);
  static const darkTextTertiary = Color(0xFF6C665E);
  static const darkOnAmber = Color(0xFF1B1309);

  // ---- Light (new — warm ivory, not white) ----
  static const lightBg = Color(0xFFFAF6EF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceSunken = Color(0xFFF1EAE0);
  static const lightBorder = Color(0xFFE8DFD1);
  static const lightTextPrimary = Color(0xFF1C1712);
  static const lightTextSecondary = Color(0xFF6F675C);
  static const lightTextTertiary = Color(0xFFA79D8F);
  static const lightOnAmber = Color(0xFF1B1309);

  // Warm-tinted shadow used instead of flat black/gray — cheap-looking
  // drop shadows are one of the fastest ways a light UI reads as generic.
  static const lightShadow = Color(0x1AD9862B);
  static const darkShadow = Color(0x33000000);
}
