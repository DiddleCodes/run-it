import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/network/api_client.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_notification.dart';
import 'features/auth/application/auth_controller.dart';

void main() {
  runApp(const ProviderScope(child: RunItApp()));
}

class RunItApp extends ConsumerWidget {
  const RunItApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Task 17: the one place every ApiClient instance's 401s get routed to
    // a clean logout, regardless of which repository made the call — see
    // ApiClient.onUnauthorized's own doc comment. Reassigning on every
    // build is deliberately cheap/idempotent rather than needing its own
    // StatefulWidget/initState just for this.
    ApiClient.onUnauthorized = () =>
        ref.read(authControllerProvider.notifier).handleUnauthorized();

    return MaterialApp.router(
      title: 'run-it.',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) =>
          AppNotificationHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
