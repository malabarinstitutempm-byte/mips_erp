class Course {
  final int? id;
  final String name;
  final String code;
  final int? universityId;
  final String? duration;
  final double totalFee;
  final int totalFeePaise;
  final String courseType; // 'primary' or 'skill'
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
    this.description,
    this.status = 'Active',
    this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'code': code,
      'university_id': universityId,
      'duration': duration,
      'total_fee': totalFee,
      'total_fee_paise': totalFeePaise,
      'course_type': courseType,
      'description': description,
      'status': status,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Course.fromMap(Map<String, dynamic> map) {
    return Course(
      id: map['id'],
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      universityId: map['university_id'],
      duration: map['duration'],
      courseType: map['course_type'] ?? 'primary',
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

