import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/features/ordering/data/ordering_repository.dart';

void main() {
  group('MockOrderingRepository campus scoping', () {
    const repo = MockOrderingRepository();

    test('getEateries returns only vendors on the requested campus', () async {
      final ui = await repo.getEateries(campusId: 'ui');
      expect(ui, hasLength(1));
      expect(ui.first.id, 'tantalizers');

      final otherCampus = await repo.getEateries(campusId: 'bu');
      expect(otherCampus, isEmpty);
    });

    test(
      'getEatery rejects a cross-campus request instead of returning it',
      () async {
        // The eatery exists — just not on this campus — so this must be a
        // rejection, not a silent "not found" that looks the same as a typo.
        expect(
          () => repo.getEatery(id: 'tantalizers', campusId: 'oau'),
          throwsA(isA<CampusMismatchException>()),
        );
        final matched = await repo.getEatery(id: 'tantalizers', campusId: 'ui');
        expect(matched.id, 'tantalizers');
      },
    );

    test(
      'getMenu rejects a cross-campus request at the repository boundary',
      () async {
        expect(
          () => repo.getMenu(eateryId: 'tantalizers', campusId: 'cu'),
          throwsA(isA<CampusMismatchException>()),
        );
        final items = await repo.getMenu(
          eateryId: 'tantalizers',
          campusId: 'ui',
        );
        expect(items, isNotEmpty);
      },
    );
  });
}
