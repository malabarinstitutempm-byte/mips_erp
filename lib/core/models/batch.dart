class Batch {
  final int? id;
  final int courseId;
  final String batchName;
  final String? startDate;
  final String? endDate;
  final int? startYear;
  final int? endYear;
  final int currentSemester;
  final String status;
  final String? completedOn;
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;
  final bool isDeleted;

  Batch({
    this.id,
    required this.courseId,
    required this.batchName,
    this.startDate,
    this.endDate,
    this.startYear,
    this.endYear,
    this.currentSemester = 1,
    this.status = 'active',
    this.completedOn,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.isDeleted = false,
  });

  /// Derived academic year: Year = ceil(semester / 2) -> (semester + 1) ~/ 2
  int get currentYear => (currentSemester <= 0 ? 1 : (currentSemester + 1) ~/ 2);

  Batch copyWith({
    int? id,
    int? courseId,
    String? batchName,
    String? startDate,
    String? endDate,
    int? startYear,
    int? endYear,
    int? currentSemester,
    String? status,
    String? completedOn,
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
    bool? isDeleted,
  }) {
    return Batch(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      batchName: batchName ?? this.batchName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      startYear: startYear ?? this.startYear,
      endYear: endYear ?? this.endYear,
      currentSemester: currentSemester ?? this.currentSemester,
      status: status ?? this.status,
      completedOn: completedOn ?? this.completedOn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'course_id': courseId,
      'batch_name': batchName,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      'current_semester': currentSemester,
      'status': status,
      if (completedOn != null) 'completed_on': completedOn,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
    };
  }

  factory Batch.fromMap(Map<String, dynamic> map) {
    final name = (map['name'] ?? map['batch_name'] ?? '').toString();
    final isDel = map['deleted_at'] != null || map['is_deleted'] == 1 || map['is_deleted'] == true;
    final sem = (map['current_semester'] as num?)?.toInt() ?? 1;

    return Batch(
      id: (map['id'] as num?)?.toInt(),
      courseId: (map['course_id'] as num).toInt(),
      batchName: name,
      startDate: map['start_date']?.toString(),
      endDate: map['end_date']?.toString(),
      startYear: (map['start_year'] as num?)?.toInt(),
      endYear: (map['end_year'] as num?)?.toInt(),
      currentSemester: sem < 1 ? 1 : sem,
      status: map['status']?.toString() ?? 'active',
      completedOn: map['completed_on']?.toString(),
      createdAt: map['created_at']?.toString(),
      updatedAt: map['updated_at']?.toString(),
      deletedAt: map['deleted_at']?.toString(),
      isDeleted: isDel,
    );
  }
}
