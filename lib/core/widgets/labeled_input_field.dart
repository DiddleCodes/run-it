import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_text_field.dart';

/// [AppTextField] with a label rendered above it — the "Email", "Password"
/// style caption used on the login/create-account cream screens, as
/// opposed to the hint-only fields used elsewhere in the app.
class LabeledInputField extends StatelessWidget {
  const LabeledInputField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.hasError,
    this.onChanged,
    this.focusNode,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool? hasError;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    const labelColor = AppColors.mutedText;
    const iconColor = AppColors.mutedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: labelColor, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: controller,
          hintText: hintText,
          keyboardType: keyboardType,
          obscureText: obscureText,
          hasError: hasError ?? false,
          onChanged: onChanged,
          focusNode: focusNode,
          prefixIcon: prefixIcon == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 20, right: 12),
                  child: Icon(prefixIcon, size: 20, color: iconColor),
                ),
          suffixIcon: suffixIcon,
        ),
      ],
    );
  }
}
