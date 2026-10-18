class Result {
  final int? id;
  final int examId;
  final int studentId;
  final double totalMarks;
  final double percentage;
  final String grade;
  final String status;
  final int? rank;
  final String? createdAt;
  final String? updatedAt;

  Result({
    this.id,
    required this.examId,
    required this.studentId,
    required this.totalMarks,
    required this.percentage,
    required this.grade,
    required this.status,
    this.rank,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'exam_id': examId,
      'student_id': studentId,
      'total_marks': totalMarks,
      'percentage': percentage,
      'grade': grade,
      'status': status,
      if (rank != null) 'rank': rank,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  factory Result.fromMap(Map<String, dynamic> map) {
    return Result(
      id: (map['id'] as num?)?.toInt(),
      examId: (map['exam_id'] as num).toInt(),
      studentId: (map['student_id'] as num).toInt(),
      totalMarks: (map['total_marks'] as num?)?.toDouble() ?? 0.0,
      percentage: (map['percentage'] as num?)?.toDouble() ?? 0.0,
      grade: (map['grade'] ?? 'F').toString(),
      status: (map['status'] ?? 'FAIL').toString(),
      rank: (map['rank'] as num?)?.toInt(),
      createdAt: map['created_at']?.toString(),
      updatedAt: map['updated_at']?.toString(),
    );
  }
}
