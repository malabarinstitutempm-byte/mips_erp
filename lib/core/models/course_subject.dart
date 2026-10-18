class CourseSubject {
  final int? id;
  final int courseId;
  final String? semester;
  final String subjectName;
  final String? subjectCode;
  final double maxMarks;
  final double passMarks;

  CourseSubject({
    this.id,
    required this.courseId,
    this.semester,
    required this.subjectName,
    this.subjectCode,
    required this.maxMarks,
    required this.passMarks,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'course_id': courseId,
      if (semester != null) 'semester': semester,
      'name': subjectName,
      'subject_name': subjectName,
      if (subjectCode != null) 'code': subjectCode,
      if (subjectCode != null) 'subject_code': subjectCode,
      'max_marks': maxMarks,
      'pass_marks': passMarks,
    };
  }

  factory CourseSubject.fromMap(Map<String, dynamic> map) {
    return CourseSubject(
      id: (map['id'] as num?)?.toInt(),
      courseId: (map['course_id'] as num).toInt(),
      semester: map['semester']?.toString(),
      subjectName: (map['name'] ?? map['subject_name'] ?? '').toString(),
      subjectCode: (map['code'] ?? map['subject_code'])?.toString(),
      maxMarks: (map['max_marks'] as num?)?.toDouble() ?? 100.0,
      passMarks: (map['pass_marks'] as num?)?.toDouble() ?? 40.0,
    );
  }
}
