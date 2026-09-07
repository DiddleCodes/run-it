import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/maroon_wave_backdrop.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/route_line.dart';
import '../application/auth_controller.dart';
import 'signup_screen.dart';

/// The dedicated moment between "Create Account" and code entry, for
/// students only — confirms the email that will receive the code and
/// sends it on tap, rather than firing silently the instant the signup
/// form is submitted. Runners skip this: their flow sends immediately and
/// goes straight to [OtpScreen], unchanged.
///
/// Task 27: this screen only ever *displays* [widget.args.contact] — the
/// student typed it back on [SignupScreen], which is where the real-time
/// campus-domain check (`ValidatedField.asyncValidator`) actually lives.
/// This screen has no editable field of its own to attach one to.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.args});
  final SignupArgs args;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _sending = false;

  /// Task 26: this is where a real backend rejection actually surfaces —
  /// an unrecognized school email domain now fails right here, at
  /// requestOtp, before any code is ever sent. Previously unguarded
  /// entirely (this screen assumed sendOtp always succeeded), which would
  /// have left the button stuck loading forever on a real rejection
  /// instead of showing the backend's own honest message.
  Future<void> _sendCode() async {
    // Task 59: a rapid double-tap can dispatch a second onTap before the
    // rebuild that disables PrimaryButton lands (setState here is
    // synchronous on this field, but the *widget rebuild* that swaps in
    // a disabled onTap closure is not) — this guard reads the same
    // synchronously-updated field to block real re-entry regardless of
    // whether the button has visually disabled itself yet.
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .sendOtp(widget.args.contact, accountType: widget.args.accountType);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ref.read(appNotificationProvider.notifier).error(e.message);
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ref
          .read(appNotificationProvider.notifier)
          .error(
            "Couldn't reach the server. Check your connection and try again.",
          );
      return;
    }
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
            // Task 57: normal Column flow, not an absolutely-positioned
            // Stack overlay, and content top-anchored in normal flow (not
            // the two Spacers this screen used to center it) — see
            // welcome_back_screen.dart's identical comment for why this
            // structurally can't overlap the content above it. Task 59:
            // CustomScrollView + SliverFillRemaining(hasScrollBody: false),
            // not a plain scroll view — Task 58 made the accent a small
            // fixed size but left it trailing the content in normal flow,
            // so on a tall screen/short content it floated with dead cream
            // space below it instead of sitting at the actual bottom edge.
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: AppSpacing.sm),
                        _CircleIconButton(
                          icon: Icons.arrow_back_rounded,
                          onTap: () => context.pop(),
                        ),
                        const SizedBox(height: AppSpacing.xl),
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
                              borderRadius: BorderRadius.circular(
                                AppRadius.input,
                              ),
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
                        const SizedBox(height: AppSpacing.xl),
                        staggered(
                          PrimaryButton(
                            label: 'Send code',
                            loading: _sending,
                            onPressed: _sendCode,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Task 58: a small, fixed-size accent, not a space-filling
                // block — this is a task-focused form screen with no
                // secondary content to justify claiming the rest of the
                // screen; the "Send code" button should stay the dominant
                // thing here. Task 59: pinned to the actual bottom of the
                // remaining space via Align instead of just trailing the
                // content in normal flow.
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xl),
                      child: const MaroonAccentStrip(),
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
