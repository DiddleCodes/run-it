import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

const passcodeLength = 6;

/// Six dot indicators that fill in as digits are entered — the iOS
/// system-passcode convention, skinned in maroon/cream. [shake] plays a
/// horizontal shake (driven by the caller, e.g. on a confirm mismatch).
///
/// Filled vs. empty is never color-only: empty dots render as a hollow
/// ring, filled dots as a solid disc, so the state still reads for
/// color-blind users. The next dot to be filled (the "cursor" position)
/// gets a subtle scale bump so entry progress feels alive rather than a
/// flat on/off toggle.
class PasscodeDots extends StatelessWidget {
  const PasscodeDots({super.key, required this.filled, this.hasError = false});

  final int filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final errorColor = AppColors.error;
    // Every keystroke repaints the affected dot's AnimatedScale/
    // AnimatedContainer (Task 10 performance audit) — isolating that from
    // the surrounding keypad/screen keeps each keystroke's repaint scoped
    // to these six dots.
    return RepaintBoundary(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(passcodeLength, (index) {
          final isFilled = index < filled;
          final isActive = !hasError && index == filled;
          return AnimatedScale(
            scale: isActive ? 1.2 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasError
                    ? errorColor.withValues(alpha: isFilled ? 1 : 0.12)
                    : (isFilled ? AppColors.primaryMaroon : Colors.transparent),
                border: isFilled
                    ? null
                    : Border.all(
                        color: hasError
                            ? errorColor.withValues(alpha: 0.4)
                            : AppColors.borderSubtle,
                        width: 1.5,
                      ),
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
            ),
          );
        }),
      ),
    );
  }
}

/// Config for an optional biometric-shortcut key rendered in the keypad's
/// bottom-left slot (row 4, before "0") — e.g. Welcome Back's fingerprint/
/// Face ID shortcut. Left null on [PasscodeKeypad] anywhere that slot
/// should stay blank (Set Passcode's create/confirm keypad has nothing to
/// put there).
class PasscodeBiometricKey {
  const PasscodeBiometricKey({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
}

/// Custom rounded-square numeric keypad standing in for the system
/// keyboard — each key gives tactile press-depth feedback on tap.
class PasscodeKeypad extends StatelessWidget {
  const PasscodeKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
    this.biometricKey,
    this.keySize = 68,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;
  final PasscodeBiometricKey? biometricKey;

  /// Lets compact layouts (small phones, or a screen with other content
  /// competing for vertical space) shrink the keys slightly — never below
  /// the 44pt minimum tap target.
  final double keySize;

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
                    child: key.isNotEmpty
                        ? _KeypadKey(
                            label: key,
                            enabled: enabled,
                            size: keySize,
                            onTap: key == '⌫'
                                ? onBackspace
                                : () => onDigit(key),
                          )
                        : biometricKey == null
                        ? SizedBox(width: keySize, height: keySize)
                        : _KeypadKey(
                            icon: biometricKey!.icon,
                            semanticLabel: biometricKey!.semanticLabel,
                            enabled: enabled,
                            size: keySize,
                            onTap: biometricKey!.onTap,
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
    this.label,
    this.icon,
    this.semanticLabel,
    required this.onTap,
    required this.enabled,
    required this.size,
  });
  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final VoidCallback onTap;
  final bool enabled;
  final double size;

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
    final glyphIcon = widget.icon ?? (isBackspace ? Icons.backspace_outlined : null);
    final label =
        widget.semanticLabel ?? (isBackspace ? 'Delete' : widget.label);
    final iconColor = widget.icon != null
        ? AppColors.gold
        : (widget.enabled ? AppColors.inkText : AppColors.mutedText);

    return Semantics(
      button: true,
      label: label,
      enabled: widget.enabled,
      child: GestureDetector(
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
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(18),
              boxShadow: _pressed
                  ? AppElevation.card(false)
                  : AppElevation.raised(false),
            ),
            child: glyphIcon != null
                ? Icon(glyphIcon, size: 22, color: iconColor)
                : Text(
                    widget.label!,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(
                          color: widget.enabled
                              ? AppColors.inkText
                              : AppColors.mutedText,
                          fontSize: 24,
                        ),
                  ),
          ),
        ),
      ),
    );
  }
}
