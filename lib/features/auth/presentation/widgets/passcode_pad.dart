import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

const passcodeLength = 6;

/// Six dot indicators that fill in as digits are entered — the iOS
/// system-passcode convention, skinned in maroon/cream. [shake] plays a
/// horizontal shake (driven by the caller, e.g. on a confirm mismatch).
class PasscodeDots extends StatelessWidget {
  const PasscodeDots({super.key, required this.filled, this.hasError = false});

  final int filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final errorColor = AppColors.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(passcodeLength, (index) {
        final isFilled = index < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasError
                ? errorColor.withValues(alpha: isFilled ? 1 : 0.25)
                : (isFilled ? AppColors.primaryMaroon : AppColors.borderSubtle),
            boxShadow: isFilled && !hasError
                ? [
                    BoxShadow(
                      color: AppColors.primaryMaroonGlow,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

/// Custom rounded-square numeric keypad standing in for the system
/// keyboard — each key gives tactile press-depth feedback on tap.
class PasscodeKeypad extends StatelessWidget {
  const PasscodeKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  static const _layout = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _layout)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final key in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: key.isEmpty
                        ? const SizedBox(width: 68, height: 68)
                        : _KeypadKey(
                            label: key,
                            enabled: enabled,
                            onTap: key == '⌫'
                                ? onBackspace
                                : () => onDigit(key),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _KeypadKey extends StatefulWidget {
  const _KeypadKey({
    required this.label,
    required this.onTap,
    required this.enabled,
  });
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_KeypadKey> createState() => _KeypadKeyState();
}

class _KeypadKeyState extends State<_KeypadKey> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final isBackspace = widget.label == '⌫';
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onTap();
            }
          : null,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 68,
          height: 68,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(18),
            boxShadow: _pressed
                ? AppElevation.card(false)
                : AppElevation.raised(false),
          ),
          child: isBackspace
              ? Icon(
                  Icons.backspace_outlined,
                  size: 22,
                  color: widget.enabled
                      ? AppColors.inkText
                      : AppColors.mutedText,
                )
              : Text(
                  widget.label,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: widget.enabled
                        ? AppColors.inkText
                        : AppColors.mutedText,
                    fontSize: 24,
                  ),
                ),
        ),
      ),
    );
  }
}
