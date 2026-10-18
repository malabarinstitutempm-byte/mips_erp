class Mark {
  final int? id;
  final int examId;
  final int subjectId;
  final int studentId;
  final double? marksObtained;
  final bool isAbsent;
  final String? grade;
  final String? status; // Pass, Fail, Absent
  final String? createdAt;
  final String? updatedAt;

  Mark({
    this.id,
    required this.examId,
    required this.subjectId,
    required this.studentId,
    this.marksObtained,
    this.isAbsent = false,
    this.grade,
    this.status,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'exam_id': examId,
      'subject_id': subjectId,
      'student_id': studentId,
      'marks_obtained': marksObtained,
      'is_absent': isAbsent,
      if (grade != null) 'grade': grade,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  factory Mark.fromMap(Map<String, dynamic> map) {
    final absent = map['is_absent'] == true || map['is_absent'] == 1 || map['status'] == 'Absent';

    return Mark(
      id: (map['id'] as num?)?.toInt(),
      examId: (map['exam_id'] as num).toInt(),
      subjectId: (map['subject_id'] as num).toInt(),
      studentId: (map['student_id'] as num).toInt(),
      marksObtained: (map['marks_obtained'] as num?)?.toDouble(),
      isAbsent: absent,
      grade: map['grade']?.toString(),
      status: map['status']?.toString() ?? (absent ? 'Absent' : 'Pass'),
      createdAt: map['created_at']?.toString(),
      updatedAt: map['updated_at']?.toString(),
    );
  }
}
