import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../application/auth_controller.dart';
import 'widgets/passcode_pad.dart';

enum _Phase { enter, confirm }

/// Shown right after OTP verification for every fresh signup — student or
/// runner — a native-feeling PIN entry (dot indicators + custom keypad,
/// not the system keyboard) that captures a 6-digit passcode twice and,
/// once they match, stores it as the user's persistent login credential
/// via [AuthController.setPasscode].
///
/// Also reused, unrouted (pushed directly via `Navigator`, not
/// `AppRoutes.setPasscode`), from Profile's "Change passcode" row — same
/// capture UI and [AuthController.setPasscode] call, but
/// [isChangingExisting] swaps the onboarding hand-off (which would
/// otherwise route an already-verified runner back into runner-type
/// selection) for a simple "saved, pop back to Profile" outcome.
class SetPasscodeScreen extends ConsumerStatefulWidget {
  const SetPasscodeScreen({super.key, this.isChangingExisting = false});

  final bool isChangingExisting;

  @override
  ConsumerState<SetPasscodeScreen> createState() => _SetPasscodeScreenState();
}

class _SetPasscodeScreenState extends ConsumerState<SetPasscodeScreen>
    with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.enter;
  String _firstPasscode = '';
  String _digits = '';
  bool _error = false;
  bool _submitting = false;

  late final _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final _shake = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 10.0, end: -6.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -6.0, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.linear));

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (_submitting || _digits.length >= passcodeLength) return;
    setState(() {
      _digits += digit;
      _error = false;
    });
    if (_digits.length == passcodeLength) _onComplete();
  }

  void _onBackspace() {
    if (_submitting || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Future<void> _onComplete() async {
    if (_phase == _Phase.enter) {
      _firstPasscode = _digits;
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      setState(() {
        _phase = _Phase.confirm;
        _digits = '';
      });
      return;
    }

    if (_digits != _firstPasscode) {
      setState(() => _error = true);
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (!mounted) return;
      setState(() {
        _digits = '';
        _error = false;
      });
      return;
    }

    setState(() => _submitting = true);
    final auth = ref.read(authControllerProvider.notifier);
    await auth.setPasscode(_digits);
    if (!mounted) return;

    if (widget.isChangingExisting) {
      ref.read(appNotificationProvider.notifier).success('Passcode updated.');
      Navigator.of(context).pop();
      return;
    }

    final accountType = ref.read(authControllerProvider)!.user.accountType;
    final biometricAvailable = await auth.isBiometricAvailable();
    if (!mounted) return;
    context.go(
      biometricAvailable
          ? AppRoutes.biometricSetup
          : postBiometricDestination(accountType),
    );
  }

  void _onBack() {
    if (_phase == _Phase.confirm) {
      setState(() {
        _phase = _Phase.enter;
        _firstPasscode = '';
        _digits = '';
        _error = false;
      });
    } else if (widget.isChangingExisting) {
      // Pushed via a plain Navigator route (not go_router's own stack) when
      // reused from Profile — `context.pop()` would pop go_router's stack
      // instead of this pushed route, so use the Navigator directly.
      Navigator.of(context).pop();
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final headline = _phase == _Phase.enter
        ? 'Create a 6-digit passcode'
        : 'Confirm your passcode';
    final subtitle = _phase == _Phase.enter
        ? "This is what you'll use to log back in."
        : _error
        ? "Those don't match — try again."
        : 'Re-enter it to confirm.';

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.sm),
              _CircleIconButton(icon: Icons.arrow_back_rounded, onTap: _onBack),
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: Text(
                        headline,
                        key: ValueKey(_phase),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(color: AppColors.inkText),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: Text(
                        subtitle,
                        key: ValueKey('$_phase-$_error'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _error ? AppColors.error : AppColors.mutedText,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AnimatedBuilder(
                      animation: _shake,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(_shake.value, 0),
                        child: child,
                      ),
                      child: PasscodeDots(
                        filled: _digits.length,
                        hasError: _error,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Center(
                child: PasscodeKeypad(
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  enabled: !_submitting,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
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
    ).animate().fadeIn(duration: 260.ms);
  }
}
