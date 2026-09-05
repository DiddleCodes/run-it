import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/features/ordering/data/vendor_menu_mapping.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';

void main() {
  group('VendorToEatery', () {
    test('uses the vendor\'s own description as the blurb when it has one', () {
      const vendor = MyVendorProfile(
        id: 'vendor-1',
        businessName: 'Tantalizers',
        category: 'Meals',
        description: 'Jollof rice, grilled chicken, and sides.',
        logoUrl: 'https://cdn.example.com/logo.png',
      );

      final eatery = vendor.toEatery();

      expect(eatery.id, 'vendor-1');
      expect(eatery.name, 'Tantalizers');
      expect(eatery.bannerUrl, 'https://cdn.example.com/logo.png');
      expect(eatery.blurb, 'Jollof rice, grilled chicken, and sides.');
      // Task 48: null here since this fixture never sets averageRating —
      // an unrated vendor genuinely has no rating, never a fabricated one.
      // No vendor-level prep-time backend field exists yet either.
      expect(eatery.rating, isNull);
      expect(eatery.prepTimeMinutes, isNull);
    });

    test('Task 48: carries the vendor\'s real average rating through once it has one', () {
      const vendor = MyVendorProfile(
        id: 'vendor-1',
        businessName: 'Tantalizers',
        category: 'Meals',
        averageRating: 4.6,
        ratingCount: 23,
      );

      expect(vendor.toEatery().rating, 4.6);
    });

    test('falls back to category as the blurb when there is no description', () {
      const vendor = MyVendorProfile(id: 'vendor-2', businessName: 'Café 167', category: 'Drinks');

      expect(vendor.toEatery().blurb, 'Drinks');
    });

    test('falls back to category when the description is blank', () {
      const vendor = MyVendorProfile(id: 'vendor-3', businessName: 'Mama\'s Kitchen', category: 'Local', description: '   ');

      expect(vendor.toEatery().blurb, 'Local');
    });
  });

  group('VendorMenuItemToMenuItem', () {
    test('converts kobo to whole naira and carries the real availability flag', () {
      const item = VendorMenuItem(
        id: 'item-1',
        name: 'Signature jollof',
        description: 'Smoky jollof rice.',
        priceKobo: 310000,
        photoUrl: 'https://cdn.example.com/jollof.png',
        category: 'Mains',
        isAvailable: false,
      );

      final menuItem = item.toMenuItem('vendor-1');

      expect(menuItem.eateryId, 'vendor-1');
      expect(menuItem.price, 3100);
      expect(menuItem.imageUrl, 'https://cdn.example.com/jollof.png');
      expect(menuItem.isAvailable, isFalse);
      // No packaging-fee field on the backend's MenuItem yet.
      expect(menuItem.packagingCost, 0);
    });

    test('defaults a null description to an empty string rather than crashing', () {
      const item = VendorMenuItem(id: 'item-2', name: 'Malt', priceKobo: 70000, category: 'Drinks', isAvailable: true);

      expect(item.toMenuItem('vendor-1').description, '');
    });
  });
}
