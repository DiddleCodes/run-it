import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _redirectTimer;

  @override
  void initState() {
    super.initState();
    // The native launch screen is held (see main.dart's
    // FlutterNativeSplash.preserve call) until right here — the first
    // frame this widget is actually about to paint — so the native-to-
    // Dart handoff happens at a moment the user can actually see, and the
    // redirect timer below gets this screen's full intended visible
    // duration rather than counting down invisibly underneath the native
    // splash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
    _redirectTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      final user = ref.read(authControllerProvider)?.user;
      context.go(
        user == null ? AppRoutes.onboarding : postAuthDestination(user),
      );
    });
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    super.dispose();
  }

  // Brief branded loader shown before role/session redirect — cream, with
  // the RUN iT lockup and tagline as the centerpiece (the onboarding flow
  // carries the one photographic illustration in this pre-auth sequence;
  // splash stays logo-led).
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 1.1,
                  colors: [
                    AppColors.accentRose.withValues(alpha: 0.35),
                    AppColors.backgroundCream,
                  ],
                  stops: const [0.0, 0.85],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Task 76: the stacked RUN iT lockup, at exactly the size and
                // position the native launch screen shows it (220pt wide,
                // 28pt above centre — see LaunchScreen.storyboard), so the
                // native -> Flutter handoff doesn't jump.
                Image.asset('assets/branding/run_it_wordmark.png', width: 220),
                const SizedBox(height: 24),
                Container(
                  width: 36,
                  height: 2,
                  color: AppColors.accentRoseDeep,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 18,
                  child: Center(
                    child: Text(
                      'NEED IT, BRIDGIT',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.mutedText,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
