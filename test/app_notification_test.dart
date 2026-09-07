import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/widgets/app_notification.dart';

void main() {
  group('AppNotificationController (Task 59)', () {
    test('calling error() again with the same message while the first is still live is a no-op, not a duplicate', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appNotificationProvider.notifier);

      notifier.error("Couldn't reach the server. Check your connection and try again.");
      notifier.error("Couldn't reach the server. Check your connection and try again.");

      expect(container.read(appNotificationProvider), hasLength(1));
    });

    test('a genuinely new message still shows as its own notification', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appNotificationProvider.notifier);

      notifier.error('First failure.');
      notifier.error('Second, different failure.');

      expect(container.read(appNotificationProvider), hasLength(2));
    });

    test('the same message is shown again as a new notification once the first has actually been dismissed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appNotificationProvider.notifier);

      final firstId = notifier.show(type: AppNotificationType.error, message: 'Retry me.');
      notifier.dismiss(firstId);
      notifier.remove(firstId);
      final secondId = notifier.show(type: AppNotificationType.error, message: 'Retry me.');

      expect(container.read(appNotificationProvider), hasLength(1));
      expect(secondId, isNot(equals(firstId)));
    });

    test('non-error types with a short auto-dismiss timer also dedupe while live', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appNotificationProvider.notifier);

      notifier.info('Code sent to a@student.ui.edu.ng.');
      notifier.info('Code sent to a@student.ui.edu.ng.');

      expect(container.read(appNotificationProvider), hasLength(1));
    });
  });
}
