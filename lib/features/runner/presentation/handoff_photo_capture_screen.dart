import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/uploads_repository.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../auth/presentation/kyc/camera_capture_step.dart';

/// Task 30: the restaurant-to-runner handoff's own chain-of-custody photo
/// — required before pickup verification can complete
/// (`OrdersRepository.verifyPickup`'s own doc comment). Reuses
/// [CameraCaptureStep] (same component KYC's ID/selfie steps and
/// [DeliveryProofCaptureScreen] use) and the same presign-then-PUT upload
/// flow — this screen only captures + uploads and hands back the real
/// public URL; the caller (RunnerScanScreen) registers it together with
/// the pickup code in one `verifyPickup` call, since the backend requires
/// both at once.
class HandoffPhotoCaptureScreen extends ConsumerStatefulWidget {
  const HandoffPhotoCaptureScreen({super.key, required this.token});
  final String token;

  @override
  ConsumerState<HandoffPhotoCaptureScreen> createState() =>
      _HandoffPhotoCaptureScreenState();
}

class _HandoffPhotoCaptureScreenState
    extends ConsumerState<HandoffPhotoCaptureScreen> {
  bool _uploading = false;

  Future<void> _submit(Uint8List bytes) async {
    setState(() => _uploading = true);
    try {
      final publicUrl = await ref
          .read(uploadsRepositoryProvider)
          .uploadImage(
            bytes: bytes,
            purpose: 'handoff-photo',
            contentType: 'image/jpeg',
            token: widget.token,
          );
      if (!mounted) return;
      Navigator.of(context).pop(publicUrl);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ref
          .read(appNotificationProvider.notifier)
          .error(
            e is ApiException
                ? e.message
                : "Couldn't upload the handoff photo. Check your connection and try again.",
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Photo of sealed pack')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _uploading
              ? const Center(child: CircularProgressIndicator())
              : CameraCaptureStep(
                  title: 'Photo of the sealed pack',
                  subtitle:
                      'Required before pickup — shows the order as handed off by the restaurant.',
                  permissionRationale:
                      "We use your camera just for this photo — it's kept as part of this order's handoff record.",
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
