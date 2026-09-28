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
    isMainMeal: true,
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
    isMainMeal: false,
  ),
];

void main() {
  group('PricingService', () {
    test('calculates all order costs in one place, with a single flat delivery fee', () {
      const basket = Basket(
        eateryId: 'tantalizers',
        items: [
          BasketItem(menuItemId: 'jollof', quantity: 2),
          BasketItem(menuItemId: 'malt', quantity: 1),
        ],
      );

      final result = PricingService.calculate(basket: basket, menuItems: _menuItems);

      expect(result.subtotal, 6900);
      expect(result.packagingTotal, 200);
      // Task 45: a single flat ₦500 fee — no more campus zones.
      expect(result.deliveryFee, 500);
      // Task 70: 5% of the food subtotal only (₦6,900 -> ₦345) — packaging
      // and delivery never count toward it.
      expect(result.serviceFee, 345);
      expect(result.serviceFeePercentLabel, '5%');
      expect(result.total, 6900 + 200 + 500 + 345);
    });

    // Task 70.
    test('uses the backend-served rate and delivery fee when given', () {
      const basket = Basket(
        eateryId: 'tantalizers',
        items: [BasketItem(menuItemId: 'malt', quantity: 1)],
      );

      final result = PricingService.calculate(
        basket: basket,
        menuItems: _menuItems,
        config: const PricingConfig(serviceFeeRate: 0.1, deliveryFee: 600),
      );

      expect(result.serviceFee, 70);
      expect(result.deliveryFee, 600);
      expect(result.serviceFeePercentLabel, '10%');
    });

    test('serviceFeeFor rounds to the nearest whole naira, half up — same as the backend', () {
      expect(PricingService.serviceFeeFor(1000, 0.05), 50);
      expect(PricingService.serviceFeeFor(1234, 0.05), 62); // 61.70
      expect(PricingService.serviceFeeFor(1230, 0.05), 62); // 61.50
      expect(PricingService.serviceFeeFor(1229, 0.05), 61); // 61.45
      expect(PricingService.serviceFeeFor(10, 0.05), 1); // 0.50
      expect(PricingService.serviceFeeFor(9, 0.05), 0); // 0.45
      expect(PricingService.serviceFeeFor(0, 0.05), 0);
    });

    test('does not apply fees to an empty basket', () {
      final result = PricingService.calculate(basket: const Basket(), menuItems: _menuItems);

      expect(result.total, 0);
      expect(result.deliveryFee, 0);
      expect(result.serviceFee, 0);
    });

    // Task 66: Group Ordering.
    test('adds a flat ₦150 surcharge to the delivery fee when isGroupOrder is true', () {
      const basket = Basket(
        eateryId: 'tantalizers',
        items: [BasketItem(menuItemId: 'jollof', quantity: 2)],
      );

      final standard = PricingService.calculate(basket: basket, menuItems: _menuItems);
      final group = PricingService.calculate(basket: basket, menuItems: _menuItems, isGroupOrder: true);

      expect(standard.deliveryFee, 500);
      expect(group.deliveryFee, 650);
      // The surcharge only ever touches delivery — nothing else moves.
      expect(group.subtotal, standard.subtotal);
      expect(group.serviceFee, standard.serviceFee);
      expect(group.total, standard.total + 150);
    });

    test('an empty basket stays fee-free even with isGroupOrder true', () {
      final result = PricingService.calculate(basket: const Basket(), menuItems: _menuItems, isGroupOrder: true);
      expect(result.deliveryFee, 0);
    });

    test('mainMealCount sums only isMainMeal:true lines by quantity', () {
      const basket = Basket(
        eateryId: 'tantalizers',
        items: [
          BasketItem(menuItemId: 'jollof', quantity: 2),
          BasketItem(menuItemId: 'malt', quantity: 5),
        ],
      );

      // 2 main-meal jollof units count; 5 malt units (isMainMeal: false)
      // never do, no matter the quantity.
      expect(PricingService.mainMealCount(basket: basket, menuItems: _menuItems), 2);
    });

    test('standardMainMealCap is 2 and groupMainMealCap is 4', () {
      expect(PricingService.standardMainMealCap, 2);
      expect(PricingService.groupMainMealCap, 4);
    });
  });
}
