import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class AppAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const AppAvatar({
    super.key,
    required this.name,
    this.radius = 20.0,
  });

  Color _getColorForName(String name) {
    // Generate a consistent color based on the name
    final hash = name.codeUnits.fold<int>(0, (prev, curr) => prev + curr);
    final colors = [
      AppColors.students.base,
      AppColors.fees.base,
      AppColors.exams.base,
      AppColors.courses.base,
      AppColors.reports.base,
    ];
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColorForName(name);
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';

    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withOpacity(0.15),
      child: Text(
        initial,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
