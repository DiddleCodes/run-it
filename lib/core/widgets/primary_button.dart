import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

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
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  /// Optional trailing icon (e.g. an arrow on the onboarding CTA).
  final IconData? icon;

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
            borderRadius: BorderRadius.circular(16),
            gradient: enabled
                ? const LinearGradient(
                    colors: [
                      AppColors.primaryMaroon,
                      AppColors.primaryMaroonDeep,
                    ],
                  )
                : null,
            color: enabled ? null : disabledBg,
            boxShadow: enabled
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
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.onMaroon,
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
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: enabled ? AppColors.onMaroon : disabledText,
                        ),
                      ),
                    ),
                    if (widget.icon != null) ...[
                      const SizedBox(width: 8),
                      Icon(
                        widget.icon,
                        size: 18,
                        color: enabled ? AppColors.onMaroon : disabledText,
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
