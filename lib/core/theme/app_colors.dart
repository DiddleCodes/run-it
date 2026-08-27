import 'package:flutter/material.dart';

/// RUN-It's design system. One base surface — cream — used app-wide by
/// every screen, student and runner alike. There is no dark theme.
///
/// These values are the single canonical source for the app's palette —
/// screens should never hardcode a hex literal that duplicates one of
/// these (the runner-flow screens used to each define their own local
/// `_kGold`, for instance; that's now [gold] below instead).
abstract class AppColors {
  AppColors._();

  // ---- Primary — burgundy ----
  static const primaryMaroon = Color(0xFF7A1636);
  static const primaryMaroonDeep = Color(0xFF5A0E25);
  static const primaryMaroonGlow = Color(0x597A1636); // primaryMaroon @ 35%

  // ---- Soft blush — icon badges, secondary tint, celebration surfaces ----
  static const accentRose = Color(0xFFF8E8E8);
  static const accentRoseDeep = Color(0xFFE3B6C1);

  // Text/icon color rendered on top of a maroon-filled surface (e.g. a CTA
  // button label) — a warm off-white reads cleanly on burgundy.
  static const onMaroon = Color(0xFFFBF4E9);

  // ---- Gold — runner-facing accent (online status, ratings, stat
  // emphasis) ----
  static const gold = Color(0xFFD99A18);
  static const goldTint = Color(0xFFFBEFD9);

  // ---- Accent forest — restaurant role (role-select screen) ----
  // A cool, deep forest green — deliberately breaks from the warm
  // maroon/gold pair used by the other two roles so a three-way choice
  // reads as visually distinct at a glance, not just relabeled.
  static const accentForest = Color(0xFF2F5D3A);
  static const accentForestDeep = Color(0xFF1D3B26);

  // ---- Status colors ----
  static const success = Color(0xFF2E7D32);
  static const successBackground = Color(0xFFE3F3E1);
  static const warning = Color(0xFFB07A2E);
  static const error = Color(0xFFB23A3A);

  // ---- Cream (the app's one base surface) ----
  static const backgroundCream = Color(0xFFFBF4E9);
  static const surfaceCard = Color(0xFFFFFFFF);
  static const borderSubtle = Color(0xFFEADDD2);
  static const inkText = Color(0xFF24151A);
  static const mutedText = Color(0xFF75656A);

  // ---- Scanner — the Scan screen's viewfinder only ----
  static const scannerGreen = Color(0xFF72D84F);
  static const scannerBackground = Color(0xFF080708);

  // Warm-tinted shadow used instead of flat black/gray.
  static const maroonShadow = Color(0x1A7A1636);
}
