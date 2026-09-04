import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Platform-adaptive loading spinner — [CupertinoActivityIndicator] on
/// iOS/macOS, [CircularProgressIndicator] everywhere else. Every raw,
/// indeterminate `CircularProgressIndicator()` in the app should go
/// through this instead, so a loading state reads as native on both
/// platforms rather than always showing Android's Material ring.
///
/// Not for a *determinate* progress ring (a real 0.0-1.0 `value`, e.g. the
/// KYC capture "hold steady" countdown) — `CupertinoActivityIndicator` has
/// no progress mode, so those stay a plain `CircularProgressIndicator`.
class AppSpinner extends StatelessWidget {
  const AppSpinner({super.key, this.size = 36, this.strokeWidth = 4, this.color});

  /// Diameter on Android (`CircularProgressIndicator` sizes to this via the
  /// wrapping `SizedBox`) and on iOS (converted to `radius: size / 2`).
  final double size;

  /// Android only — `CupertinoActivityIndicator` has no stroke-width
  /// concept, just its own fixed native dash style.
  final double strokeWidth;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return CupertinoActivityIndicator(radius: size / 2, color: color);
    }
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: strokeWidth, color: color),
    );
  }
}
