import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';

import '../../../../core/utils/money.dart';

export '../../../../core/utils/money.dart' show formatKobo, naira;

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

class CategoryChip extends StatefulWidget {
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
  State<CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<CategoryChip> {
  bool _pressed = false;
  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _setPressed(true),
    onTapUp: (_) => _setPressed(false),
    onTapCancel: () => _setPressed(false),
    onTap: () {
      HapticFeedback.selectionClick();
      widget.onTap();
    },
    child: AnimatedScale(
      scale: _pressed ? 0.95 : 1,
      duration: AppMotion.fast,
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: widget.selected
              ? AppColors.primaryMaroon
              : OrderingColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            width: widget.selected ? 1 : 1.2,
            color: widget.selected
                ? AppColors.primaryMaroon
                : OrderingColors.border(context),
          ),
          // Task 52: same "raised until pressed" elevation the Home
          // screen's own category chips now get — an inactive chip here is
          // just as tappable and shouldn't read as a flat label either.
          boxShadow: (widget.selected || _pressed) ? const [] : AppElevation.card(false),
        ),
        child: Text(
          widget.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: widget.selected ? AppColors.onMaroon : OrderingColors.text(context),
          ),
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

/// One line of a price breakdown (Basket, Checkout, the tracking summary):
/// bold label on the left, the amount flush right with tabular digits so
/// every row's amounts line up like a receipt. [emphasized] is the Total.
class PriceRow extends StatelessWidget {
  const PriceRow({
    super.key,
    required this.label,
    required this.amount,
    this.emphasized = false,
  });
  final String label;

  /// Naira.
  final num amount;
  final bool emphasized;
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final base = (emphasized ? textTheme.titleLarge : textTheme.bodyMedium)?.copyWith(
      color: OrderingColors.text(context),
      fontSize: emphasized ? 17 : null,
      fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: base),
            ),
            const SizedBox(width: 12),
            // Shrinks to fit rather than overflow at large text sizes.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  naira(amount),
                  style: base?.copyWith(
                    fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Task 10 performance audit: no screen in this app loads a real remote
/// image yet — every `imageUrl`/`bannerUrl` in the mock data is `''`, so
/// this has always rendered the seeded-color placeholder below. [imageUrl]
/// is accepted now so call sites don't need to change again the moment a
/// real backend URL (e.g. Task 9's `menu_items.photo_url`) actually starts
/// flowing into this data — `cached_network_image` gives disk+memory
/// caching and an explicit decode size for free, so a thumbnail slot never
/// loads a full-resolution image into memory.
class MenuImagePlaceholder extends StatelessWidget {
  const MenuImagePlaceholder({super.key, required this.seed, this.size = 82, this.imageUrl});
  final String seed;
  final double size;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final placeholder = _SeedPlaceholder(seed: seed, size: size);
    if (imageUrl == null || imageUrl!.isEmpty) return placeholder;

    final pixelSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Decodes at the actual display size (not the source resolution) —
        // the point of "explicit sizing," not just a fixed layout box.
        memCacheWidth: pixelSize,
        memCacheHeight: pixelSize,
        placeholder: (context, url) => placeholder,
        errorWidget: (context, url, error) => placeholder,
      ),
    );
  }
}

class _SeedPlaceholder extends StatelessWidget {
  const _SeedPlaceholder({required this.seed, required this.size});
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
