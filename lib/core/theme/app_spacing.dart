import 'package:flutter/material.dart';

/// Spacing, radius, and elevation scale — every screen should pull from
/// here rather than inlining one-off numbers, so density and roundedness
/// read as one consistent system app-wide.
abstract class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 14.0;
  // Task 39: promoted from a raw 18 hardcoded 36+ times app-wide — real
  // enough (and far enough from both neighbors) to earn its own step
  // rather than being forced into md or lg.
  static const ml = 18.0;
  static const lg = 22.0;
  static const xl = 28.0;
  static const xxl = 40.0;
}

abstract class AppRadius {
  AppRadius._();

  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const pill = 999.0;

  // Task 39: the shared AppTextField's own corner radius (19), hand-
  // replicated across several other input-styled widgets before this
  // constant existed — promoted rather than rounded into sm/md/lg, since
  // rounding would be a real (if small) visual change to the actual
  // canonical text field, not just a referencing fix.
  static const input = 19.0;
}

/// Layered elevation shadows — a single flat drop-shadow is one of the
/// fastest ways a UI reads as generic. Each interactive-card shadow here
/// is two stacked layers (a tight, low-opacity "contact" shadow plus a
/// soft, wide "ambient" one) rather than one BoxShadow. Maroon-black
/// (runner) screens stay flat (hairline borders do the separating there);
/// cream screens lean on these for lift. Purely informational surfaces (list
/// rows, empty states) should use neither — reserve elevation for things
/// that are actually interactive/tappable.
abstract class AppElevation {
  AppElevation._();

  static List<BoxShadow> card(bool isDark) => isDark
      ? const []
      : const [
          BoxShadow(color: Color(0x0F7A1636), blurRadius: 3, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x147A1636), blurRadius: 20, offset: Offset(0, 10)),
        ];

  static List<BoxShadow> raised(bool isDark) => isDark
      ? [
          const BoxShadow(color: Color(0x30000000), blurRadius: 24, offset: Offset(0, 12)),
        ]
      : const [
          BoxShadow(color: Color(0x1A7A1636), blurRadius: 6, offset: Offset(0, 2)),
          BoxShadow(color: Color(0x1F7A1636), blurRadius: 32, offset: Offset(0, 16)),
        ];
}
