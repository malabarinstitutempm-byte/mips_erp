import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

class AppStepper extends StatelessWidget {
  final List<String> steps;
  final int currentStep;

  const AppStepper({
    super.key,
    required this.steps,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(steps.length * 2 - 1, (index) {
        if (index % 2 != 0) {
          // Divider
          final stepIndex = index ~/ 2;
          final isPast = stepIndex < currentStep;
          return Expanded(
            child: Container(
              height: 2,
              color: isPast ? AppColors.brand : AppColors.border,
            ),
          );
        }

        // Step
        final stepIndex = index ~/ 2;
        final isActive = stepIndex == currentStep;
        final isPast = stepIndex < currentStep;
        
        Color bgColor;
        Color textColor;
        if (isActive) {
          bgColor = AppColors.brand;
          textColor = Colors.white;
        } else if (isPast) {
          bgColor = AppColors.brandTint;
          textColor = AppColors.brandDark;
        } else {
          bgColor = AppColors.bg;
          textColor = AppColors.textMuted;
        }

        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive || isPast ? AppColors.brand : AppColors.border,
            ),
          ),
          child: Center(
            child: Text(
              '${stepIndex + 1}',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }),
    );
  }
}
