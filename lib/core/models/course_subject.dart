class CourseSubject {
  final int? id;
  final int courseId;
  final int? periodNo;
  final String? semester;
  final String subjectName;
  final String? subjectCode;
  final double maxMarks;
  final double passMarks;

  CourseSubject({
    this.id,
    required this.courseId,
    this.periodNo,
    this.semester,
    required this.subjectName,
    this.subjectCode,
    required this.maxMarks,
    required this.passMarks,
  });

  CourseSubject copyWith({
    int? id,
    int? courseId,
    int? periodNo,
    String? semester,
    String? subjectName,
    String? subjectCode,
    double? maxMarks,
    double? passMarks,
  }) {
    return CourseSubject(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      periodNo: periodNo ?? this.periodNo,
      semester: semester ?? this.semester,
      subjectName: subjectName ?? this.subjectName,
      subjectCode: subjectCode ?? this.subjectCode,
      maxMarks: maxMarks ?? this.maxMarks,
      passMarks: passMarks ?? this.passMarks,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'course_id': courseId,
      'period_no': periodNo,
      if (semester != null) 'semester': semester,
      'subject_name': subjectName,
      if (subjectCode != null) 'subject_code': subjectCode,
      'max_marks': maxMarks,
      'pass_marks': passMarks,
    };
  }

  factory CourseSubject.fromMap(Map<String, dynamic> map) {
    int? parsedPeriodNo;
    if (map['period_no'] != null) {
      parsedPeriodNo = (map['period_no'] as num?)?.toInt();
    } else if (map['semester'] != null) {
      final s = map['semester'].toString();
      final match = RegExp(r'\d+').firstMatch(s);
      if (match != null) {
        parsedPeriodNo = int.tryParse(match.group(0)!);
      }
    }

    return CourseSubject(
      id: (map['id'] as num?)?.toInt(),
      courseId: (map['course_id'] as num).toInt(),
      periodNo: parsedPeriodNo,
      semester: map['semester']?.toString() ?? (parsedPeriodNo != null ? 'Semester $parsedPeriodNo' : null),
      subjectName: (map['name'] ?? map['subject_name'] ?? '').toString(),
      subjectCode: (map['code'] ?? map['subject_code'])?.toString(),
      maxMarks: (map['max_marks'] as num?)?.toDouble() ?? 100.0,
      passMarks: (map['pass_marks'] as num?)?.toDouble() ?? 40.0,
    );
  }
}
