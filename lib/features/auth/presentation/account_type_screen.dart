import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';
import '../domain/auth_models.dart';

/// Runner's gold accent doesn't exist anywhere else in the app yet, so it
/// stays a local pair here rather than a shared token. Student now uses
/// [AppColors.primaryMaroon] directly (previously a separate near-duplicate
/// local burgundy) and Restaurant uses [AppColors.accentForest] — both
/// proper shared tokens, so only gold needs a local definition.

/// UI-only selection, kept separate from [AccountType] purely so this
/// screen's own `_selected` field name/values read naturally — all three
/// cases map 1:1 onto an [AccountType] in `_continue()` below. Restaurant
/// goes through the exact same session-creating signup → OTP → passcode →
/// biometric funnel as the other two now (see `postBiometricDestination`);
/// only what comes after biometric setup differs.
enum _Role { student, runner, restaurant }

/// The very first real choice in the app. Student is pre-selected by
/// default (the common case) so Continue is reachable immediately; the
/// disabled-button style still exists for robustness even though the
/// current flow can't actually reach a null selection.
class AccountTypeScreen extends StatefulWidget {
  const AccountTypeScreen({super.key});

  @override
  State<AccountTypeScreen> createState() => _AccountTypeScreenState();
}

class _AccountTypeScreenState extends State<AccountTypeScreen> {
  _Role? _selected = _Role.student;

  void _select(_Role role) {
    if (_selected == role) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = role);
  }

  void _continue() {
    final role = _selected;
    if (role == null) return;
    HapticFeedback.mediumImpact();
    switch (role) {
      case _Role.student:
        context.push(AppRoutes.signup, extra: AccountType.student);
      case _Role.runner:
        context.push(AppRoutes.signup, extra: AccountType.runner);
      case _Role.restaurant:
        context.push(AppRoutes.signup, extra: AccountType.restaurant);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth.clamp(0.0, 480.0);
            return Center(
              child: SizedBox(
                width: maxWidth,
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Header(),
                          const SizedBox(height: 10),
                          const _HeroSection(),
                          const SizedBox(height: 14),
                          _RoleCard(
                            icon: Icons.school_rounded,
                            accent: AppColors.primaryMaroon,
                            title: "I'm a Student",
                            description: 'Order meals from vendors on campus.',
                            selected: _selected == _Role.student,
                            onTap: () => _select(_Role.student),
                          ),
                          const SizedBox(height: 12),
                          _RoleCard(
                            icon: Icons.two_wheeler_rounded,
                            accent: AppColors.gold,
                            title: "I'm a Runner",
                            description:
                                'Deliver orders and earn on your schedule.',
                            selected: _selected == _Role.runner,
                            onTap: () => _select(_Role.runner),
                          ),
                          const SizedBox(height: 12),
                          _RoleCard(
                            icon: Icons.storefront_rounded,
                            accent: AppColors.accentForest,
                            title: "I'm a Restaurant",
                            description: 'Sell your meals on campus.',
                            selected: _selected == _Role.restaurant,
                            onTap: () => _select(_Role.restaurant),
                          ),
                          const SizedBox(height: 14),
                          const _TrustFooter(),
                          const SizedBox(height: 10),
                          PrimaryButton(
                            label: 'Continue',
                            icon: Icons.arrow_forward_rounded,
                            onPressed: _selected == null ? null : _continue,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.maroonShadow,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: AppColors.inkText, size: 20),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _CircleIconButton(
          icon: Icons.arrow_back_rounded,
          semanticLabel: 'Back',
          onTap: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.onboarding),
        ),
        _CircleIconButton(
          icon: Icons.help_outline_rounded,
          semanticLabel: 'Help',
          onTap: () {
            HapticFeedback.selectionClick();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Students order, Runners deliver, Restaurants sell on campus.',
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 4,
          right: 0,
          child: IgnorePointer(
            child: SizedBox(
              width: 76,
              height: 96,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/route_decoration.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const Positioned(
                    right: 0,
                    top: 40,
                    child: Icon(
                      Icons.location_on,
                      color: AppColors.primaryMaroon,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 70),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'How will you\nuse '),
                    TextSpan(
                      text: 'RUN-It?',
                      style: TextStyle(color: AppColors.primaryMaroon),
                    ),
                  ],
                ),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: AppColors.inkText,
                  fontSize: 27,
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This helps us verify the right details\nfor a smooth experience.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mutedText,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Reserves the space + rounded frame a real 3D icon render will drop
/// into later. Falls back to a tinted, ghost-iconed panel so the card
/// still reads as intentional (not a bug) until that asset lands — once
/// one exists, add an `assetPath` param here and swap this fallback for
/// `Image.asset(assetPath, width: size, height: size, fit: BoxFit.cover)`;
/// no other card code needs to change.
class _IllustrationPlaceholder extends StatelessWidget {
  const _IllustrationPlaceholder({required this.icon, required this.tint});

  static const double size = 104;

  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        width: size,
        height: size,
        color: tint.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: Icon(icon, size: 46, color: tint.withValues(alpha: 0.4)),
      ),
    );
  }
}

class _RoleCard extends StatefulWidget {
  const _RoleCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.title,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.selected
                  ? AppColors.accentRose.withValues(alpha: 0.3)
                  : AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: widget.selected
                    ? AppColors.primaryMaroon
                    : Colors.transparent,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.maroonShadow,
                  blurRadius: widget.selected ? 18 : 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _IllustrationPlaceholder(
                      icon: widget.icon,
                      tint: widget.accent,
                    ),
                    Positioned(
                      top: -8,
                      left: -8,
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: widget.accent,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          boxShadow: [
                            BoxShadow(
                              color: widget.accent.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(widget.icon, color: Colors.white, size: 19),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontSize: 18, color: AppColors.inkText),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: AppColors.mutedText, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: widget.selected
                      ? Container(
                          key: const ValueKey('selected'),
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryMaroon,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        )
                      : Container(
                          key: const ValueKey('unselected'),
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.backgroundCream,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.mutedText,
                            size: 20,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrustFooter extends StatelessWidget {
  const _TrustFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.accentRose.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Image.asset('assets/images/security_icon.png', height: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Your data is '),
                  TextSpan(
                    text: 'secure',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(
                    text: ' with us.\nWe verify to keep our community ',
                  ),
                  TextSpan(
                    text: 'safe',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: AppColors.mutedText, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
