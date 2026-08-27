import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/route_line.dart';
import '../application/auth_controller.dart';
import 'signup_screen.dart';

/// The dedicated moment between "Create Account" and code entry, for
/// students only — confirms the email that will receive the code and
/// sends it on tap, rather than firing silently the instant the signup
/// form is submitted. Runners skip this: their flow sends immediately and
/// goes straight to [OtpScreen], unchanged.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.args});
  final SignupArgs args;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _sending = false;

  Future<void> _sendCode() async {
    setState(() => _sending = true);
    await ref
        .read(authControllerProvider.notifier)
        .sendOtp(widget.args.contact);
    if (!mounted) return;
    setState(() => _sending = false);
    ref
        .read(appNotificationProvider.notifier)
        .info('Code sent to ${widget.args.contact}.');
    context.push(AppRoutes.otp, extra: widget.args);
  }

  @override
  Widget build(BuildContext context) {
    final onBg = AppColors.inkText;
    final secondary = AppColors.mutedText;

    var stagger = 0;
    Widget staggered(Widget child) {
      final delay = Duration(milliseconds: 70 * stagger++);
      return child
          .animate()
          .fadeIn(delay: delay, duration: 260.ms)
          .moveY(begin: 10, end: 0);
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.8, -0.9),
                  radius: 1.4,
                  colors: [
                    AppColors.accentRose.withValues(alpha: 0.28),
                    AppColors.backgroundCream,
                  ],
                  stops: const [0.0, 0.8],
                ),
              ),
            ),
          ),
          const Positioned.fill(child: RouteLineBackdrop()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  _CircleIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => context.pop(),
                  ),
                  const Spacer(),
                  staggered(
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.accentRose,
                            AppColors.accentRoseDeep,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: AppElevation.raised(false),
                      ),
                      child: const Icon(
                        Icons.mark_email_read_rounded,
                        color: AppColors.primaryMaroon,
                        size: 34,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  staggered(
                    Text(
                      'Verify your\nstudent email',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(color: onBg),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  staggered(
                    Text(
                      'This confirms your campus eligibility — no ID upload needed.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: secondary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  staggered(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(color: AppColors.borderSubtle),
                        boxShadow: AppElevation.card(false),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.mail_rounded,
                            size: 22,
                            color: AppColors.primaryMaroon,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.args.contact,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: onBg),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  staggered(
                    PrimaryButton(
                      label: 'Send code',
                      loading: _sending,
                      onPressed: _sendCode,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
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
