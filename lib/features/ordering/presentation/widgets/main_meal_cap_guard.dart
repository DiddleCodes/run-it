import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ordering_providers.dart';
import '../../domain/ordering_models.dart';
import '../../domain/pricing_service.dart';

/// Task 70: the one place every "add more of this" path (Menu's quick add,
/// the Item Options sheet, the Basket's +) asks before growing the basket,
/// so the main-meal cap is met with a choice at the moment it bites rather
/// than a blocked Checkout button later. Honest UX only — the real cap is
/// OrderEscrowService.hold's own server-side check.
///
/// Returns whether the caller should go ahead and apply the change. When
/// the student switches to Group Order here, this returns true so the meal
/// they just tried to add is added straight away.
Future<bool> confirmMainMealIncrease(
  BuildContext context,
  WidgetRef ref, {
  required MenuItem item,
  required int newQuantity,
}) async {
  if (!item.isMainMeal) return true;
  final basket = ref.read(basketProvider);
  // A different eatery's basket is about to be replaced (the caller's own
  // "Start a new basket?" flow) — only this item would be left in it.
  final replacing = basket.eateryId != null && basket.eateryId != item.eateryId;
  final before = replacing ? 0 : _mainMeals(ref, extra: item);
  final currentQuantity = replacing
      ? 0
      : basket.items.where((line) => line.menuItemId == item.id).fold(0, (sum, line) => sum + line.quantity);
  final after = before - currentQuantity + newQuantity;
  if (after <= before) return true;

  final isGroupOrder = ref.read(checkoutFormProvider).isGroupOrder;
  final cap = isGroupOrder ? PricingService.groupMainMealCap : PricingService.standardMainMealCap;
  if (after <= cap) return true;

  if (!isGroupOrder && after <= PricingService.groupMainMealCap) {
    final switchToGroup = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('Ordering for a group? 👀'),
        content: Text(
          'Solo orders are limited to ${PricingService.standardMainMealCap} main meals. '
          'Switch to Group Order to add up to ${PricingService.groupMainMealCap} meals in one delivery, '
          'for just ₦${PricingService.groupOrderSurcharge} extra.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep solo order'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Switch to Group Order'),
          ),
        ],
      ),
    );
    if (switchToGroup != true) return false;
    ref.read(checkoutFormProvider.notifier).setGroupOrder(true);
    return true;
  }

  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog.adaptive(
      title: const Text('That’s the most for one order'),
      content: Text(
        'One order can include up to ${PricingService.groupMainMealCap} main meals. '
        'For more, place a second order.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK')),
      ],
    ),
  );
  return false;
}

/// Task 70: call after any change that may have removed main meals, with
/// the count from just before it. If a Group Order has dropped to what a
/// solo order already covers, offers to switch back so the student doesn't
/// pay the surcharge for nothing — once per drop, not on every tap.
Future<void> offerSoloIfGroupUnneeded(
  BuildContext context,
  WidgetRef ref, {
  required int mainMealsBefore,
}) async {
  if (!ref.read(checkoutFormProvider).isGroupOrder) return;
  final now = _mainMeals(ref);
  if (mainMealsBefore <= PricingService.standardMainMealCap || now > PricingService.standardMainMealCap) return;

  // Nothing left to deliver — nothing to ask about either.
  if (ref.read(basketProvider).isEmpty) {
    ref.read(checkoutFormProvider.notifier).setGroupOrder(false);
    return;
  }

  final switchToSolo = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog.adaptive(
      title: const Text('Switch back to a solo order?'),
      content: Text(
        'You’re down to $now main meal${now == 1 ? '' : 's'} — a solo order covers up to '
        '${PricingService.standardMainMealCap}, so you won’t pay the ₦${PricingService.groupOrderSurcharge} '
        'Group Order extra.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Keep Group Order'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Switch to solo'),
        ),
      ],
    ),
  );
  if (switchToSolo == true) ref.read(checkoutFormProvider.notifier).setGroupOrder(false);
}

/// Main meals currently in the basket (by quantity; sides and drinks never
/// count). [extra] covers an item not (yet) in the loaded menu list.
int currentMainMeals(WidgetRef ref) => _mainMeals(ref);

int _mainMeals(WidgetRef ref, {MenuItem? extra}) {
  final menu = ref.read(menuProvider).valueOrNull ?? const <MenuItem>[];
  return PricingService.mainMealCount(
    basket: ref.read(basketProvider),
    menuItems: [
      ...menu.where((item) => item.id != extra?.id),
      ?extra,
    ],
  );
}
