import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// A text field whose border blooms into a soft amber glow on focus,
/// rather than the flat instant color swap Flutter gives you by default —
/// small detail, disproportionate amount of "premium" it buys back.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.hintText,
    this.leadingText,
    this.prefixIcon,
    this.keyboardType,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController? controller;
  final String? hintText;

  /// Rendered as a permanently-visible label before the input (e.g. a
  /// country code) — unlike [InputDecoration.prefixText], which Material
  /// only reveals once the field has content, this stays put regardless.
  final String? leadingText;
  final Widget? prefixIcon;
  final TextInputType? keyboardType;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _focusNode = FocusNode();
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
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.emphasized,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceSunken,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _focused
              ? AppColors.amber
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: _focused ? 1.5 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.amber.withValues(alpha: 0.28),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Row(
        children: [
          if (widget.leadingText != null) ...[
            const SizedBox(width: 20),
            Text(
              widget.leadingText!,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 1,
              height: 22,
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              keyboardType: widget.keyboardType,
              onChanged: widget.onChanged,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
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
                  top: 18,
                  bottom: 18,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
