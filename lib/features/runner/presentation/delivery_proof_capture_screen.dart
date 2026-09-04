import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/orders_repository.dart';
import '../../../core/network/uploads_repository.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/presentation/kyc/camera_capture_step.dart';

/// Task 11's fallback when PIN verification isn't possible (student's
/// phone unavailable) — reuses [CameraCaptureStep] (the same component
/// KYC's ID/selfie steps use) rather than building a second camera flow,
/// then presigns + uploads via Task 9's S3 flow and registers the result
/// against `/orders/:orderId/delivery-proof`. This never marks the order
/// delivered — see `OrdersRepository.submitDeliveryProof`'s doc comment —
/// it only flags it for manual review.
class DeliveryProofCaptureScreen extends ConsumerStatefulWidget {
  const DeliveryProofCaptureScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<DeliveryProofCaptureScreen> createState() =>
      _DeliveryProofCaptureScreenState();
}

class _DeliveryProofCaptureScreenState
    extends ConsumerState<DeliveryProofCaptureScreen> {
  bool _submitting = false;

  Future<void> _submit(Uint8List bytes) async {
    // Task 21b: the real signed-in runner's own token — same reasoning as
    // RunnerScanScreen._runnerToken's own doc comment. `EscrowPartyGuard`
    // requires it to belong to whoever actually claimed this order.
    final token = ref.read(authControllerProvider)?.accessToken;
    if (token == null) {
      ref
          .read(appNotificationProvider.notifier)
          .error('Your session has expired. Sign in again to continue.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final publicUrl = await ref
          .read(uploadsRepositoryProvider)
          .uploadImage(
            bytes: bytes,
            purpose: 'delivery-proof',
            contentType: 'image/jpeg',
            token: token,
          );
      await ref
          .read(ordersRepositoryProvider)
          .submitDeliveryProof(
            orderId: widget.orderId,
            photoUrl: publicUrl,
            token: token,
          );
      if (!mounted) return;
      ref
          .read(appNotificationProvider.notifier)
          .info('Photo submitted — this delivery is flagged for manual review.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ref
          .read(appNotificationProvider.notifier)
          .error(
            e is ApiException
                ? e.message
                : "Couldn't submit photo proof. Check your connection and try again.",
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery photo proof')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _submitting
              ? const Center(child: AppSpinner())
              : CameraCaptureStep(
                  title: 'Photo proof of delivery',
                  subtitle:
                      "Show the order at the student's door or drop-off point.",
                  permissionRationale:
                      "Used only to flag this delivery for manual review when the student's PIN can't be entered — it isn't stored anywhere except that review record.",
                  guide: CaptureGuide.document,
                  lensDirection: CameraLensDirection.back,
                  primaryActionLabel: 'Take Photo',
                  onCaptured: _submit,
                ),
        ),
      ),
    );
  }
}
