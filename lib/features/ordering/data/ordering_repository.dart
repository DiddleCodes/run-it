import '../domain/ordering_models.dart';

/// Thrown when a request asks for data belonging to a campus other than
/// the one it was scoped to — e.g. fetching an eatery/menu by id without
/// that id actually belonging to the given `campusId`. This is the
/// repository-layer rejection: campus enforcement happens here, not by
/// filtering results after the fact in a widget.
class CampusMismatchException implements Exception {
  CampusMismatchException(this.message);
  final String message;
  @override
  String toString() => 'CampusMismatchException: $message';
}

abstract class OrderingRepository {
  /// Every vendor visible to a caller, scoped to their campus. A campus
  /// with no active vendors yet simply returns an empty list — that's the
  /// legitimate "nothing here yet" case the UI shows an empty state for.
  Future<List<Eatery>> getEateries({required String campusId});

  /// Throws [CampusMismatchException] if [id] doesn't belong to [campusId]
  /// — this is the enforcement point, not a lookup that happens to work
  /// because there's only one eatery in the mock data.
  Future<Eatery> getEatery({required String id, required String campusId});

  /// Throws [CampusMismatchException] under the same condition as
  /// [getEatery] — a menu can't be read for an eatery outside the
  /// caller's campus.
  Future<List<MenuItem>> getMenu({required String eateryId, required String campusId});
}

class MockOrderingRepository implements OrderingRepository {
  const MockOrderingRepository();

  static const eatery = Eatery(
    id: 'tantalizers',
    name: 'Tantalizers',
    bannerUrl: '',
    rating: 4.8,
    prepTimeMinutes: 12,
    isOpen: true,
    campusId: 'ui',
  );

  static const eateries = <Eatery>[eatery];

  static const menu = <MenuItem>[
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
      id: 'rice',
      eateryId: 'tantalizers',
      name: 'Coconut fried rice',
      description: 'Fragrant rice with vegetables and a protein of choice.',
      price: 2800,
      packagingCost: 100,
      category: 'Mains',
      imageUrl: '',
      isAvailable: true,
    ),
    MenuItem(
      id: 'wrap',
      eateryId: 'tantalizers',
      name: 'Chicken shawarma',
      description: 'Charred chicken, crisp salad and house sauce.',
      price: 2200,
      packagingCost: 80,
      category: 'Quick bites',
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
    MenuItem(
      id: 'shake',
      eateryId: 'tantalizers',
      name: 'Vanilla shake',
      description: 'Currently taking a break from the menu.',
      price: 1500,
      packagingCost: 50,
      category: 'Drinks',
      imageUrl: '',
      isAvailable: false,
    ),
  ];

  @override
  Future<List<Eatery>> getEateries({required String campusId}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return eateries.where((e) => e.campusId == campusId).toList();
  }

  @override
  Future<Eatery> getEatery({required String id, required String campusId}) async {
    final scoped = await getEateries(campusId: campusId);
    for (final candidate in scoped) {
      if (candidate.id == id) return candidate;
    }
    throw CampusMismatchException(
      'Eatery "$id" is not available for campus "$campusId".',
    );
  }

  @override
  Future<List<MenuItem>> getMenu({
    required String eateryId,
    required String campusId,
  }) async {
    // Verifies the eatery actually belongs to this campus before handing
    // back any menu data — throws rather than silently returning nothing,
    // since reaching this with a mismatched id/campus pair means a caller
    // is trying to read data it was never scoped to see.
    await getEatery(id: eateryId, campusId: campusId);
    await Future.delayed(const Duration(milliseconds: 300));
    return menu.where((item) => item.eateryId == eateryId).toList();
  }
}
