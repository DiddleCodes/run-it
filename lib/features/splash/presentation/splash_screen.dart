import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/radar_pulse.dart';
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
  // a maroon radar-pulse badge and a bespoke two-tone "run-it." logotype
  // as the centerpiece (the onboarding flow carries the one photographic
  // illustration in this pre-auth sequence; splash stays logo-led).
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
                RadarPulse(
                  color: AppColors.primaryMaroon.withValues(alpha: 0.4),
                  maxExtent: 260,
                  child: Container(
                    width: 92,
                    height: 92,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accentRose,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryMaroonDeep.withValues(
                            alpha: 0.22,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.room_service_rounded,
                      color: AppColors.primaryMaroon,
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'run',
                        style: GoogleFonts.fraunces(
                          fontSize: 52,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                          color: AppColors.inkText,
                        ),
                      ),
                      TextSpan(
                        text: '-it.',
                        style: GoogleFonts.fraunces(
                          fontSize: 52,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                          fontStyle: FontStyle.italic,
                          color: AppColors.primaryMaroon,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 2,
                  color: AppColors.accentRoseDeep,
                ),
                const SizedBox(height: 12),
                Text(
                  'FOOD, YOUR WAY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.mutedText,
                    letterSpacing: 2.4,
                    fontWeight: FontWeight.w600,
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
