class Exam {
  final int? id;
  final String name;
  final int academicYearId;
  final int courseId;
  final int batchId;
  final String? semester;
  final String? examDate;
  final String? publishDate;
  final String status;
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;
  final bool isDeleted;

  Exam({
    this.id,
    required this.name,
    required this.academicYearId,
    required this.courseId,
    required this.batchId,
    this.semester,
    this.examDate,
    this.publishDate,
    this.status = 'draft',
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.isDeleted = false,
  });

  bool get isPublished => status.toLowerCase() == 'published';

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'academic_year_id': academicYearId,
      'course_id': courseId,
      'batch_id': batchId,
      if (semester != null) 'semester': semester,
      if (examDate != null) 'date': examDate,
      if (examDate != null) 'exam_date': examDate,
      if (publishDate != null) 'published_at': publishDate,
      if (publishDate != null) 'publish_date': publishDate,
      'status': status.toLowerCase(),
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
    };
  }

  factory Exam.fromMap(Map<String, dynamic> map) {
    final d = map['date'] ?? map['exam_date'];
    final pDate = map['published_at'] ?? map['publish_date'];
    final isDel = map['deleted_at'] != null || map['is_deleted'] == 1 || map['is_deleted'] == true;

    return Exam(
      id: (map['id'] as num?)?.toInt(),
      name: (map['name'] ?? '').toString(),
      academicYearId: (map['academic_year_id'] as num?)?.toInt() ?? 1,
      courseId: (map['course_id'] as num).toInt(),
      batchId: (map['batch_id'] as num).toInt(),
      semester: map['semester']?.toString(),
      examDate: d?.toString(),
      publishDate: pDate?.toString(),
      status: (map['status'] ?? 'draft').toString(),
      createdAt: map['created_at']?.toString(),
      updatedAt: map['updated_at']?.toString(),
      deletedAt: map['deleted_at']?.toString(),
      isDeleted: isDel,
    );
  }
}
