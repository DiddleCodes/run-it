import 'package:flutter/animation.dart';

/// Shared motion vocabulary. Everything animated in the app should pull
/// from here rather than inlining durations/curves, so the product moves
/// as one coherent system instead of a pile of one-off tweaks.
abstract class AppMotion {
  AppMotion._();

  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 450);
  static const slower = Duration(milliseconds: 700);

  /// "Expo out" — decisive start, soft landing. Used for nearly all
  /// entrance/transition motion; reads as considerably more premium than
  /// the default easeInOut most apps ship with.
  static const emphasized = Cubic(0.16, 1, 0.3, 1);

  /// Slight overshoot for confirmation/success moments only — used
  /// sparingly so it stays special.
  static const bouncy = Cubic(0.34, 1.56, 0.64, 1);
}
