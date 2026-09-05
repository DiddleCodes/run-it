import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/campus_repository.dart';
import '../../../core/network/vendors_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../../vendor/domain/vendor_dashboard_models.dart';
import '../data/vendor_menu_mapping.dart';
import '../domain/ordering_models.dart';

/// The category chip currently selected on the Home screen's vendor list —
/// `null` means "All". Kept as app-wide state (rather than local widget
/// state) so it and [vendorSearchQueryProvider] can drive one shared
/// [campusEateriesProvider] fetch.
final vendorCategoryFilterProvider = StateProvider<String?>((ref) => null);

/// The Home screen's search bar text, debounced by the widget itself before
/// it's written here (see `_Search`) — a keystroke-per-request would be
/// wasteful and would spam `GET /vendors`.
final vendorSearchQueryProvider = StateProvider<String>((ref) => '');

/// Every active vendor matching the current category/search filters (Task
/// 14) — backs the Home screen's "Popular around campus" list and (via
/// [availableJobsProvider] in the runner feature) the runner's job-preview
/// list. Empty means the filters genuinely matched nothing, not a fetch
/// failure — callers show an empty state for that, never a blank screen.
final campusEateriesProvider = FutureProvider<List<Eatery>>((ref) async {
  final category = ref.watch(vendorCategoryFilterProvider);
  final search = ref.watch(vendorSearchQueryProvider).trim();
  final page = await ref.watch(vendorsRepositoryProvider).listVendors(
    category: category,
    search: search.isEmpty ? null : search,
  );
  return page.items.map((vendor) => vendor.toEatery()).toList();
});

/// The vendor id a student is currently viewing the menu for — set when
/// tapping a vendor card or "Order Now" on Home, before navigating to
/// [AppRoutes.menu]. `null` means nothing has been picked yet.
final selectedVendorIdProvider = StateProvider<String?>((ref) => null);

/// One fetch, shared by [selectedEateryProvider] and [menuProvider] below —
/// `GET /vendors/:id/menu` already returns both the vendor and its items
/// together, so there's no reason for its two consumers to each trigger
/// their own network call.
final _selectedVendorWithMenuProvider = FutureProvider<VendorWithMenu?>((ref) async {
  final vendorId = ref.watch(selectedVendorIdProvider);
  if (vendorId == null) return null;
  return ref.watch(vendorsRepositoryProvider).fetchMenu(vendorId);
});

final selectedEateryProvider = FutureProvider<Eatery?>((ref) async {
  final withMenu = await ref.watch(_selectedVendorWithMenuProvider.future);
  return withMenu?.vendor.toEatery();
});

/// The full vendor profile behind [selectedEateryProvider] — unlike the
/// mapped `Eatery`, this carries `userId`, which checkout needs to hold
/// escrow for the REAL vendor a student ordered from (see
/// `MyVendorProfile.userId`'s own doc comment) instead of the fixed demo
/// restaurant identity.
final selectedVendorProfileProvider = FutureProvider<MyVendorProfile?>((ref) async {
  final withMenu = await ref.watch(_selectedVendorWithMenuProvider.future);
  return withMenu?.vendor;
});

final menuProvider = FutureProvider<List<MenuItem>>((ref) async {
  final withMenu = await ref.watch(_selectedVendorWithMenuProvider.future);
  if (withMenu == null) return const [];
  return withMenu.items.map((item) => item.toMenuItem(withMenu.vendor.id)).toList();
});

enum AddToBasketResult { added, needsReplacement }

class BasketNotifier extends Notifier<Basket> {
  @override
  Basket build() => const Basket();

  AddToBasketResult add(MenuItem item) {
    if (state.eateryId != null && state.eateryId != item.eateryId) {
      return AddToBasketResult.needsReplacement;
    }
    final lines = [...state.items];
    final index = lines.indexWhere((line) => line.menuItemId == item.id);
    if (index == -1) {
      lines.add(BasketItem(menuItemId: item.id, quantity: 1));
    } else {
      lines[index] = lines[index].copyWith(quantity: lines[index].quantity + 1);
    }
    state = Basket(items: lines, eateryId: item.eateryId);
    return AddToBasketResult.added;
  }

