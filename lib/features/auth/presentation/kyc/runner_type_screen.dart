import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../application/kyc_flow_controller.dart';

/// Independent Rider's accent doesn't exist anywhere else yet, so it stays
/// a local gold rather than a shared token — same convention as the
/// role-select screen's runner gold.

/// Shown once, right after Biometric Setup, for runners only — the
/// answer here decides which ID types [KycCaptureScreen] accepts and
/// whether it includes a vehicle step.
class RunnerTypeScreen extends ConsumerStatefulWidget {
  const RunnerTypeScreen({super.key});

  @override
  ConsumerState<RunnerTypeScreen> createState() => _RunnerTypeScreenState();
}

class _RunnerTypeScreenState extends ConsumerState<RunnerTypeScreen> {
  RunnerType? _selected;

  void _select(RunnerType type) {
    if (_selected == type) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = type);
  }

  void _continue() {
    final type = _selected;
    if (type == null) return;
    HapticFeedback.mediumImpact();
    ref.read(kycFlowProvider.notifier).setRunnerType(type);
    context.go(AppRoutes.kycIntro);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.accentRoseDeep,
                            AppColors.primaryMaroon,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryMaroon.withValues(
                              alpha: 0.3,
                            ),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.two_wheeler_rounded,
                        color: AppColors.onMaroon,
                        size: 34,
                      ),
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 260.ms)
                  .scale(begin: const Offset(.85, .85)),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'How will you be\ndelivering?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(color: AppColors.inkText),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "This determines what we'll need to verify.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedText),
              ),
              const SizedBox(height: AppSpacing.xl),
              _RunnerCard(
                icon: Icons.school_rounded,
                accent: AppColors.primaryMaroon,
                title: "I'm a Student Runner",
                description: 'Deliver between classes, using your student ID.',
                selected: _selected == RunnerType.studentRunner,
                onTap: () => _select(RunnerType.studentRunner),
              ),
              const SizedBox(height: AppSpacing.md),
              _RunnerCard(
                icon: Icons.pedal_bike_rounded,
                accent: AppColors.gold,
                title: "I'm an Independent Rider",
                description: 'Bike or keke rider, campus deliveries only.',
                selected: _selected == RunnerType.independentRider,
                onTap: () => _select(RunnerType.independentRider),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                onPressed: _selected == null ? null : _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunnerCard extends StatefulWidget {
  const _RunnerCard({
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
  State<_RunnerCard> createState() => _RunnerCardState();
}

class _RunnerCardState extends State<_RunnerCard> {
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
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: widget.selected
                  ? widget.accent.withValues(alpha: 0.08)
                  : AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: widget.selected ? widget.accent : AppColors.borderSubtle,
                width: widget.selected ? 2 : 1,
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
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(widget.icon, color: widget.accent, size: 26),
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
                            ?.copyWith(fontSize: 17, color: AppColors.inkText),
                      ),
                      const SizedBox(height: 3),
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
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: widget.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        )
                      : Container(
                          key: const ValueKey('unselected'),
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.backgroundCream,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.mutedText,
                            size: 18,
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
