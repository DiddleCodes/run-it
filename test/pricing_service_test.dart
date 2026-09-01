import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/features/ordering/domain/ordering_models.dart';
import 'package:run_it/features/ordering/domain/pricing_service.dart';

const _menuItems = <MenuItem>[
  MenuItem(
    id: 'jollof',
    eateryId: 'tantalizers',
    name: 'Signature jollof',
    description: 'Smoky jollof rice, grilled chicken and plantain.',
    price: 3100,
    packagingCost: 100,
    category: 'Mains',
    imageUrl: '',
    isAvailable: true,
  ),
  MenuItem(
    id: 'malt',
    eateryId: 'tantalizers',
    name: 'Chilled malt',
    description: 'Cold, bottled and ready for the walk back.',
    price: 700,
    packagingCost: 0,
    category: 'Drinks',
    imageUrl: '',
    isAvailable: true,
  ),
];

void main() {
  group('PricingService', () {
    test('calculates all order costs in one place', () {
      const basket = Basket(
        eateryId: 'tantalizers',
        items: [
          BasketItem(menuItemId: 'jollof', quantity: 2),
          BasketItem(menuItemId: 'malt', quantity: 1),
        ],
      );

      final result = PricingService.calculate(
        basket: basket,
        menuItems: _menuItems,
        zone: DeliveryFeeZone.central,
      );

      expect(result.subtotal, 6900);
      expect(result.packagingTotal, 200);
      expect(result.deliveryFee, 350);
      expect(result.serviceFee, 150);
      expect(result.total, 7600);
    });

    test('does not apply fees to an empty basket', () {
      final result = PricingService.calculate(
        basket: const Basket(),
        menuItems: _menuItems,
        zone: DeliveryFeeZone.north,
      );

      expect(result.total, 0);
      expect(result.deliveryFee, 0);
      expect(result.serviceFee, 0);
    });
  });
}
