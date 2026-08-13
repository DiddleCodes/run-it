import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/radar_pulse.dart';
import '../../../core/widgets/runner_mark.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) context.go(AppRoutes.onboarding);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBg = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RadarPulse(
              maxExtent: 300,
              child: const RunnerMark(size: 108),
            ).animate().scale(
              begin: const Offset(0.8, 0.8),
              end: const Offset(1, 1),
              duration: 500.ms,
              curve: Curves.easeOutBack,
            ),
            const SizedBox(height: 28),
            Text(
              'run-it.',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: onBg,
              ),
            ).animate().fadeIn(delay: 300.ms, duration: 400.ms).moveY(
              begin: 8,
              end: 0,
              delay: 300.ms,
              duration: 400.ms,
            ),
            const SizedBox(height: 8),
            Text(
              'Campus deliveries in minutes.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: secondary),
            ).animate().fadeIn(delay: 450.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }
}
