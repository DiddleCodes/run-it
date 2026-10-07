import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_spinner.dart';
import '../application/auth_controller.dart';

/// Every runner and restaurant sign-in passes through here: it fetches the
/// account's current review status from the backend, then sends it where
/// [destinationFor] says — so an approved runner never lands back in
/// verification just because this phone had no saved status.
class SignInGateScreen extends ConsumerStatefulWidget {
  const SignInGateScreen({super.key});

  @override
  ConsumerState<SignInGateScreen> createState() => _SignInGateScreenState();
}

class _SignInGateScreenState extends ConsumerState<SignInGateScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    setState(() => _failed = false);
    final ok = await ref.read(authControllerProvider.notifier).refreshProfile();
    if (!mounted) return;
    final user = ref.read(authControllerProvider)?.user;
    if (user == null) return; // signed out meanwhile — the router handles it
    if (!ok) {
      // Never guess: routing on an unknown status is how approved accounts
      // ended up back in verification.
      setState(() => _failed = true);
      return;
    }
    context.go(destinationFor(user));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: Center(
        child: _failed
            ? Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.mutedText),
                    const SizedBox(height: 12),
                    Text(
                      "Couldn't check your account",
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.inkText),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Check your connection and try again.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                    ),
                    const SizedBox(height: 16),
                    TextButton(onPressed: _check, child: const Text('Try again')),
                  ],
                ),
              )
            : const AppSpinner(),
      ),
    );
  }
}
