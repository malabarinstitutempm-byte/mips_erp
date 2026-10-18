import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

class ProgressBar extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final Color color;
  final double height;
  final bool animate;

  ProgressBar({
    super.key,
    required this.progress,
    this.color = AppColors.brand,
    this.height = 8.0,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final targetWidth = constraints.maxWidth * progress.clamp(0.0, 1.0);
          
          Widget fill = Container(
            width: targetWidth,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          );
          
          if (animate) {
            fill = fill.animate().custom(
              duration: 800.ms,
              curve: Curves.easeOutCubic,
              builder: (context, val, child) {
                return Container(
                  width: targetWidth * val,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                );
              }
            );
          }
          
          return Align(
            alignment: Alignment.centerLeft,
            child: fill,
          );
        },
      ),
    );
  }
}
