import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/maroon_wave_backdrop.dart';
import '../application/auth_controller.dart';
import '../domain/auth_models.dart';
import 'set_passcode_screen.dart';
import 'signup_screen.dart';

const _codeLength = 6;
const _resendWindow = Duration(seconds: 30);

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.args})
    : recoveryContact = null,
      recoveryAccountType = null;

  /// "Forgot passcode?" recovery mode: same boxed-code UI, but re-verifies
  /// an *existing* account's contact instead of registering a new one —
  /// pushed directly via `Navigator` from [WelcomeBackScreen] rather than
  /// through go_router's `otp` route, mirroring how Profile's "Change
  /// passcode" row reuses [SetPasscodeScreen] outside the router stack.
  const OtpScreen.recovery({
    super.key,
    required String contact,
    required AccountType accountType,
  }) : recoveryContact = contact,
       recoveryAccountType = accountType,
       args = null;

  final SignupArgs? args;
  final String? recoveryContact;
  final AccountType? recoveryAccountType;

  bool get isRecovery => recoveryContact != null;
  String get contact => isRecovery ? recoveryContact! : args!.contact;
  AccountType get accountType =>
      isRecovery ? recoveryAccountType! : args!.accountType;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _resendTimer;
  Duration _remaining = _resendWindow;
  bool _verifying = false;
  bool _verified = false;
  bool _autoSubmitted = false;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    _controller.addListener(_onCodeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _remaining = _resendWindow);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining.inSeconds <= 1) {
        timer.cancel();
        setState(() => _remaining = Duration.zero);
      } else {
        setState(() => _remaining -= const Duration(seconds: 1));
      }
    });
  }

  void _onCodeChanged() {
    final digits = _controller.text.replaceAll(RegExp(r'\D'), '');
    final clipped = digits.length > _codeLength
        ? digits.substring(0, _codeLength)
        : digits;
    if (clipped != _controller.text) {
      _controller.value = TextEditingValue(
        text: clipped,
        selection: TextSelection.collapsed(offset: clipped.length),
      );
      return; // listener re-fires with the corrected value
    }
    if (clipped.length == _codeLength && !_autoSubmitted) {
      _autoSubmitted = true;
      _submit();
    } else if (clipped.length < _codeLength) {
      _autoSubmitted = false;
    }
    setState(() {});
  }

  Future<void> _submit() async {
    setState(() => _verifying = true);
    try {
      if (widget.isRecovery) {
        final foundAccount = await ref
            .read(authControllerProvider.notifier)
            .recoverSessionForPasscodeReset(
              contact: widget.contact,
              code: _controller.text,
            );
        if (!foundAccount) {
          if (!mounted) return;
          setState(() => _verifying = false);
          ref
              .read(appNotificationProvider.notifier)
              .error("Couldn't find an account on this device.");
          _controller.clear();
          _autoSubmitted = false;
          return;
        }
      } else {
        await ref
            .read(authControllerProvider.notifier)
            .verifyOtpAndLogin(
              contact: widget.args!.contact,
              code: _controller.text,
              name: widget.args!.name,
              accountType: widget.args!.accountType,
              classOrGrade: widget.args!.classOrGrade,
              phone: widget.args!.phone,
            );
      }
    } on ApiException catch (e) {
      // The backend's own message ("Invalid or expired code") — deliberately
      // the same whether the code was simply wrong/expired or the account
      // is suspended, mirroring the dashboard login's identical convention.
      if (!mounted) return;
      setState(() => _verifying = false);
      ref.read(appNotificationProvider.notifier).error(e.message);
      _controller.clear();
      _autoSubmitted = false;
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _verifying = false);
      ref
          .read(appNotificationProvider.notifier)
          .error(
            "Couldn't reach the server. Check your connection and try again.",
          );
      _controller.clear();
      _autoSubmitted = false;
      return;
    }
    if (!mounted) return;
    setState(() => _verifying = false);
    setState(() => _verified = true);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;

    if (widget.isRecovery) {
      // Identity re-verified — hand off to the same Set Passcode screen
      // Profile's "Change passcode" row reuses, then unwind straight back
      // to Welcome Back once a new passcode is saved.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SetPasscodeScreen(isChangingExisting: true),
        ),
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // Every fresh signup — student or runner — sets a passcode next
    // (their real login credential) and gets the same optional
    // biometric-setup screen; only what comes after that differs by
    // account type (see postBiometricDestination in app_router.dart).
    context.go(AppRoutes.setPasscode);
  }

  Future<void> _resend() async {
    // Task 59: unlike _submit (only reachable through _onCodeChanged's
    // own synchronous _autoSubmitted guard), this is wired straight to
    // a TextButton, and _remaining doesn't change until this call
    // finishes — so a rapid double-tap while resend is available could
    // fire sendOtp twice before either request resolves. _resending is
    // read synchronously here, same fix as verify_email_screen's
    // _sendCode.
    if (_remaining > Duration.zero || _resending) return;
    setState(() => _resending = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .sendOtp(widget.contact, accountType: widget.accountType);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
    if (!mounted) return;
    ref.read(appNotificationProvider.notifier).info('New code sent.');
    _startResendTimer();
  }

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;
    final canResend = _remaining == Duration.zero && !_resending;

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      // Task 57: normal Column flow, not an absolutely-positioned Stack
      // overlay — see welcome_back_screen.dart's identical comment for why
      // this structurally can't overlap the content above it. Task 59:
      // CustomScrollView + SliverFillRemaining(hasScrollBody: false), not
      // a plain scroll view — Task 58 made the accent a small fixed size
      // but left it in normal flow right after the content, so on a tall
      // screen/short content it floated with dead cream space below it
      // instead of sitting at the actual bottom edge. SliverFillRemaining
      // reserves exactly whatever space is left after the content, and
      // Align(bottomCenter) pins the (still small, fixed-size) strip to
      // the bottom of that space — same "safe against unbounded height on
      // overflow" reasoning as welcome_back_screen.dart's footer.
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      // Pushed via a plain Navigator route (not go_router's own
                      // stack) in recovery mode — `context.pop()` would pop
                      // go_router's stack instead of this pushed route, same
                      // reasoning as SetPasscodeScreen's `isChangingExisting` back
                      // button.
                      onPressed: widget.isRecovery
                          ? () => Navigator.of(context).pop()
                          : () => context.pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(height: 4),
                    Text(
                          'Enter the code',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(color: onBg),
                        )
                        .animate()
                        .fadeIn(duration: 300.ms)
                        .moveY(begin: 8, end: 0),
                    const SizedBox(height: 6),
                    Text(
                      'Sent to ${widget.contact}',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: secondary),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    GestureDetector(
                      onTap: () => _focusNode.requestFocus(),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _OtpBoxes(
                            value: _controller.text,
                            hasFocus: _focusNode.hasFocus,
                            loading: _verifying,
                          ),
                          if (_verified)
                            const _SuccessCheck()
                                .animate()
                                .fadeIn(duration: 160.ms)
                                .scale(
                                  begin: const Offset(0.6, 0.6),
                                  curve: Curves.easeOutBack,
                                ),
                          Positioned.fill(
                            child: Opacity(
                              opacity: 0,
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                autofocus: true,
                                showCursor: false,
                                enableInteractiveSelection: true,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  counterText: '',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Center(
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(
                                begin: 1,
                                end:
                                    1 -
                                    _remaining.inMilliseconds /
                                        _resendWindow.inMilliseconds,
                              ),
                              duration: const Duration(milliseconds: 950),
                              curve: Curves.linear,
                              builder: (context, value, _) => SizedBox(
                                width: 120,
                                child: LinearProgressIndicator(
                                  value: canResend ? 1 : value,
                                  minHeight: 3,
                                  color: AppColors.primaryMaroon,
                                  backgroundColor: AppColors.borderSubtle,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: canResend ? _resend : null,
                            child: AnimatedSwitcher(
                              duration: AppMotion.fast,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                              child: Text(
                                // Text tracks _remaining alone (not _resending)
                                // so it reads "Resend code" for the in-flight
                                // request instead of flashing "0:00" — the
                                // TextButton itself is still correctly disabled
                                // via canResend.
                                _remaining == Duration.zero
                                    ? 'Resend code'
                                    : 'Resend in 0:${_remaining.inSeconds.toString().padLeft(2, '0')}',
                                key: ValueKey(
                                  _remaining == Duration.zero
                                      ? 'ready'
                                      : _remaining.inSeconds,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Task 58: a small, fixed-size accent, not a space-filling
            // block — this screen is a task-focused code entry with no
            // secondary content to justify claiming the rest of the
            // screen, and the space below it is mostly covered by the
            // system keyboard anyway once it's showing. Task 59: pinned
            // to the actual bottom of the remaining space via Align
            // instead of just trailing the content in normal flow.
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
    );
  }
}

class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes({
    required this.value,
    required this.hasFocus,
    required this.loading,
  });
  final String value;
  final bool hasFocus;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    const surface = AppColors.surfaceCard;
    const border = AppColors.borderSubtle;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_codeLength, (index) {
        final filled = index < value.length;
        final active = hasFocus && index == value.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: filled || active ? AppColors.primaryMaroon : border,
              width: filled || active ? 1.5 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.primaryMaroonGlow,
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: loading
              ? null
              : TweenAnimationBuilder<double>(
                  key: ValueKey(filled ? '$index-${value[index]}' : index),
                  tween: Tween(begin: filled ? 0.6 : 1, end: 1),
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Text(
                    filled ? value[index] : '',
                    style: AppTypography.mono(
                      fontSize: 22,
                      color: AppColors.primaryMaroon,
                    ),
                  ),
                ),
        );
      }),
    );
  }
}

/// Brief celebration badge shown over the boxes the instant a code
/// verifies, before handing off to the next screen — a beat of positive
/// feedback instead of an instant, silent cut.
class _SuccessCheck extends StatelessWidget {
  const _SuccessCheck();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryMaroon,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryMaroonGlow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.check_rounded,
        color: AppColors.onMaroon,
        size: 32,
      ),
    );
  }
}
