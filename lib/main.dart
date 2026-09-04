import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/monitoring/crash_reporting.dart';
import 'core/network/api_client.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_notification.dart';
import 'features/auth/application/auth_controller.dart';

Future<void> main() async {
  // Task 31: initializeCrashReporting's appRunner callback runs inside
  // Sentry's own guarded zone (see that function's doc comment) — the
  // widgets binding must be created in that *same* zone as runApp, or
  // Flutter's debugCheckZone throws a real "Zone mismatch" assertion the
  // first time runApp is called (confirmed by hitting it directly while
  // building this). That's why both calls that used to sit above this
  // block, before crash reporting existed, now live inside appRunner
  // instead of ahead of it.
  await initializeCrashReporting(
    appRunner: () {
      // Holds the native launch screen up past Flutter's own default
      // first-frame auto-dismiss — without this, the native splash and
      // SplashScreen's redirect timer race independently, and the timer
      // (which starts as soon as SplashScreen's initState runs) can burn
      // through most or all of its visible window before the native splash
      // actually lifts, making the branded Dart splash flash by almost
      // invisibly. SplashScreen itself calls FlutterNativeSplash.remove()
      // once its first frame is about to paint, so the handoff — and the
      // redirect timer's start — line up with what the user actually sees.
      final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
      runApp(const ProviderScope(child: RunItApp()));
    },
  );
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
