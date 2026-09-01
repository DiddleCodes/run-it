import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/uploads_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_notification.dart';
import '../../../../core/widgets/photo_capture_screen.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/presentation/widgets/validated_field.dart';
import '../../application/my_vendor_profile_controller.dart';
import '../../domain/vendor_dashboard_models.dart';
import 'category_picker_field.dart';

/// Business name / category / description / logo — the one form shared by
/// Task 12's first-run profile-completion screen and the Profile tab's own
/// "edit business info" (per the task's explicit "reuses the same form"
/// constraint), rather than two near-duplicate forms drifting apart.
///
/// Owns its own backend call (mirroring `PayoutAccountForm`'s shape):
/// [onSaved] only ever fires after a real, confirmed `POST /vendors/me`
/// succeeds — never optimistically.
class VendorProfileForm extends ConsumerStatefulWidget {
  const VendorProfileForm({
    super.key,
    this.initialBusinessName = '',
    this.initialCategory,
    this.initialDescription,
    this.initialLogoUrl,
    this.initialLogoBytes,
    this.submitLabel = 'Save',
    required this.onSaved,
  });

  final String initialBusinessName;
  final String? initialCategory;
  final String? initialDescription;
  final String? initialLogoUrl;

  /// A photo already captured (e.g. the wizard's storefront photo,
  /// Task 7) but not yet uploaded anywhere — treated exactly like a
  /// freshly-captured photo (uploaded on Save), so first-run setup never
  /// asks the restaurant to retake a photo it already gave.
  final Uint8List? initialLogoBytes;
  final String submitLabel;
  final ValueChanged<MyVendorProfile> onSaved;

  @override
  ConsumerState<VendorProfileForm> createState() => _VendorProfileFormState();
}

class _VendorProfileFormState extends ConsumerState<VendorProfileForm> {
  late final _nameController = TextEditingController(text: widget.initialBusinessName);
  late final _descriptionController = TextEditingController(text: widget.initialDescription ?? '');
  final _nameFieldKey = GlobalKey<ValidatedFieldState>();
  late String? _category = widget.initialCategory;
  String? _categoryError;
  late Uint8List? _newLogoBytes = widget.initialLogoBytes;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _captureLogo() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => const PhotoCaptureScreen(
          title: 'Business Photo',
          subtitle: 'Your logo or storefront — shown on your dashboard listing.',
          permissionRationale: "We use your camera just for this photo — it's only used for your listing.",
        ),
      ),
    );
    if (bytes != null && mounted) setState(() => _newLogoBytes = bytes);
  }

  Future<void> _save() async {
    final nameOk = _nameFieldKey.currentState?.validateNow() ?? false;
    final category = _category;
    setState(
      () => _categoryError = category == null ? 'Choose a category to continue.' : null,
    );
    if (!nameOk || category == null) return;

    setState(() => _saving = true);
    try {
      String? logoUrl = widget.initialLogoUrl;
      final bytes = _newLogoBytes;
      if (bytes != null) {
        final session = ref.read(authControllerProvider);
        // Task 9's presign flow is keyed on the caller's own token — a
        // restaurant account already has a real one via its own session,
        // same as the student/runner flows that call it.
        logoUrl = await ref
            .read(uploadsRepositoryProvider)
            .uploadImage(
              bytes: bytes,
              purpose: 'vendor-logo',
              contentType: 'image/jpeg',
              token: session?.accessToken ?? '',
            );
      }

      final saved = await ref
          .read(myVendorProfileProvider.notifier)
          .save(
            businessName: _nameController.text.trim(),
            category: category,
            description: _descriptionController.text.trim(),
            logoUrl: logoUrl,
          );
      if (!mounted) return;
      widget.onSaved(saved);
    } catch (e) {
      if (!mounted) return;
      ref
          .read(appNotificationProvider.notifier)
          .error("Couldn't save your business profile. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _LogoPicker(bytes: _newLogoBytes, url: widget.initialLogoUrl, onTap: _captureLogo)),
          const SizedBox(height: AppSpacing.xl),
          Text('Business name', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: onBg)),
          const SizedBox(height: AppSpacing.sm),
          ValidatedField(
            key: _nameFieldKey,
            controller: _nameController,
            hintText: "e.g. Mama Kemi's Kitchen",
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 20, right: 12),
              child: Icon(Icons.storefront_rounded, size: 22, color: AppColors.accentForest),
            ),
            validator: (value) => value.trim().length < 2 ? 'Enter your business name.' : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Category', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: onBg)),
          const SizedBox(height: AppSpacing.sm),
          CategoryPickerField(
            selected: _category,
            errorText: _categoryError,
            onChanged: (category) {
              HapticFeedback.selectionClick();
              setState(() {
                _category = category;
                _categoryError = null;
              });
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Description (optional)', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: onBg)),
          const SizedBox(height: AppSpacing.sm),
          ValidatedField(
            controller: _descriptionController,
            hintText: 'What should students know about you?',
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 20, right: 12),
              child: Icon(Icons.notes_rounded, size: 22, color: AppColors.accentForest),
            ),
            validator: (_) => null,
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(label: widget.submitLabel, onPressed: _saving ? null : _save, loading: _saving),
        ],
      ),
    );
  }
}

class _LogoPicker extends StatelessWidget {
  const _LogoPicker({required this.bytes, required this.url, required this.onTap});
  final Uint8List? bytes;
  final String? url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = 96.0;
    Widget content;
    if (bytes != null) {
      content = Image.memory(bytes!, width: size, height: size, fit: BoxFit.cover);
    } else if (url != null && url!.isNotEmpty) {
      content = CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (context, url, error) => const Icon(Icons.storefront_rounded, size: 34, color: AppColors.accentForest),
      );
    } else {
      content = const Icon(Icons.add_a_photo_rounded, size: 30, color: AppColors.accentForest);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accentForest.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(22), child: content),
      ),
    );
  }
}

