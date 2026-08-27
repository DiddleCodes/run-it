import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';

String naira(int value) => '₦${value.toString()}';

/// Thin, context-taking accessors over the app's one (cream) palette —
/// kept as static methods rather than inlining `AppColors.x` at every call
/// site so this file's many widgets read consistently either way.
class OrderingColors {
  const OrderingColors._();
  static Color text(BuildContext context) => AppColors.inkText;
  static Color muted(BuildContext context) => AppColors.mutedText;
  static Color surface(BuildContext context) => AppColors.surfaceCard;
  static Color border(BuildContext context) => AppColors.borderSubtle;
}

class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: AppMotion.fast,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primaryMaroon
            : OrderingColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? AppColors.primaryMaroon
              : OrderingColors.border(context),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: selected ? AppColors.onMaroon : OrderingColors.text(context),
        ),
      ),
    ),
  );
}

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    this.compact = false,
  });
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 36.0;
    if (quantity == 0) {
      return _TactileAddPill(onTap: onAdd, height: size);
    }
    return AnimatedSize(
      duration: AppMotion.fast,
      curve: AppMotion.emphasized,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: AppColors.backgroundCream,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              onTap: onRemove,
              size: size - 4,
            ),
            AnimatedSwitcher(
              duration: AppMotion.fast,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: SizedBox(
                key: ValueKey(quantity),
                width: compact ? 26 : 32,
                child: Text(
                  '$quantity',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: OrderingColors.text(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _StepButton(icon: Icons.add_rounded, onTap: onAdd, size: size - 4),
          ],
        ),
      ),
    );
  }
}

/// A small, individually-raised circular key — same tactile language as
/// the passcode keypad's `_KeypadKey` (press-depth scale, a soft shadow
/// that flattens on press, a selection haptic) scaled down to fit inline
/// in a list row instead of a full-screen numpad.
class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.size,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  bool _pressed = false;
  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: AnimatedScale(
          scale: _pressed ? 0.85 : 1,
          duration: AppMotion.fast,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              shape: BoxShape.circle,
              boxShadow: _pressed ? const [] : AppElevation.card(false),
            ),
            child: Icon(widget.icon, size: 15, color: AppColors.primaryMaroon),
          ),
        ),
      ),
    );
  }
}

/// The zero-quantity "Add" affordance — same press-depth + haptic
/// treatment as [_StepButton], just pill-shaped and filled since it's a
/// standalone CTA rather than one half of a paired control.
class _TactileAddPill extends StatefulWidget {
  const _TactileAddPill({required this.onTap, required this.height});
  final VoidCallback onTap;
  final double height;

  @override
  State<_TactileAddPill> createState() => _TactileAddPillState();
}

class _TactileAddPillState extends State<_TactileAddPill> {
  bool _pressed = false;
  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1,
        duration: AppMotion.fast,
        curve: Curves.easeOut,
        child: Container(
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryMaroon,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            boxShadow: _pressed
                ? const []
                : [
                    BoxShadow(
                      color: AppColors.primaryMaroonGlow,
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Text(
            'Add',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.onMaroon,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class PriceRow extends StatelessWidget {
  const PriceRow({
    super.key,
    required this.label,
    required this.amount,
    this.emphasized = false,
  });
  final String label;
  final int amount;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(
          label,
          style:
              (emphasized
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.bodyMedium)
                  ?.copyWith(
                    color: emphasized
                        ? OrderingColors.text(context)
                        : OrderingColors.muted(context),
                    fontSize: emphasized ? 17 : null,
                  ),
        ),
        const Spacer(),
        Text(
          naira(amount),
          style:
              (emphasized
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.bodyMedium)
                  ?.copyWith(
                    color: OrderingColors.text(context),
                    fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
                  ),
        ),
      ],
    ),
  );
}

class MenuImagePlaceholder extends StatelessWidget {
  const MenuImagePlaceholder({super.key, required this.seed, this.size = 82});
  final String seed;
  final double size;
  @override
  Widget build(BuildContext context) {
    final swatches = [
      const Color(0xFFD8B593),
      const Color(0xFFB4C1AE),
      const Color(0xFFB6B2D5),
      const Color(0xFFD5A7A0),
    ];
    final color = swatches[seed.codeUnitAt(0) % swatches.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.restaurant_rounded,
        color: AppColors.primaryMaroonDeep.withValues(alpha: .75),
        size: size * .38,
      ),
    );
  }
}
