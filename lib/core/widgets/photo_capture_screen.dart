import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../../features/auth/presentation/kyc/camera_capture_step.dart';

/// A thin, reusable wrapper around [CameraCaptureStep] for the common case
/// of "capture one photo, hand the bytes back to whoever pushed this
/// screen" — used by the Restaurant Dashboard for a vendor logo and a
/// menu-item photo (Task 12), where the actual upload happens later, on
/// the surrounding form's own Save action, not the instant a photo is
/// captured (unlike `DeliveryProofCaptureScreen`, which uploads
/// immediately since submitting the photo *is* the whole action there).
class PhotoCaptureScreen extends StatelessWidget {
  const PhotoCaptureScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.permissionRationale,
  });
  final String title;
  final String subtitle;
  final String permissionRationale;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: CameraCaptureStep(
            title: title,
            subtitle: subtitle,
            permissionRationale: permissionRationale,
            guide: CaptureGuide.document,
            lensDirection: CameraLensDirection.back,
            primaryActionLabel: 'Take Photo',
            onCaptured: (bytes) => Navigator.of(context).pop<Uint8List>(bytes),
          ),
        ),
      ),
    );
  }
}
