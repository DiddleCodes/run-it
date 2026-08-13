import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_button.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phoneController = TextEditingController();
  bool _useEmail = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBg = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(height: 8),
              Text(
                'How can we reach you?',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: onBg),
              ).animate().fadeIn(duration: 300.ms).moveY(begin: 8, end: 0),
              const SizedBox(height: 6),
              Text(
                "We'll send a code to verify it's you.",
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: secondary),
              ).animate().fadeIn(delay: 80.ms, duration: 300.ms),
              const SizedBox(height: 32),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: _useEmail
                    ? AppTextField(
                        key: const ValueKey('email'),
                        hintText: 'Email address',
                        keyboardType: TextInputType.emailAddress,
                        autofocus: true,
                      )
                    : AppTextField(
                        key: const ValueKey('phone'),
                        controller: _phoneController,
                        hintText: 'Phone number',
                        keyboardType: TextInputType.phone,
                        leadingText: '+234',
                      ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _useEmail = !_useEmail),
                  child: Text(_useEmail ? 'Use phone instead' : 'Use email instead'),
                ),
              ),
              const Spacer(),
              Text.rich(
                TextSpan(
                  text: 'By continuing you agree to our ',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: secondary),
                  children: [
                    TextSpan(
                      text: 'Terms',
                      style: TextStyle(color: onBg, decoration: TextDecoration.underline),
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(color: onBg, decoration: TextDecoration.underline),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Continue',
                onPressed: () => context.go(AppRoutes.campusSelect),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
