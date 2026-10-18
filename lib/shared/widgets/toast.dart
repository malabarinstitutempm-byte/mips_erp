import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

class Toast {
  static void show(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: isError ? AppColors.danger.dark : AppColors.textStrong,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: isError ? AppColors.danger.tint : AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: isError ? AppColors.danger.base : AppColors.border),
        ),
        margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
        elevation: 8,
      ),
    );
  }
}
