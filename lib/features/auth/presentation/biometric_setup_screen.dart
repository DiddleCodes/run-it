import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/auth_controller.dart';

/// Optional and skippable — offered once, right after a fresh signup (any
/// account type) sets their passcode. Declining costs nothing: passcode
/// entry is always available from the login screen, biometrics can be
/// turned on later.
class BiometricSetupScreen extends ConsumerStatefulWidget {
  const BiometricSetupScreen({super.key});

  @override
  ConsumerState<BiometricSetupScreen> createState() =>
      _BiometricSetupScreenState();
}

class _BiometricSetupScreenState extends ConsumerState<BiometricSetupScreen> {
  List<BiometricType> _kinds = const [];
  bool _enabling = false;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    ref.read(authControllerProvider.notifier).availableBiometrics().then((
      kinds,
    ) {
      if (mounted) setState(() => _kinds = kinds);
    });
  }

  bool get _isFace => _kinds.contains(BiometricType.face);

  String get _label => _isFace ? 'Enable Face ID' : 'Enable Touch ID';
  IconData get _icon => _isFace
      ? Icons.face_retouching_natural_rounded
      : Icons.fingerprint_rounded;

  Future<void> _enable() async {
    setState(() => _enabling = true);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .enableBiometric();
    if (!mounted) return;
    if (!ok) {
      setState(() => _enabling = false);
      ref
          .read(appNotificationProvider.notifier)
          .warning(
            "Couldn't verify biometrics — you can try again from your profile.",
          );
      return;
    }
    setState(() {
      _enabling = false;
      _enabled = true;
    });
    final accountType = ref.read(authControllerProvider)!.user.accountType;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    context.go(postBiometricDestination(accountType));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: _enabled
                    ? Container(
                        key: const ValueKey('done'),
                        width: 116,
                        height: 116,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryMaroon,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: AppColors.onMaroon,
                          size: 52,
                        ),
                      )
                    : Container(
                        key: const ValueKey('prompt'),
                        width: 116,
                        height: 116,
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
                          shape: BoxShape.circle,
                          boxShadow: AppElevation.raised(false),
                        ),
                        child: Icon(
                          _icon,
                          color: AppColors.primaryMaroon,
                          size: 52,
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                _enabled ? 'All set!' : 'Unlock faster next time',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(color: AppColors.inkText),
              ).animate().fadeIn(duration: 260.ms).moveY(begin: 8, end: 0),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _enabled
                    ? "You're ready to go."
                    : '${_isFace ? 'Face ID' : 'Touch ID'} is a faster, optional alternative to '
                          'typing your passcode — you can turn it on anytime from settings.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedText),
              ),
              const Spacer(),
              if (!_enabled) ...[
                PrimaryButton(
                  label: _label,
                  loading: _enabling,
                  onPressed: _enable,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () {
                    final accountType = ref
                        .read(authControllerProvider)!
                        .user
                        .accountType;
                    context.go(postBiometricDestination(accountType));
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.mutedText,
                  ),
                  child: const Text('Maybe later'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
