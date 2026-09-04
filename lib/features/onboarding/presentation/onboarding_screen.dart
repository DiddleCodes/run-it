import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';
import 'widgets/campus_collage_visual.dart';
import 'widgets/delivery_hero_visual.dart';
import 'widgets/dual_mode_visual.dart';
import 'widgets/onboarding_progress_track.dart';

class _OnboardingPage {
  const _OnboardingPage({
    required this.headlinePrefix,
    required this.headlineHighlight,
    required this.body,
    required this.visual,
    this.header,
  });

  /// The headline is split so the final word/phrase can render in
  /// [AppColors.accentRose] — e.g. "Campus meals, delivered to " + "you."
  final String headlinePrefix;
  final String headlineHighlight;
  final String body;
  final Widget Function(BuildContext, double parallax) visual;

  /// Replaces the shared compact top bar with a page-specific cover header
  /// (e.g. the centered logo lockup on the hero page). Optional — most
  /// pages just use the shared bar.
  final WidgetBuilder? header;
}

/// A corner decoration image whose source PNG has a hard, straight-cut
/// edge baked in (these are raster extractions from a flattened design,
/// not clean vector cutouts — see design/assets/README.txt). Rather than
/// let that seam show as a pasted-on rectangle, a radial [ShaderMask]
/// dissolves the image to transparent right at the screen corner it
/// bleeds off of, so only its organic inner silhouette stays visible.
class _CornerImage extends StatelessWidget {
  const _CornerImage({
    required this.asset,
    required this.height,
    required this.fadeFrom,
    required this.angle,
    this.opacity = 0.9,
  });

  final String asset;
  final double height;

  /// The screen corner this image bleeds off of — the fade center.
  final Alignment fadeFrom;
  final double angle;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Opacity(
        opacity: opacity,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => RadialGradient(
            center: fadeFrom,
            radius: 1.15,
            colors: const [Colors.transparent, Colors.white],
            stops: const [0.0, 0.62],
          ).createShader(rect),
          child: Image.asset(asset, height: height),
        ),
      ),
    );
  }
}

/// Soft-focus food renders bleeding off the four corners, matching the
/// reference splash's layered-imagery treatment. Only meaningful behind
/// the "Campus meals" page, so its opacity is driven by how close the
/// [PageView] currently is to that page.
class _CornerBloom extends StatelessWidget {
  const _CornerBloom({required this.opacity});
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0.01) return const SizedBox.shrink();
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Stack(
          children: [
            const Positioned(
              top: -18,
              left: -34,
              child: _CornerImage(
                asset: 'assets/images/03_top-left_food_bowl.png',
                height: 190,
                angle: -0.05,
                fadeFrom: Alignment.topLeft,
                opacity: 0.92,
              ),
            ),
            const Positioned(
              top: -16,
              right: -30,
              child: _CornerImage(
                asset: 'assets/images/04_top-right_greens_bowl.png',
                height: 180,
                angle: 0.04,
                fadeFrom: Alignment.topRight,
                opacity: 0.9,
              ),
            ),
            Positioned(
              top: 130,
              right: 6,
              child: Transform.rotate(
                angle: 0.2,
                child: Opacity(
                  opacity: 0.85,
                  child: Image(
                    image: AssetImage('assets/images/05_floating_leaf.png'),
                    height: 22,
                  ),
                ),
              ),
            ),
            const Positioned(
              bottom: -22,
              right: -28,
              child: _CornerImage(
                asset: 'assets/images/06_bottom-right_food_bowl.png',
                height: 200,
                angle: -0.04,
                fadeFrom: Alignment.bottomRight,
                opacity: 0.92,
              ),
            ),
            const Positioned(
              bottom: -14,
              left: -32,
              child: _CornerImage(
                asset: 'assets/images/07_bottom-left_burger.png',
                height: 180,
                angle: 0.06,
                fadeFrom: Alignment.bottomLeft,
                opacity: 0.9,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
      headlinePrefix: 'Campus meals, delivered to ',
      headlineHighlight: 'you.',
      body: 'Order from the spots you already know, brought to you by peers already heading your way.',
      visual: (context, parallax) => Transform.translate(
        offset: Offset(parallax * 24, 0),
        child: const DeliveryHeroVisual(),
      ),
      header: (context) => Column(
        children: [
          Image.asset('assets/images/02_run-it_logo.png', height: 56),
          const SizedBox(height: 6),
          Text(
            'Food, your way.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.onMaroon.withValues(alpha: .65)),
          ),
        ],
      ),
    ),
    _OnboardingPage(
      headlinePrefix: 'Every canteen, café, and shop, ',
      headlineHighlight: 'all in one place.',
      body: 'No delivery zones, no strangers off campus — just the spots you know.',
      visual: (context, parallax) => Transform.translate(
        offset: Offset(parallax * 24, 0),
        child: const CampusCollageVisual(),
      ),
    ),
    _OnboardingPage(
      headlinePrefix: 'Need something, or got ',
      headlineHighlight: 'a few minutes?',
      body: 'Switch between requesting and running anytime — right from your profile.',
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
    final cornerOpacity = (1 - _page.abs()).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.primaryMaroon,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.6, -0.9),
            radius: 1.6,
            colors: [
              AppColors.primaryMaroonDeep.withValues(alpha: 0.0),
              AppColors.primaryMaroon,
            ],
            stops: const [0.0, 0.75],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: _CornerBloom(opacity: cornerOpacity)),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    children: [
                      Opacity(
                        opacity: _page.clamp(0.0, 1.0),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/images/02_run-it_logo.png',
                                height: 34,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Food, your way.',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: AppColors.onMaroon.withValues(
                                        alpha: .6,
                                      ),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: PageView.builder(
                          controller: _controller,
                          itemCount: _pages.length,
                          itemBuilder: (context, index) {
                            final page = _pages[index];
                            final parallax = (_page - index).clamp(-1.0, 1.0);

                            return LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                  ),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (page.header != null) ...[
                                          page.header!(context),
                                          const SizedBox(height: 20),
                                        ],
                                        page.visual(context, parallax),
                                        const SizedBox(height: 24),
                                        Text.rich(
                                          TextSpan(
                                            children: [
                                              TextSpan(
                                                text: page.headlinePrefix,
                                              ),
                                              TextSpan(
                                                text: page.headlineHighlight,
                                                style: const TextStyle(
                                                  color: AppColors.accentRose,
                                                ),
                                              ),
                                            ],
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 3,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineMedium
                                              ?.copyWith(
                                                color: AppColors.onMaroon,
                                              ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          page.body,
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.copyWith(
                                                color: AppColors.onMaroon
                                                    .withValues(alpha: .72),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OnboardingProgressTrack(
                              pageCount: _pages.length,
                              page: _page,
                            ),
                            const SizedBox(height: AppSpacing.ml),
                            PrimaryButton(
                              label: _isLastPage ? 'Get Started' : 'Continue',
                              icon: Icons.arrow_forward_rounded,
                              onPressed: () {
                                if (_isLastPage) {
                                  context.go(AppRoutes.accountType);
                                } else {
                                  _controller.nextPage(
                                    duration: const Duration(milliseconds: 380),
                                    curve: Curves.easeOutCubic,
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 14),
                            Center(
                              child: TextButton(
                                onPressed: () => context.go(AppRoutes.login),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.onMaroon
                                      .withValues(alpha: .78),
                                ),
                                child: const Text('I have an account'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
