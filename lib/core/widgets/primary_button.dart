import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Task 40: [PrimaryButtonStyle.outlined] exists for the one real recurring
/// case where the default maroon-gradient fill doesn't work — a button
/// sitting on a surface that's already maroon (the Wallet balance card),
/// where a second filled maroon button would have no contrast against its
/// own background. It keeps the same press-scale/haptic identity as
/// [PrimaryButtonStyle.filled], just without the gradient/shadow.
enum PrimaryButtonStyle { filled, outlined }

/// A rounded-rect CTA with a tactile press response (scale + haptic) and a
/// maroon glow lift, instead of the flat, static Material button most
/// delivery apps ship with.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.style = PrimaryButtonStyle.filled,
    this.color,
    this.foregroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  /// Optional trailing icon (e.g. an arrow on the onboarding CTA).
  final IconData? icon;

  final PrimaryButtonStyle style;

  /// Overrides the default maroon gradient fill (filled) or border/text tint
  /// (outlined) — for the rare screen that genuinely needs a different
  /// color to read against its own background (e.g. the Wallet balance
  /// card's gold "Add Funds"), not for arbitrary re-theming.
  final Color? color;
  final Color? foregroundColor;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    const disabledBg = AppColors.borderSubtle;
    const disabledText = AppColors.mutedText;
    final outlined = widget.style == PrimaryButtonStyle.outlined;
    final fg = widget.foregroundColor ?? AppColors.onMaroon;
    final contentColor = enabled ? fg : disabledText;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              widget.onPressed!();
            }
          : null,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            gradient: enabled && !outlined
                ? LinearGradient(
                    colors: widget.color != null
                        ? [widget.color!, widget.color!]
                        : const [
                            AppColors.primaryMaroon,
                            AppColors.primaryMaroonDeep,
                          ],
                  )
                : null,
            color: !enabled && !outlined ? disabledBg : null,
            border: outlined
                ? Border.all(color: enabled ? fg.withValues(alpha: .5) : disabledText)
                : null,
            boxShadow: enabled && !outlined && widget.color == null
                ? [
                    const BoxShadow(
                      color: AppColors.primaryMaroonGlow,
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ]
                : [],
          ),
          child: widget.loading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: contentColor,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Flexible, not a bare Text: several call sites build
                    // this label dynamically (basket subtotal, order
                    // total) and can run long — at larger Dynamic Type
                    // scale that combined with a fixed-width button can
                    // need more horizontal room than's available. Flexible
                    // lets it shrink to a single ellipsized line instead
                    // of overflowing the row.
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: contentColor),
                      ),
                    ),
                    if (widget.icon != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Icon(widget.icon, size: 18, color: contentColor),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
