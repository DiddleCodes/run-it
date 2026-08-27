import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/auth_controller.dart';
import 'widgets/passcode_pad.dart';

/// Returning-student login: a native-feeling passcode pad (same dots +
/// keypad as the Set Passcode step) is the default credential, with a
/// biometric shortcut offered alongside it when this device has one
/// enrolled. Passcode entry is always present — biometrics are a shortcut
/// on top of it, never a replacement, so a failed/unavailable biometric
/// check is never a dead end.
class WelcomeBackScreen extends ConsumerStatefulWidget {
  const WelcomeBackScreen({super.key});

  @override
  ConsumerState<WelcomeBackScreen> createState() => _WelcomeBackScreenState();
}

class _WelcomeBackScreenState extends ConsumerState<WelcomeBackScreen>
    with SingleTickerProviderStateMixin {
  String _digits = '';
  bool _error = false;
  bool _submitting = false;
  bool _biometricEnrolled = false;
  bool _isFaceId = false;

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
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider.notifier);
    auth.hasBiometricCredential().then((enrolled) async {
      if (!enrolled || !mounted) return;
      final kinds = await auth.availableBiometrics();
      if (!mounted) return;
      setState(() {
        _biometricEnrolled = true;
        _isFaceId = kinds.contains(BiometricType.face);
      });
    });
  }

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
    if (_digits.length == passcodeLength) _submit();
  }

  void _onBackspace() {
    if (_submitting || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .loginWithPasscode(_digits);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _submitting = false;
        _error = true;
        _digits = '';
      });
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);
      return;
    }
    _goToDestination();
  }

  Future<void> _useBiometric() async {
    final ok = await ref
        .read(authControllerProvider.notifier)
        .loginWithBiometric();
    if (!mounted || !ok) return;
    _goToDestination();
  }

  void _goToDestination() {
    final user = ref.read(authControllerProvider)?.user;
    if (user == null) return;
    context.go(postAuthDestination(user));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryMaroon,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shopping_bag_rounded,
                      color: AppColors.onMaroon,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'run-it.',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: AppColors.inkText),
                  ),
                ],
              ),
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Text(
                          'Welcome back',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(color: AppColors.inkText),
                        )
                        .animate()
                        .fadeIn(duration: 300.ms)
                        .moveY(begin: 8, end: 0),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: Text(
                        _error
                            ? "That passcode didn't match."
                            : 'Enter your passcode to log in.',
                        key: ValueKey(_error),
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
                    if (_biometricEnrolled) ...[
                      const SizedBox(height: AppSpacing.lg),
                      GestureDetector(
                        onTap: _submitting ? null : _useBiometric,
                        child: Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accentRose,
                            shape: BoxShape.circle,
                            boxShadow: AppElevation.card(false),
                          ),
                          child: Icon(
                            _isFaceId
                                ? Icons.face_retouching_natural_rounded
                                : Icons.fingerprint_rounded,
                            color: AppColors.primaryMaroon,
                            size: 26,
                          ),
                        ),
                      ),
                    ],
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
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    Text(
                      'New here? ',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: AppColors.mutedText),
                    ),
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.accountType),
                      child: Text(
                        'Create an account',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
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
