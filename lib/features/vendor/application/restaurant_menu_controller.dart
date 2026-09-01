import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/vendors_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/vendor_dashboard_models.dart';
import 'my_vendor_profile_controller.dart';

/// The Menu tab's own list. Read-back after every mutation (create/update/
/// delete/availability) rather than editing local state directly — a menu
/// item's real, server-confirmed shape (e.g. after backend-side
/// normalization) is what the kitchen and student-facing menu both depend
/// on being right.
class RestaurantMenuController extends AsyncNotifier<List<VendorMenuItem>> {
  @override
  Future<List<VendorMenuItem>> build() => _fetch();

  Future<List<VendorMenuItem>> _fetch() async {
    final vendor = await ref.watch(myVendorProfileProvider.future);
    final withMenu = await ref.read(vendorsRepositoryProvider).fetchMenu(vendor.id);
    return withMenu.items;
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<VendorMenuItem>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard<List<VendorMenuItem>>(_fetch);
  }

  String _requireToken() {
    final session = ref.read(authControllerProvider);
    if (session == null) throw StateError('Menu action called with no active session');
    return session.accessToken;
  }

  Future<void> createItem({
    required String name,
    String? description,
    required int priceKobo,
    String? photoUrl,
    required String category,
  }) async {
    await ref
        .read(vendorsRepositoryProvider)
        .createMenuItem(
          name: name,
          description: description,
          priceKobo: priceKobo,
          photoUrl: photoUrl,
          category: category,
          token: _requireToken(),
        );
    await refresh();
  }

  Future<void> updateItem({
    required String itemId,
    required String name,
    String? description,
    required int priceKobo,
    String? photoUrl,
    required String category,
  }) async {
    await ref
        .read(vendorsRepositoryProvider)
        .updateMenuItem(
          itemId: itemId,
          name: name,
          description: description,
          priceKobo: priceKobo,
          photoUrl: photoUrl,
          category: category,
          token: _requireToken(),
        );
    await refresh();
  }

  Future<void> setAvailability(String itemId, bool isAvailable) async {
    await ref
        .read(vendorsRepositoryProvider)
        .setMenuItemAvailability(itemId: itemId, isAvailable: isAvailable, token: _requireToken());
    await refresh();
  }

  Future<void> deleteItem(String itemId) async {
    await ref.read(vendorsRepositoryProvider).deleteMenuItem(itemId: itemId, token: _requireToken());
    await refresh();
  }
}

final restaurantMenuProvider = AsyncNotifierProvider<RestaurantMenuController, List<VendorMenuItem>>(
  RestaurantMenuController.new,
);

/// Every category already used across this vendor's own menu — what the
/// Add/Edit Menu Item screen's category selector offers as quick-pick
/// chips, matching exactly what the student-side filter chips derive from
/// (see `EateryMenuScreen`'s own category-chip logic) rather than a
/// separate fixed list that could drift from it.
final restaurantMenuCategoriesProvider = Provider<List<String>>((ref) {
  final items = ref.watch(restaurantMenuProvider).valueOrNull ?? const [];
  return {for (final item in items) item.category}.toList()..sort();
});
