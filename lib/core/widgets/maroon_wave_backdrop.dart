import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Task 57: fixes Task 56's broken implementation. That version
/// absolutely-positioned this shape inside a [Stack] with a manually
/// guessed `topOffset` (a fraction of screen height) — real content
/// (the keypad, footer links) could end up rendered underneath/behind
/// it, and on any device where the guess didn't match actual content
/// height, it either overlapped real widgets or left cream space
/// showing anyway. A [Stack] with fixed offsets can never structurally
/// guarantee "never overlaps, always fills the rest" — only normal
/// layout flow can.
///
/// [MaroonWaveSection] is that fix: a normal-flow, purely decorative
/// widget meant to be the **last, `Expanded` child of a [Column]** whose
/// earlier children are the screen's real primary content (laid out at
/// natural size). Being `Expanded` — not absolutely positioned — it is
/// *structurally* incapable of overlapping the content above it, and it
/// always occupies exactly whatever space is actually left on the
/// current device, never a fixed guess.
///
/// Renders a maroon wave (a shallow curve at its own top edge, solid
/// below) plus low-opacity secondary shapes for depth (a soft circular
/// blob, a diagonal capsule highlight).
///
/// For a screen with secondary links that belong *inside* the maroon
/// area (e.g. Welcome Back's "Forgot passcode?" / "Create an account"),
/// pair this with [MaroonFooterBar] as the Column's next (non-flex)
/// child, right after this one — deliberately real content, not nested
/// inside this widget's own [Stack]: a [Stack] with only [Positioned]
/// children reports zero intrinsic height regardless of what's inside
/// it, which silently defeats the `ConstrainedBox` + `IntrinsicHeight`
/// "sticky footer" pattern every call site uses to reserve real
/// content its actual minimum space. [MaroonFooterBar] is a plain
/// (non-`Stack`) widget specifically so its intrinsic height is
/// unambiguous, and its flat maroon fill continues seamlessly from this
/// section's own solid color with no visible seam.
///
/// Usage:
/// ```dart
/// Column(
///   children: [
///     // primary content, natural size — NOT Expanded
///     Padding(padding: ..., child: Column(children: [...])),
///     const Expanded(child: MaroonWaveSection()),
///     MaroonFooterBar(child: footerLinks), // omit if there's no footer
///   ],
/// )
/// ```
class MaroonWaveSection extends StatelessWidget {
  const MaroonWaveSection({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipPath(
        clipper: const _WaveClipper(),
        child: ColoredBox(
          color: AppColors.primaryMaroon,
          child: Stack(children: [_SecondaryBlob(), _DiagonalHighlight()]),
        ),
      ),
    );
  }
}

/// Task 58: corrects Task 56/57's blanket use of [MaroonWaveSection] (a
/// space-filling `Expanded`/`SliverFillRemaining` block) on task-focused
/// screens with no secondary content to justify that much real estate —
/// e.g. OTP entry, email verification. Those screens get this instead: the
/// same wave motif at a small, fixed, modest height, placed as an ordinary
/// (non-flex) last child after the real content rather than a widget that
/// claims all remaining vertical space. The primary task content stays the
/// dominant thing on screen; this just softens the bottom edge.
class MaroonAccentStrip extends StatelessWidget {
  const MaroonAccentStrip({super.key, this.height = 88});

  final double height;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ClipPath(
          clipper: const _WaveClipper(),
          child: const ColoredBox(color: AppColors.primaryMaroon),
        ),
      ),
    );
  }
}

/// See [MaroonWaveSection]'s doc comment — a plain, non-`Stack` maroon
/// bar for real content (secondary links) that belongs directly below
/// it, safe-area aware. Its own natural size is unambiguous to Flutter's
/// normal intrinsic-height algorithm, unlike nesting the same content
/// inside [MaroonWaveSection]'s decorative `Stack`.
class MaroonFooterBar extends StatelessWidget {
  const MaroonFooterBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.primaryMaroon,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Soft, low-opacity circular blob for texture — deliberately positioned
/// well below the wave's peak so it never needs its own clip.
class _SecondaryBlob extends StatelessWidget {
  const _SecondaryBlob();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: -50,
      top: 70,
      child: Container(
        width: 190,
        height: 190,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.onMaroon.withValues(alpha: 0.06),
        ),
      ),
    );
  }
}

/// A lighter diagonal capsule/pill highlight for depth.
class _DiagonalHighlight extends StatelessWidget {
  const _DiagonalHighlight();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: -40,
      bottom: 50,
      child: Transform.rotate(
        angle: -0.5,
        child: Container(
          width: 230,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: AppColors.onMaroon.withValues(alpha: 0.05),
          ),
        ),
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  const _WaveClipper();

  // Fixed pixel amplitude (not a fraction of size.height) — this section's
  // actual height is whatever's left on the device (an Expanded child), so
  // a height-relative curve would look wildly different from one device
  // to the next. A constant curve reads consistently everywhere, and
  // safely degrades to "mostly just the curve" on the rare device where
  // almost no space is left.
  static const _lowPoint = 40.0;
  static const _peakLift = 40.0;

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, _lowPoint)
      ..quadraticBezierTo(
        size.width * 0.5,
        _lowPoint - _peakLift * 2,
        size.width,
        _lowPoint,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
