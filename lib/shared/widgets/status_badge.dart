import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

enum BadgeStatus { success, warning, danger, info, draft, neutral }

class StatusBadge extends StatelessWidget {
  final String text;
  final BadgeStatus status;

  StatusBadge({super.key, required this.text, required this.status});

  @override
  Widget build(BuildContext context) {
    Color tint;
    Color dark;

    switch (status) {
      case BadgeStatus.success:
        tint = AppColors.success.tint;
        dark = AppColors.success.dark;
        break;
      case BadgeStatus.warning:
        tint = AppColors.warning.tint;
        dark = AppColors.warning.dark;
        break;
      case BadgeStatus.danger:
        tint = AppColors.danger.tint;
        dark = AppColors.danger.dark;
        break;
      case BadgeStatus.neutral:
        tint = const Color(0xFFF1F5F9);
        dark = const Color(0xFF475569);
        break;
      case BadgeStatus.info:
      case BadgeStatus.draft:
        tint = AppColors.info.tint;
        dark = AppColors.info.dark;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: dark,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
