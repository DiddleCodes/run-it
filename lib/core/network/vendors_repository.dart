import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/vendor/domain/vendor_dashboard_models.dart';
import 'api_client.dart';

final vendorsRepositoryProvider = Provider<VendorsRepository>(
  (ref) => const VendorsRepository(),
);

/// The controlled vendor-category vocabulary — effectively static, so
/// (like `banksProvider`) it's fetched once per provider container rather
/// than re-fetched on every rebuild.
final vendorCategoriesProvider = FutureProvider<List<VendorCategoryOption>>(
  (ref) => ref.read(vendorsRepositoryProvider).fetchCategories(),
);

/// Real backend calls against `/vendors/me/*` (Task 9/11/12) — the
/// Restaurant Dashboard's own data layer. Every method takes the caller's
/// own [token] explicitly (mirroring `EscrowRepository`/`OrdersRepository`)
/// rather than reading a session provider itself, so this stays a plain,
/// independently-testable HTTP client.
class VendorsRepository {
  const VendorsRepository({this.client = const ApiClient()});

  final ApiClient client;

  Future<MyVendorProfile> fetchMyVendor({required String token}) async {
    final json = await client.get('/vendors/me', token: token) as Map<String, dynamic>;
    return MyVendorProfile.fromJson(json);
  }

  /// Task 12: also what the first-run profile-completion screen calls to
  /// replace the backend's auto-provisioned placeholder vendor (see
  /// `OrderEscrowService.resolveVendorId`'s doc comment) with the
  /// restaurant's real submitted details.
  Future<MyVendorProfile> upsertMyVendor({
    required String businessName,
    required String category,
    String? description,
    String? logoUrl,
    String? requestedCampusId,
    // Task 47: omitted entirely (not just `false`) when a caller doesn't
    // pass it, so a routine business-info edit never accidentally flips a
    // restaurant's existing Pay on Delivery opt-in back off.
    bool? payAtDeliveryEnabled,
    required String token,
  }) async {
    final json =
        await client.post(
              '/vendors/me',
              token: token,
              body: {
                'businessName': businessName,
                'category': category,
                if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
                'logoUrl': ?logoUrl,
                'requestedCampusId': ?requestedCampusId,
                'payAtDeliveryEnabled': ?payAtDeliveryEnabled,
              },
            )
            as Map<String, dynamic>;
    return MyVendorProfile.fromJson(json);
  }

  /// Public — the controlled category vocabulary vendors must pick from
  /// (`upsertMyVendor` rejects anything else) and students filter Home by.
  Future<List<VendorCategoryOption>> fetchCategories() async {
    final json = await client.get('/vendors/categories') as List;
    return json.map((e) => VendorCategoryOption.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Public — a student browsing campus vendors (Task 14): "Popular around
  /// campus", category chips, and the search bar all page through this. No
  /// [category]/[search] means every active vendor, page 1.
  Future<VendorsPage> listVendors({String? category, String? search, int page = 1, int limit = 20}) async {
    final query = {
      'page': '$page',
      'limit': '$limit',
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final path = Uri(path: '/vendors', queryParameters: query).toString();
    final json = await client.get(path) as Map<String, dynamic>;
    return VendorsPage.fromJson(json);
  }

  /// One vendor's own menu — the public `GET /vendors/:id/menu` (Task 9).
  /// Serves both the Restaurant Dashboard (Task 12, which already knows its
  /// own [vendorId] from [fetchMyVendor] and only needs `.items`) and Task
  /// 14's student-side browsing (which also needs `.vendor` for the eatery
  /// hero) — one call, not two overlapping ones.
  Future<VendorWithMenu> fetchMenu(String vendorId) async {
    final json = await client.get('/vendors/$vendorId/menu') as Map<String, dynamic>;
    return VendorWithMenu.fromJson(json);
  }

  Future<VendorMenuItem> createMenuItem({
    required String name,
    String? description,
    required int priceKobo,
    String? photoUrl,
    required String category,
    required String token,
  }) async {
    final json =
        await client.post(
              '/vendors/me/menu-items',
              token: token,
              body: {
                'name': name,
                if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
                'price': priceKobo,
                'photoUrl': ?photoUrl,
                'category': category,
              },
            )
            as Map<String, dynamic>;
    return VendorMenuItem.fromJson(json);
  }

  Future<VendorMenuItem> updateMenuItem({
    required String itemId,
    required String name,
    String? description,
    required int priceKobo,
    String? photoUrl,
    required String category,
    required String token,
  }) async {
    final json =
        await client.patch(
              '/vendors/me/menu-items/$itemId',
              token: token,
              body: {
                'name': name,
                'description': description?.trim() ?? '',
                'price': priceKobo,
                'photoUrl': ?photoUrl,
                'category': category,
              },
            )
            as Map<String, dynamic>;
    return VendorMenuItem.fromJson(json);
  }

  Future<void> setMenuItemAvailability({
    required String itemId,
    required bool isAvailable,
    required String token,
  }) async {
    await client.patch(
      '/vendors/me/menu-items/$itemId/availability',
      token: token,
      body: {'isAvailable': isAvailable},
    );
  }

  Future<void> deleteMenuItem({required String itemId, required String token}) async {
    await client.delete('/vendors/me/menu-items/$itemId', token: token);
  }

  /// Extends Task 11's `/orders/incoming` rather than a second, overlapping
  /// GET — see `VendorsService.listIncomingOrders`'s own doc comment
  /// backend-side. No [status] means "the live kitchen queue".
  Future<VendorOrdersPage> fetchOrders({
    RestaurantOrderStatus? status,
    int page = 1,
    int limit = 20,
    required String token,
  }) async {
    final query = {
      'page': '$page',
      'limit': '$limit',
      if (status != null) 'status': status.toJson,
    };
    final path = Uri(path: '/vendors/me/orders/incoming', queryParameters: query).toString();
    final json = await client.get(path, token: token) as Map<String, dynamic>;
    return VendorOrdersPage.fromJson(json);
  }

  /// Forward-only (`preparing`/`ready_for_pickup`) — see
  /// `UpdateOrderStatusDto` backend-side for why nothing else is accepted
  /// here.
  Future<void> advanceOrderStatus({
    required String orderId,
    required RestaurantOrderStatus status,
    required String token,
  }) async {
    await client.patch(
      '/vendors/me/orders/$orderId/status',
      token: token,
      body: {'status': status.toJson},
    );
  }

  Future<VendorMetrics> fetchMetrics({
    DateTime? from,
    DateTime? to,
    required String token,
  }) async {
    final query = {
      if (from != null) 'from': from.toIso8601String(),
      if (to != null) 'to': to.toIso8601String(),
    };
    final path = Uri(path: '/vendors/me/metrics', queryParameters: query).toString();
    final json = await client.get(path, token: token) as Map<String, dynamic>;
    return VendorMetrics.fromJson(json);
  }
}
