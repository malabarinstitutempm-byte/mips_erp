class Exam {
  final int? id;
  final String name;
  final int academicYearId;
  final int courseId;
  final int batchId;
  final String? periodType; // 'semester' or 'year'
  final int? periodNo;
  final String? overrideReason;
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
    this.periodType,
    this.periodNo,
    this.overrideReason,
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

  String get periodDisplay {
    if (periodType == 'year' && periodNo != null) return 'Year $periodNo';
    if (periodType == 'semester' && periodNo != null) return 'Semester $periodNo';
    if (semester != null && semester!.isNotEmpty) return semester!;
    if (periodNo != null) return 'Period $periodNo';
    return 'General';
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'academic_year_id': academicYearId,
      'course_id': courseId,
      'batch_id': batchId,
      'period_type': periodType,
      'period_no': periodNo,
      if (overrideReason != null) 'override_reason': overrideReason,
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

    int? pNo = (map['period_no'] as num?)?.toInt();
    String? pType = map['period_type']?.toString();
    final sem = map['semester']?.toString();

    if (pNo == null && sem != null) {
      final match = RegExp(r'\d+').firstMatch(sem);
      if (match != null) pNo = int.tryParse(match.group(0)!);
    }
    pType ??= (pNo != null ? 'semester' : null);

    return Exam(
      id: (map['id'] as num?)?.toInt(),
      name: (map['name'] ?? '').toString(),
      academicYearId: (map['academic_year_id'] as num?)?.toInt() ?? 1,
      courseId: (map['course_id'] as num).toInt(),
      batchId: (map['batch_id'] as num).toInt(),
      periodType: pType,
      periodNo: pNo,
      overrideReason: map['override_reason']?.toString(),
      semester: sem ?? (pNo != null ? (pType == 'year' ? 'Year $pNo' : 'Semester $pNo') : null),
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
