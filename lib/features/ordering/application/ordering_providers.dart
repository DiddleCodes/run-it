import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/ordering_repository.dart';
import '../domain/ordering_models.dart';

final orderingRepositoryProvider = Provider<OrderingRepository>(
  (ref) => const MockOrderingRepository(),
);

/// The signed-in user's campus — every ordering query below is scoped to
/// this and nothing else. The actual enforcement lives in
/// `ordering_repository.dart`; this just supplies the scope.
final currentCampusIdProvider = Provider<String?>(
  (ref) => ref.watch(authControllerProvider)?.user.campusId,
);

/// Every vendor available on the signed-in user's campus. Empty means the
/// campus genuinely has no active vendors yet — the UI shows an empty
/// state for that, not a crash or a blank screen.
final campusEateriesProvider = FutureProvider<List<Eatery>>((ref) async {
  final campusId = ref.watch(currentCampusIdProvider);
  if (campusId == null) return const [];
  return ref.watch(orderingRepositoryProvider).getEateries(campusId: campusId);
});

/// There's no vendor-picker screen yet, so this is simply the first (and
/// currently only) eatery on the user's campus — `null` when the campus
/// has none.
final selectedEateryProvider = FutureProvider<Eatery?>((ref) async {
  final eateries = await ref.watch(campusEateriesProvider.future);
  return eateries.isEmpty ? null : eateries.first;
});

final menuProvider = FutureProvider<List<MenuItem>>((ref) async {
  final campusId = ref.watch(currentCampusIdProvider);
  final eatery = await ref.watch(selectedEateryProvider.future);
  if (campusId == null || eatery == null) return const [];
  return ref
      .watch(orderingRepositoryProvider)
      .getMenu(eateryId: eatery.id, campusId: campusId);
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
  });

  final DeliveryLocation location;
  final PaymentMethod paymentMethod;
  CheckoutForm copyWith({
    DeliveryLocation? location,
    PaymentMethod? paymentMethod,
  }) => CheckoutForm(
    location: location ?? this.location,
    paymentMethod: paymentMethod ?? this.paymentMethod,
  );
}

class CheckoutFormNotifier extends Notifier<CheckoutForm> {
  @override
  CheckoutForm build() {
    // Profile has no dedicated address model yet — its own "Delivery
    // Address" row is just the signed-in user's campus name (see
    // `student_profile_screen.dart`). Seed the same real value here rather
    // than a hall name unrelated to whoever is actually signed in.
    final campusName = ref.watch(authControllerProvider)?.user.campus.name;
    return CheckoutForm(
      location: DeliveryLocation(
        label: campusName == null
            ? 'Set your delivery point'
            : '$campusName · Drop-off point',
        zone: DeliveryFeeZone.central,
      ),
    );
  }

  void setPayment(PaymentMethod value) =>
      state = state.copyWith(paymentMethod: value);
  void setLocation(DeliveryLocation value) =>
      state = state.copyWith(location: value);
}

final checkoutFormProvider =
    NotifierProvider<CheckoutFormNotifier, CheckoutForm>(
      CheckoutFormNotifier.new,
    );