  /// Sets a line's quantity (Task 6's Item Options sheet, quantity-only
  /// since Task 45 moved notes to a single order-level field).
  AddToBasketResult setLine(MenuItem item, {required int quantity}) {
    if (state.eateryId != null && state.eateryId != item.eateryId) {
      return AddToBasketResult.needsReplacement;
    }
    final lines = [...state.items];
    final index = lines.indexWhere((line) => line.menuItemId == item.id);
    if (quantity <= 0) {
      if (index != -1) lines.removeAt(index);
    } else if (index == -1) {
      lines.add(BasketItem(menuItemId: item.id, quantity: quantity));
    } else {
      lines[index] = BasketItem(menuItemId: item.id, quantity: quantity);
    }
    state = Basket(
      items: lines,
      eateryId: lines.isEmpty ? null : item.eateryId,
    );
    return AddToBasketResult.added;
  }

  void replaceWith(MenuItem item) {
    state = Basket(
      eateryId: item.eateryId,
      items: [BasketItem(menuItemId: item.id, quantity: 1)],
    );
  }

  void setQuantity(String itemId, int quantity) {
    final lines = [...state.items];
    final index = lines.indexWhere((line) => line.menuItemId == itemId);
    if (index == -1) return;
    if (quantity <= 0) {
      lines.removeAt(index);
    } else {
      lines[index] = lines[index].copyWith(quantity: quantity);
    }
    state = Basket(
      items: lines,
      eateryId: lines.isEmpty ? null : state.eateryId,
    );
  }

  void remove(String itemId) => setQuantity(itemId, 0);
  void clear() => state = const Basket();
}

final basketProvider = NotifierProvider<BasketNotifier, Basket>(
  BasketNotifier.new,
);

class CheckoutForm {
  const CheckoutForm({
    required this.location,
    this.paymentMethod = PaymentMethod.wallet,
    this.note,
  });

  final DeliveryLocation location;
  final PaymentMethod paymentMethod;
  // Task 45: one note for the whole order, replacing the old per-item
  // notes — set on the Basket screen, read at checkout.
  final String? note;
  CheckoutForm copyWith({
    DeliveryLocation? location,
    PaymentMethod? paymentMethod,
    String? note,
  }) => CheckoutForm(
    location: location ?? this.location,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    note: note ?? this.note,
  );
}

class CheckoutFormNotifier extends Notifier<CheckoutForm> {
  @override
  CheckoutForm build() {
    // Profile has no dedicated address model yet — its own "Delivery
    // Address" row is just the signed-in user's campus name (see
    // `student_profile_screen.dart`). Seed the same real value here rather
    // than a hall name unrelated to whoever is actually signed in.
    // Task 10 performance audit: only campus name actually matters here —
    // selecting it means an unrelated session change (token refresh, KYC
    // status) doesn't rebuild (and reset) this form.
    final campusId = ref.watch(
      authControllerProvider.select((session) => session?.user.campusId),
    );
    final campusName = ref.watch(campusNameProvider(campusId));
    return CheckoutForm(
      location: DeliveryLocation(
        label: campusName == null
            ? 'Set your delivery point'
            : '$campusName · Drop-off point',
      ),
    );
  }

  void setPayment(PaymentMethod value) =>
      state = state.copyWith(paymentMethod: value);
  // `copyWith`'s `note ?? this.note` can't express "the user cleared the
  // note back to empty" — a full replace, same reasoning setLine used to
  // apply to per-item notes before Task 45 moved this to one field.
  void setNote(String? value) =>
      state = CheckoutForm(location: state.location, paymentMethod: state.paymentMethod, note: value);
}

final checkoutFormProvider =
    NotifierProvider<CheckoutFormNotifier, CheckoutForm>(
      CheckoutFormNotifier.new,
    );
