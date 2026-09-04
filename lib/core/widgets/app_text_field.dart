import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// A text field whose border blooms into a soft maroon glow on focus,
/// rather than the flat instant color swap Flutter gives you by default —
/// small detail, disproportionate amount of "premium" it buys back.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.hintText,
    this.leadingText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.autofocus = false,
    this.hasError = false,
    this.obscureText = false,
    this.onChanged,
    this.focusNode,
    this.maxLength,
    this.maxLines = 1,
  });

  final TextEditingController? controller;
  final String? hintText;
  final int? maxLength;
  final int? maxLines;

  /// Rendered as a permanently-visible label before the input (e.g. a
  /// country code) — unlike [InputDecoration.prefixText], which Material
  /// only reveals once the field has content, this stays put regardless.
  final String? leadingText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final bool autofocus;
  final bool hasError;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final _ownsFocusNode = widget.focusNode == null;
  late final _focusNode = widget.focusNode ?? FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: AppMotion.emphasized,
      decoration: BoxDecoration(
        // A faint top-to-bottom lightening reads as a raised/tactile
        // surface instead of a flat fill.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.6),
            AppColors.surfaceCard,
          ],
          stops: const [0.0, 0.4],
        ),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(
          color: widget.hasError
              ? AppColors.error
              : _focused
              ? AppColors.primaryMaroon
              : AppColors.borderSubtle,
          width: widget.hasError || _focused ? 1.5 : 1,
        ),
        boxShadow: _focused
            ? AppElevation.raised(false)
            : AppElevation.card(false),
      ),
      child: Row(
        children: [
          if (widget.leadingText != null) ...[
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentRose.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.leadingText!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.inkText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 1,
              height: 22,
              color: AppColors.borderSubtle,
            ),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              keyboardType: widget.keyboardType,
              obscureText: widget.obscureText,
              onChanged: widget.onChanged,
              maxLength: widget.maxLength,
              maxLines: widget.maxLines,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.inkText,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon: widget.prefixIcon,
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 0,
                  minHeight: 0,
                ),
                contentPadding: EdgeInsets.only(
                  left: widget.leadingText != null ? 10 : 20,
                  right: 20,
                  top: AppSpacing.ml,
                  bottom: AppSpacing.ml,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          if (widget.suffixIcon != null) ...[
            widget.suffixIcon!,
            const SizedBox(width: 16),
          ],
        ],
      ),
    );
  }
}
