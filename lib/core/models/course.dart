class Course {
  final int? id;
  final String name;
  final String code;
  final int? universityId;
  final String? duration;
  final double totalFee;
  final int totalFeePaise;
  final String courseType; // 'primary' or 'skill'
  final String structure; // 'semester', 'year', 'single'
  final String attendanceBasis; // 'semester', 'year', 'none'
  final String? description;
  final String status;
  final String? createdAt;
  final String? updatedAt;
  final bool isDeleted;

  Course({
    this.id,
    required this.name,
    required this.code,
    this.universityId,
    this.duration,
    this.totalFee = 0.0,
    this.totalFeePaise = 0,
    this.courseType = 'primary',
    String? structure,
    String? attendanceBasis,
    this.description,
    this.status = 'Active',
    this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
  })  : structure = structure ?? (courseType == 'skill' ? 'single' : 'semester'),
        attendanceBasis = attendanceBasis ?? (courseType == 'skill' ? 'none' : (structure ?? 'semester'));

  bool get isSemesterWise => structure == 'semester';
  bool get isYearWise => structure == 'year';
  bool get isSingle => structure == 'single';

  int get durationYears {
    if (duration == null) return 2;
    final match = RegExp(r'\d+').firstMatch(duration!);
    if (match != null) {
      final val = int.tryParse(match.group(0)!) ?? 2;
      return val > 0 ? val : 1;
    }
    return 2;
  }

  int get periodsCount {
    if (isSingle) return 1;
    if (isYearWise) return durationYears;
    return durationYears * 2;
  }

  String get periodTypeLabel {
    if (isYearWise) return 'Year';
    if (isSemesterWise) return 'Semester';
    return 'Period';
  }

  String periodName(int periodNo) {
    if (isSingle) return 'All Subjects';
    if (isYearWise) return 'Year $periodNo';
    return 'Semester $periodNo';
  }

  Map<String, dynamic> toMap() {
    final feePaise = totalFeePaise > 0 ? totalFeePaise : (totalFee * 100).round();
    return {
      if (id != null) 'id': id,
      'name': name,
      'code': code,
      'university_id': universityId,
      'duration': duration,
      'total_fee_paise': feePaise,
      'course_type': courseType,
      'structure': structure,
      'attendance_basis': attendanceBasis,
      'description': description,
      'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  factory Course.fromMap(Map<String, dynamic> map) {
    final cType = map['course_type'] ?? 'primary';
    final rawStructure = map['structure']?.toString();
    final struct = rawStructure ?? (cType == 'skill' ? 'single' : 'semester');
    final rawAttBasis = map['attendance_basis']?.toString();
    final attBasis = rawAttBasis ?? (struct == 'single' ? 'none' : struct);

    return Course(
      id: map['id'],
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      universityId: map['university_id'],
      duration: map['duration'],
      courseType: cType,
      structure: struct,
      attendanceBasis: attBasis,
      totalFeePaise: map['total_fee_paise'] is int
          ? map['total_fee_paise']
          : int.tryParse(map['total_fee_paise']?.toString() ?? '0') ??
              ((map['total_fee'] as num?)?.toDouble() ?? 0.0 * 100).toInt(),
      totalFee: (map['total_fee'] as num?)?.toDouble() ??
          ((map['total_fee_paise'] as num?)?.toDouble() ?? 0.0) / 100.0,
      description: map['description'],
      status: map['status'] ?? 'Active',
      createdAt: map['created_at'],
      updatedAt: map['updated_at'],
      isDeleted: map['is_deleted'] == 1 || map['deleted_at'] != null,
    );
  }
}
