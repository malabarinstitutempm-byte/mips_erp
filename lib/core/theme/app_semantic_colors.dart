import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Module + status colors, available anywhere via `context.semantic`.
///
/// Usage:
///   final c = context.semantic;
///   Container(color: c.fees.tint, child: Icon(Icons.x, color: c.fees.base));
///   Text('Paid', style: TextStyle(color: c.success.dark));
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  // Modules
  final ColorSet students;
  final ColorSet fees;
  final ColorSet exams;
  final ColorSet documents;
  final ColorSet courses;
  final ColorSet reports;
  final ColorSet settings;

  // Status
  final ColorSet success;
  final ColorSet warning;
  final ColorSet danger;
  final ColorSet info;

  const AppSemanticColors({
    required this.students,
    required this.fees,
    required this.exams,
    required this.documents,
    required this.courses,
    required this.reports,
    required this.settings,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  static const AppSemanticColors standard = AppSemanticColors(
    students: AppColors.students,
    fees: AppColors.fees,
    exams: AppColors.exams,
    documents: AppColors.documents,
    courses: AppColors.courses,
    reports: AppColors.reports,
    settings: AppColors.settings,
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.danger,
    info: AppColors.info,
  );

  @override
  AppSemanticColors copyWith({
    ColorSet? students,
    ColorSet? fees,
    ColorSet? exams,
    ColorSet? documents,
    ColorSet? courses,
    ColorSet? reports,
    ColorSet? settings,
    ColorSet? success,
    ColorSet? warning,
    ColorSet? danger,
    ColorSet? info,
  }) {
    return AppSemanticColors(
      students: students ?? this.students,
      fees: fees ?? this.fees,
      exams: exams ?? this.exams,
      documents: documents ?? this.documents,
      courses: courses ?? this.courses,
      reports: reports ?? this.reports,
      settings: settings ?? this.settings,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      students: ColorSet.lerp(students, other.students, t),
      fees: ColorSet.lerp(fees, other.fees, t),
      exams: ColorSet.lerp(exams, other.exams, t),
      documents: ColorSet.lerp(documents, other.documents, t),
      courses: ColorSet.lerp(courses, other.courses, t),
      reports: ColorSet.lerp(reports, other.reports, t),
      settings: ColorSet.lerp(settings, other.settings, t),
      success: ColorSet.lerp(success, other.success, t),
      warning: ColorSet.lerp(warning, other.warning, t),
      danger: ColorSet.lerp(danger, other.danger, t),
      info: ColorSet.lerp(info, other.info, t),
    );
  }
}

extension SemanticColorsX on BuildContext {
  AppSemanticColors get semantic =>
      Theme.of(this).extension<AppSemanticColors>() ??
      AppSemanticColors.standard;
}
