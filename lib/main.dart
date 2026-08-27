import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_notification.dart';

void main() {
  runApp(const ProviderScope(child: RunItApp()));
}

class RunItApp extends ConsumerWidget {
  const RunItApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
