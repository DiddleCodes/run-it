import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/app_spinner.dart';
import '../application/auth_controller.dart';
import 'otp_screen.dart';
import 'widgets/passcode_pad.dart';

/// After this many consecutive wrong passcode attempts, entry locks out
/// briefly — a lightweight client-side throttle (no such rate-limit exists
/// anywhere else in the passcode logic yet) rather than letting someone
/// hammer the keypad indefinitely.
const _maxAttemptsBeforeLockout = 5;
const _lockoutDuration = Duration(seconds: 30);

/// Returning-student login: a native-feeling passcode pad (same dots +
/// keypad as the Set Passcode step) is the default credential, with a
/// biometric shortcut offered alongside it — both in the keypad itself and
/// as a dedicated button — when this device has one enrolled. Passcode
/// entry is always present — biometrics are a shortcut on top of it, never
/// a replacement, so a failed/unavailable biometric check is never a dead
/// end.
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
  bool _biometricAuthenticating = false;

  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  Timer? _lockoutTicker;
  Duration _lockoutRemaining = Duration.zero;

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

  bool get _lockedOut =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

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
    _lockoutTicker?.cancel();
    super.dispose();
  }

  void _startLockout() {
    _lockedUntil = DateTime.now().add(_lockoutDuration);
    _lockoutTicker?.cancel();
    _lockoutTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = _lockedUntil!.difference(DateTime.now());
      if (remaining.isNegative || remaining == Duration.zero) {
        timer.cancel();
        setState(() {
          _lockedUntil = null;
          _failedAttempts = 0;
          _lockoutRemaining = Duration.zero;
        });
      } else {
        setState(() => _lockoutRemaining = remaining);
      }
    });
    _lockoutRemaining = _lockoutDuration;
  }

  void _onDigit(String digit) {
    if (_submitting || _lockedOut || _digits.length >= passcodeLength) return;
    setState(() {
      _digits += digit;
      _error = false;
    });
    if (_digits.length == passcodeLength) _submit();
  }

  void _onBackspace() {
    if (_submitting || _lockedOut || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    bool ok;
    try {
      ok = await ref.read(authControllerProvider.notifier).loginWithPasscode(_digits);
    } on SessionRecoveryRequiredException {
      if (!mounted) return;
      setState(() => _submitting = false);
      await _recoverExpiredSession();
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ref
          .read(appNotificationProvider.notifier)
          .error("Couldn't reach the server. Check your connection and try again.");
      return;
    }
    if (!mounted) return;
    if (!ok) {
      _failedAttempts++;
      final lockingOut = _failedAttempts >= _maxAttemptsBeforeLockout;
      setState(() {
        _submitting = false;
        _error = true;
        _digits = '';
        if (lockingOut) _startLockout();
      });
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);
      return;
    }
    _failedAttempts = 0;
    _goToDestination();
  }

  Future<void> _useBiometric() async {
    if (_biometricAuthenticating || _submitting || _lockedOut) return;
    setState(() => _biometricAuthenticating = true);
    bool ok;
    try {
      ok = await ref.read(authControllerProvider.notifier).loginWithBiometric();
    } on SessionRecoveryRequiredException {
      if (!mounted) return;
      setState(() => _biometricAuthenticating = false);
      await _recoverExpiredSession();
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _biometricAuthenticating = false);
      ref
          .read(appNotificationProvider.notifier)
          .error("Couldn't reach the server. Check your connection and try again.");
      return;
    }
    if (!mounted) return;
    setState(() => _biometricAuthenticating = false);
    // A failed/cancelled biometric check just returns the user to passcode
    // entry — never a dead end.
    if (!ok) return;
    _failedAttempts = 0;
    _goToDestination();
  }

  Future<void> _onForgotPasscode() => _recoverViaOtp();

  /// Task 17: the same real-OTP-recovery flow "Forgot passcode?" already
  /// uses, also entered when [SessionRecoveryRequiredException] shows the
  /// passcode/biometric check was right but there's no still-valid
  /// persisted session to resume (it expired, or a suspension cleared it
  /// mid-session) — either way, only a fresh, real backend verification
  /// can produce a new one, never a retry of the same local credential.
  Future<void> _recoverExpiredSession() async {
    ref
        .read(appNotificationProvider.notifier)
        .error('Your session has ended. Please verify your code to continue.');
    await _recoverViaOtp();
  }

  Future<void> _recoverViaOtp() async {
    final auth = ref.read(authControllerProvider.notifier);
    final contact = await auth.storedPasscodeContact();
    final accountType = await auth.storedPasscodeAccountType();
    if (!mounted) return;
    if (contact == null || accountType == null) {
      ref
          .read(appNotificationProvider.notifier)
          .info('No saved account found on this device.');
      return;
    }
    await auth.sendOtp(contact, accountType: accountType);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OtpScreen.recovery(contact: contact, accountType: accountType),
      ),
    );
  }

  void _goToDestination() {
    final user = ref.read(authControllerProvider)?.user;
    if (user == null) return;
    context.go(postAuthDestination(user));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: Stack(
        children: [
          const Positioned.fill(child: _BottomBrandShape()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // This screen packs in a lot for one phone viewport — brand
                // header, welcome copy, dots, a full keypad, a divider, a
                // dedicated biometric button, and two footer links. Even at
                // "normal" heights there's no room for generous spacing, so
                // the rhythm here stays tight everywhere; `compact` only
                // shaves a little further for the very smallest phones.
                // `SingleChildScrollView` is the real overflow guard — for
                // large Dynamic Type scales or a genuinely tiny device.
                final compact = constraints.maxHeight < 640;
                final keySize = compact ? 56.0 : 60.0;
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _BrandHeader(),
                          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                          Center(
                            child: _WelcomeBlock(
                              filled: _digits.length,
                              error: _error,
                              lockedOut: _lockedOut,
                              lockoutRemaining: _lockoutRemaining,
                              shake: _shake,
                            ),
                          ),
                          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                          Center(
                            child: PasscodeKeypad(
                              onDigit: _onDigit,
                              onBackspace: _onBackspace,
                              enabled: !_submitting && !_lockedOut,
                              keySize: keySize,
                              biometricKey: _biometricEnrolled
                                  ? PasscodeBiometricKey(
                                      icon: _isFaceId
                                          ? Icons.face_retouching_natural_rounded
                                          : Icons.fingerprint_rounded,
                                      semanticLabel:
                                          'Sign in using device biometrics',
                                      onTap: _useBiometric,
                                    )
                                  : null,
                            ),
                          ),
                          if (_biometricEnrolled) ...[
                            SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
                            const _OrDivider(),
                            SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
                            _BiometricButton(
                              isFaceId: _isFaceId,
                              authenticating: _biometricAuthenticating,
                              enabled: !_submitting && !_lockedOut,
                              onTap: _useBiometric,
                            ),
                          ],
                          SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
                          Center(
                            child: GestureDetector(
                              onTap: _onForgotPasscode,
                              child: Text(
                                'Forgot passcode?',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: AppColors.inkText,
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                          SizedBox(height: AppSpacing.xs),
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
                                    style: Theme.of(context).textTheme.bodyMedium
                                        ?.copyWith(
                                          color: AppColors.gold,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryMaroon,
            borderRadius: BorderRadius.circular(13),
          ),
          // The real run-it. brand mark, not a generic Material bag icon —
          // matches the badge Task 5 already put on Home's header (Task
          // "Welcome Back redesign" Part B brand-badge sweep).
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              AppColors.onMaroon,
              BlendMode.srcIn,
            ),
            child: Image.asset(
              'assets/images/runit_icon_mark.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'run-it.',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: AppColors.inkText),
            ),
            Text(
              'Food your way',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.gold,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WelcomeBlock extends StatelessWidget {
  const _WelcomeBlock({
    required this.filled,
    required this.error,
    required this.lockedOut,
    required this.lockoutRemaining,
    required this.shake,
  });

  final int filled;
  final bool error;
  final bool lockedOut;
  final Duration lockoutRemaining;
  final Animation<double> shake;

  @override
  Widget build(BuildContext context) {
    final subtitle = lockedOut
        ? 'Too many attempts. Try again in ${lockoutRemaining.inSeconds}s.'
        : error
        ? 'Incorrect passcode. Try again.'
        : 'Enter your passcode to continue';

    return Column(
      children: [
        const Text('👋', style: TextStyle(fontSize: 30)),
        const SizedBox(height: 6),
        Text(
          'Welcome back!',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(color: AppColors.inkText),
        ).animate().fadeIn(duration: 300.ms).moveY(begin: 8, end: 0),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: Text(
            subtitle,
            key: ValueKey(subtitle),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: (error || lockedOut)
                  ? AppColors.error
                  : AppColors.mutedText,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AnimatedBuilder(
          animation: shake,
          builder: (context, child) =>
              Transform.translate(offset: Offset(shake.value, 0), child: child),
          child: PasscodeDots(filled: filled, hasError: error),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.borderSubtle)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.borderSubtle)),
      ],
    );
  }
}

class _BiometricButton extends StatefulWidget {
  const _BiometricButton({
    required this.isFaceId,
    required this.authenticating,
    required this.enabled,
    required this.onTap,
  });

  final bool isFaceId;
  final bool authenticating;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_BiometricButton> createState() => _BiometricButtonState();
}

class _BiometricButtonState extends State<_BiometricButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isFaceId
        ? 'Sign in with Face ID'
        : 'Sign in with Biometrics';
    final disabled = !widget.enabled || widget.authenticating;

    return Semantics(
      button: true,
      label: 'Sign in using device biometrics',
      enabled: !disabled,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: disabled ? null : widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppElevation.raised(false),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: widget.authenticating
                      ? const Center(
                          child: AppSpinner(
                            size: 22,
                            strokeWidth: 2.4,
                            color: AppColors.primaryMaroon,
                          ),
                        )
                      : Container(
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.accentRose,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.isFaceId
                                ? Icons.face_retouching_natural_rounded
                                : Icons.fingerprint_rounded,
                            color: AppColors.primaryMaroon,
                            size: 20,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successBackground,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'Fast & Secure',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
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

/// Decorative bottom brand shape, purely visual — [IgnorePointer] keeps it
/// from ever intercepting a tap meant for the controls above it. Sized off
/// [MediaQuery]'s height fraction (not fixed pixel dimensions) so it scales
/// and repositions sensibly from the smallest to the largest iPhone.
class _BottomBrandShape extends StatelessWidget {
  const _BottomBrandShape();

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.16;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipPath(
          clipper: _BrandShapeClipper(),
          child: Container(
            height: height,
            width: double.infinity,
            color: AppColors.primaryMaroon,
          ),
        ),
      ),
    );
  }
}

class _BrandShapeClipper extends CustomClipper<Path> {
  const _BrandShapeClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, size.height * 0.6)
      ..quadraticBezierTo(
        size.width * 0.5,
        -size.height * 0.5,
        size.width,
        size.height * 0.6,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
