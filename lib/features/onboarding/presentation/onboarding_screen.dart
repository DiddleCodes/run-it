import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import 'widgets/campus_collage_visual.dart';
import 'widgets/dual_mode_visual.dart';
import 'widgets/onboarding_progress_track.dart';

class _OnboardingPage {
  const _OnboardingPage({
    required this.title,
    required this.body,
    required this.visual,
  });

  final String title;
  final String body;
  final Widget Function(BuildContext, double parallax) visual;
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  double _page = 0;

  late final _pages = [
    _OnboardingPage(
      title: 'Delivered by people already heading your way.',
      body:
          'Tap into a network of peers crossing campus right now. Faster, cheaper, and fundamentally more efficient.',
      visual: (context, parallax) => Transform.translate(
        offset: Offset(parallax * 24, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Image.asset(
            'assets/images/onboarding_handoff.png',
            height: 320,
            fit: BoxFit.cover,
          ),
        ),
      ),
    ),
    _OnboardingPage(
      title: 'Every canteen, café, and shop on campus.',
      body:
          'Order from the spots you already know — no delivery zones, no strangers off campus.',
      visual: (context, parallax) => Transform.translate(
        offset: Offset(parallax * 24, 0),
        child: const CampusCollageVisual(),
      ),
    ),
    _OnboardingPage(
      title: 'Need something, or got a few minutes?',
      body:
          'Switch between requesting and running anytime — right from your profile.',
      visual: (context, parallax) => Transform.translate(
        offset: Offset(parallax * 24, 0),
        child: const DualModeVisual(),
      ),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _page = _controller.page ?? 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLastPage => _page >= _pages.length - 1 - 0.05;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBg = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  final parallax = (_page - index).clamp(-1.0, 1.0);

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        page.visual(context, parallax),
                        const SizedBox(height: 40),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.headlineMedium?.copyWith(color: onBg),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(color: secondary),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
              child: OnboardingProgressTrack(
                pageCount: _pages.length,
                page: _page,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: Column(
                children: [
                  PrimaryButton(
                    label: _isLastPage ? 'Get started' : 'Continue',
                    onPressed: () {
                      if (_isLastPage) {
                        context.go(AppRoutes.phoneAuth);
                      } else {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 380),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.phoneAuth),
                    child: const Text('I have an account'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
