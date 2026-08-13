import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_motion.dart';

/// A pill CTA with a tactile press response (scale + haptic) instead of
/// the flat, static Material button most delivery apps ship with.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

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
        duration: AppMotion.fast,
        curve: AppMotion.emphasized,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.5,
          duration: AppMotion.fast,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                colors: [Color(0xFFF4B863), Color(0xFFDB8A2E)],
              ),
            ),
            child: widget.loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Color(0xFF1B1309),
                    ),
                  )
                : Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF1B1309),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
