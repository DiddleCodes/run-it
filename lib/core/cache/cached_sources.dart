import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_models.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/notifications/domain/app_notification.dart';
import '../../features/ordering/domain/order_history_models.dart';
import '../../features/vendor/domain/vendor_dashboard_models.dart';
import '../../features/wallet/data/wallet_repository.dart';
import '../network/orders_repository.dart';
import '../network/vendors_repository.dart';
import 'cached_fetch.dart';
import 'local_cache.dart';

/// Every cached data source, defined once: the screens' providers load
/// through these, and the reconnect refresh refreshes the same entries.

/// The student's campus restaurant list (unfiltered — searches and
/// filters always go to the network).
CachedSource<List<MyVendorProfile>> vendorListSource(Ref ref, AuthSession session) => CachedSource(
  key: CacheKeys.vendors(session.user.id),
  fetch: () async => (await ref.read(vendorsRepositoryProvider).listVendors(token: session.accessToken)).items,
  encode: (vendors) => [for (final vendor in vendors) vendor.toJson()],
  decode: (json) => [
    for (final vendor in json! as List<dynamic>) MyVendorProfile.fromJson(vendor as Map<String, dynamic>),
  ],
);

CachedSource<List<VendorCategoryOption>> vendorCategoriesSource(Ref ref) => CachedSource(
  key: CacheKeys.categories,
  fetch: () => ref.read(vendorsRepositoryProvider).fetchCategories(),
  encode: (options) => [for (final option in options) option.toJson()],
  decode: (json) => [
    for (final option in json! as List<dynamic>) VendorCategoryOption.fromJson(option as Map<String, dynamic>),
  ],
);

CachedSource<VendorWithMenu> menuSource(Ref ref, String vendorId) => CachedSource(
  key: CacheKeys.menu(vendorId),
  fetch: () => ref.read(vendorsRepositoryProvider).fetchMenu(vendorId),
  encode: (menu) => menu.toJson(),
  decode: (json) => VendorWithMenu.fromJson(json! as Map<String, dynamic>),
);

/// The student's order history (first page — what My Orders shows).
CachedSource<List<OrderHistoryEntry>> orderHistorySource(Ref ref, AuthSession session) => CachedSource(
  key: CacheKeys.orders(session.user.id),
  fetch: () async => (await ref.read(ordersRepositoryProvider).fetchOrderHistory(token: session.accessToken)).items,
  encode: (orders) => [for (final order in orders) order.toJson()],
  decode: (json) => [
    for (final order in json! as List<dynamic>) OrderHistoryEntry.fromJson(order as Map<String, dynamic>),
  ],
);

/// The balance shown on screen — display only. Paying never reads this:
/// the backend checks the real balance when it holds the money.
CachedSource<num> walletBalanceSource(Ref ref, AuthSession session) => CachedSource(
  key: CacheKeys.wallet(session.user.id),
  fetch: () => ref.read(walletRepositoryProvider).getBalance(userId: session.user.id, token: session.accessToken),
  encode: (balance) => balance,
  decode: (json) => json! as num,
);

/// The student's notification centre (newest page + unread count).
CachedSource<NotificationFeed> notificationsSource(Ref ref, AuthSession session) => CachedSource(
  key: CacheKeys.notifications(session.user.id),
  fetch: () => ref.read(notificationsRepositoryProvider).list(token: session.accessToken),
  encode: (feed) => feed.toJson(),
  decode: (json) => NotificationFeed.fromJson(json! as Map<String, dynamic>),
);

/// Brings every saved copy for [session] up to date — including menus and
/// screens that aren't open. Menus: the most recently saved few.
Future<void> refreshAllCached(Ref ref, AuthSession session, {int maxMenus = 10}) async {
  final cache = ref.read(localCacheProvider);
  final menuIds = [
    for (final key in cache.keys)
      if (key.startsWith(CacheKeys.menuPrefix)) (key.substring(CacheKeys.menuPrefix.length), cache.read(key)?.savedAt),
  ]..sort((a, b) => (b.$2 ?? DateTime(0)).compareTo(a.$2 ?? DateTime(0)));
  final isStudent = session.user.accountType == AccountType.student;
  await Future.wait([
    if (isStudent) refreshCached(ref, vendorListSource(ref, session)),
    if (isStudent) refreshCached(ref, vendorCategoriesSource(ref)),
    if (isStudent) refreshCached(ref, orderHistorySource(ref, session)),
    if (isStudent) refreshCached(ref, notificationsSource(ref, session)),
    refreshCached(ref, walletBalanceSource(ref, session)),
    for (final (vendorId, _) in menuIds.take(maxMenus)) refreshCached(ref, menuSource(ref, vendorId)),
  ]);
}
