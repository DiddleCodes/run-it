import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';

/// A restaurant whose application is pending or was rejected — instead of
/// the dashboard (it can't take orders yet) or the application wizard (it
/// has already applied). While pending it checks back by itself and moves
/// on the moment Bridgit approves it.
class RestaurantApplicationStatusScreen extends ConsumerStatefulWidget {
  const RestaurantApplicationStatusScreen({super.key, this.pollInterval = const Duration(seconds: 6)});

  final Duration pollInterval;

  @override
  ConsumerState<RestaurantApplicationStatusScreen> createState() => _RestaurantApplicationStatusScreenState();
}

class _RestaurantApplicationStatusScreenState extends ConsumerState<RestaurantApplicationStatusScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(widget.pollInterval, (_) => _checkAgain());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkAgain() async {
    await ref.read(authControllerProvider.notifier).refreshProfile();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider)?.user;
    final status = user?.vendorStatus ?? VendorReviewStatus.pending;

    // Approved (or the status moved on some other way): go where it now belongs.
    if (user != null && status != VendorReviewStatus.pending && status != VendorReviewStatus.rejected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(destinationFor(user));
      });
    }

    final rejected = status == VendorReviewStatus.rejected;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (rejected ? AppColors.error : AppColors.warning).withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    rejected ? Icons.error_outline_rounded : Icons.hourglass_top_rounded,
                    size: 40,
                    color: rejected ? AppColors.error : AppColors.warning,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  rejected ? "Your application wasn't approved" : 'Your application is under review',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineMedium?.copyWith(color: AppColors.inkText),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  rejected
                      ? (user?.vendorRejectionReason?.isNotEmpty ?? false)
                            ? 'Reason: ${user!.vendorRejectionReason}'
                            : 'Update your details and send it again.'
                      : "We'll open your dashboard as soon as Bridgit approves your restaurant.",
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (rejected)
                  PrimaryButton(
                    label: 'Update and resubmit',
                    onPressed: () => context.go(AppRoutes.vendorApplication),
                  )
                else
                  TextButton(onPressed: _checkAgain, child: const Text('Check again')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
