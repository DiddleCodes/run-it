import '../../vendor/domain/vendor_dashboard_models.dart';
import '../domain/ordering_models.dart';

/// Task 14: turns the backend's real vendor/menu-item shapes (shared with
/// the Restaurant Dashboard, Task 12) into this feature's own `Eatery`/
/// `MenuItem` domain models — the one seam between "what the backend calls
/// it" and "what the student-ordering UI has always called it", replacing
/// `MockOrderingRepository`'s hand-authored fixtures entirely.
extension VendorToEatery on MyVendorProfile {
  Eatery toEatery() => Eatery(
    id: id,
    name: businessName,
    bannerUrl: logoUrl,
    blurb: (description != null && description!.trim().isNotEmpty) ? description!.trim() : category,
  );
}

extension VendorMenuItemToMenuItem on VendorMenuItem {
  /// [vendorId] comes from the parent [VendorWithMenu.vendor] rather than
  /// this item's own JSON — the backend's `MenuItem` row doesn't echo its
  /// own `vendorId` back in `GET /vendors/:id/menu`'s per-item shape (it
  /// doesn't need to; the whole list is already scoped to one vendor).
  MenuItem toMenuItem(String vendorId) => MenuItem(
    id: id,
    eateryId: vendorId,
    name: name,
    description: description ?? '',
    // Kobo -> naira: every naira amount in this feature (PricingService,
    // naira()) is a whole-naira int, matching the Restaurant Dashboard's
    // own priceKobo ~/ 100 display convention (see restaurant_menu_screen).
    price: priceKobo ~/ 100,
    // No packaging-fee concept on the backend's MenuItem row yet — real
    // items simply carry no packaging cost, rather than a fabricated one.
    packagingCost: 0,
    category: category,
    imageUrl: photoUrl ?? '',
    isAvailable: isAvailable,
  );
}
