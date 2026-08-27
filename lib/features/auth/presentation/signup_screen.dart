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
import '../domain/auth_models.dart';
import 'widgets/campus_picker_field.dart';
import 'widgets/validated_field.dart';

class SignupArgs {
  const SignupArgs({
    required this.name,
    required this.contact,
    required this.accountType,
    required this.campus,
    this.classOrGrade,
  });
  final String name;
  final String contact;
  final AccountType accountType;
  final Campus campus;
  final String? classOrGrade;
}

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key, required this.accountType});
  final AccountType accountType;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _classController = TextEditingController();
  final _nameFieldKey = GlobalKey<ValidatedFieldState>();
  final _contactFieldKey = GlobalKey<ValidatedFieldState>();
  Campus? _campus;
  String? _campusError;
  bool _agreedToTerms = false;
  bool _submitting = false;

  bool get _isStudent => widget.accountType == AccountType.student;
  bool get _isRestaurant => widget.accountType == AccountType.restaurant;

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _classController.dispose();
    super.dispose();
  }

  String? _validateName(String value) {
    if (value.trim().length < 2) return 'Enter your full name.';
    return null;
  }

  String? _validateContact(String value) {
    if (_isStudent) {
      final valid = RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$').hasMatch(value);
      return valid ? null : 'Enter a valid school email address.';
    }
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 ? null : 'Enter a valid phone number.';
  }

  Future<void> _continue() async {
    final nameOk = _nameFieldKey.currentState?.validateNow() ?? false;
    final contactOk = _contactFieldKey.currentState?.validateNow() ?? false;
    final campus = _campus;
    setState(
      () => _campusError = campus == null ? 'Choose your campus.' : null,
    );
    if (!_agreedToTerms) {
      ref
          .read(appNotificationProvider.notifier)
          .warning('Please agree to the Terms and Privacy Policy to continue.');
    }
    if (!nameOk || !contactOk || campus == null || !_agreedToTerms) return;

    final args = SignupArgs(
      name: _nameController.text.trim(),
      contact: _isStudent
          ? _contactController.text.trim()
          : '+234${_contactController.text.replaceAll(RegExp(r'\D'), '')}',
      accountType: widget.accountType,
      campus: campus,
      classOrGrade: _isStudent && _classController.text.trim().isNotEmpty
          ? _classController.text.trim()
          : null,
    );

    // Students land on a dedicated "verify your email" moment first — it
    // sends the code and hands off to the same boxed-code entry runners
    // use. Runners keep the original one-tap flow: send immediately and
    // go straight to code entry (that flow stays exactly as built).
    if (_isStudent) {
      context.push(AppRoutes.verifyEmail, extra: args);
      return;
    }

    setState(() => _submitting = true);
    await ref.read(authControllerProvider.notifier).sendOtp(args.contact);
    if (!mounted) return;
    setState(() => _submitting = false);
    context.push(AppRoutes.otp, extra: args);
  }

  void _showPolicy(String title) {
    ref.read(appNotificationProvider.notifier).info('$title — coming soon.');
  }

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;

    var stagger = 0;
    Widget staggered(Widget child) {
      final delay = Duration(milliseconds: 60 * stagger++);
      return child
          .animate()
          .fadeIn(delay: delay, duration: 240.ms)
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
                  center: const Alignment(-0.7, -0.9),
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CircleIconButton(
                    icon: Icons.arrow_back_rounded,
                    semanticLabel: 'Back',
                    onTap: () => context.pop(),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isStudent
                        ? 'Create account'
                        : _isRestaurant
                        ? 'Set up your business account'
                        : 'Set up your runner account',
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(color: onBg),
                  ).animate().fadeIn(duration: 300.ms).moveY(begin: 8, end: 0),
                  const SizedBox(height: 6),
                  Text(
                    _isStudent
                        ? "We'll verify your student email — no ID upload needed."
                        : _isRestaurant
                        ? "We'll verify your phone, then get your business details."
                        : "We'll verify your ID and a selfie match after this.",
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: secondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _HeroBadge(
                    icon: _isStudent
                        ? Icons.school_rounded
                        : _isRestaurant
                        ? Icons.storefront_rounded
                        : Icons.badge_rounded,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  staggered(
                    ValidatedField(
                      key: _nameFieldKey,
                      controller: _nameController,
                      hintText: 'Full name',
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 20, right: 12),
                        child: Icon(
                          Icons.person_rounded,
                          size: 22,
                          color: AppColors.primaryMaroon,
                        ),
                      ),
                      validator: _validateName,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  staggered(
                    _isStudent
                        ? ValidatedField(
                            key: _contactFieldKey,
                            controller: _contactController,
                            hintText: 'School email address',
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon: const Padding(
                              padding: EdgeInsets.only(left: 20, right: 12),
                              child: Icon(
                                Icons.mail_rounded,
                                size: 22,
                                color: AppColors.primaryMaroon,
                              ),
                            ),
                            validator: _validateContact,
                          )
                        : ValidatedField(
                            key: _contactFieldKey,
                            controller: _contactController,
                            hintText: 'Phone number',
                            keyboardType: TextInputType.phone,
                            leadingText: '+234',
                            prefixIcon: const Padding(
                              padding: EdgeInsets.only(left: 4, right: 4),
                              child: Icon(
                                Icons.phone_rounded,
                                size: 20,
                                color: AppColors.primaryMaroon,
                              ),
                            ),
                            validator: _validateContact,
                          ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_isStudent) ...[
                    staggered(
                      ValidatedField(
                        controller: _classController,
                        hintText: 'Class / grade (optional)',
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 20, right: 12),
                          child: Icon(
                            Icons.grade_rounded,
                            size: 22,
                            color: AppColors.primaryMaroon,
                          ),
                        ),
                        validator: (_) => null,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  staggered(
                    CampusPickerField(
                      selected: _campus,
                      errorText: _campusError,
                      onChanged: (campus) => setState(() {
                        _campus = campus;
                        _campusError = null;
                      }),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  staggered(
                    GestureDetector(
                      onTap: () =>
                          setState(() => _agreedToTerms = !_agreedToTerms),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _RoundedCheckbox(checked: _agreedToTerms),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'I agree to the ',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: secondary),
                                ),
                                GestureDetector(
                                  onTap: () => _showPolicy('Terms of Service'),
                                  child: Text(
                                    'Terms',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: AppColors.primaryMaroon,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                Text(
                                  ' and ',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: secondary),
                                ),
                                GestureDetector(
                                  onTap: () => _showPolicy('Privacy Policy'),
                                  child: Text(
                                    'Privacy Policy',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: AppColors.primaryMaroon,
                                          fontWeight: FontWeight.w700,
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
                  const SizedBox(height: AppSpacing.xl),
                  staggered(
                    PrimaryButton(
                      label: _isStudent ? 'Create Account' : 'Continue',
                      loading: _submitting,
                      onPressed: _continue,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: secondary),
                        ),
                        GestureDetector(
                          onTap: () => context.go(AppRoutes.login),
                          child: Text(
                            'Log in',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: AppColors.primaryMaroon,
                                  fontWeight: FontWeight.w700,
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
        ],
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

/// Compact placeholder for the small dimensional accent graphic below the
/// title — a real 3D render can drop in later; for now a tinted, elevated
/// icon badge gives the top of the screen visual weight instead of
/// jumping straight from title text to form fields.
class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentRose, AppColors.accentRoseDeep],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppElevation.raised(false),
      ),
      child: Icon(icon, color: AppColors.primaryMaroon, size: 30),
    );
  }
}

class _RoundedCheckbox extends StatelessWidget {
  const _RoundedCheckbox({required this.checked});
  final bool checked;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: checked ? AppColors.primaryMaroon : AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(7),
        border: checked ? null : Border.all(color: AppColors.borderSubtle),
        boxShadow: checked
            ? [
                BoxShadow(
                  color: AppColors.primaryMaroonGlow,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : AppElevation.card(false),
      ),
      alignment: Alignment.center,
      child: AnimatedScale(
        scale: checked ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
      ),
    );
  }
}
