import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// A visual placeholder only — no entitlement/recurring-payment logic.
/// Real RUN-It Plus subscription/billing is out of scope for this task;
/// this screen exists purely so the Profile banner has somewhere real to
/// go instead of a dead tap.
class RunItPlusScreen extends StatelessWidget {
  const RunItPlusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.maroonShadow,
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    CupertinoIcons.xmark,
                    color: AppColors.inkText,
                    size: 18,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.gold, AppColors.primaryMaroonDeep],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.money_dollar_circle_fill,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'RUN-It Plus',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(color: AppColors.inkText),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Free delivery, exclusive deals, and more —\ncoming soon.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: AppColors.mutedText, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
