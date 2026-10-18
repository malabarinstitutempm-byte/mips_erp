class AcademicYear {
  final int? id;
  final String yearName;
  final bool isCurrent;
  final String? createdAt;
  final String? updatedAt;

  AcademicYear({
    this.id,
    required this.yearName,
    this.isCurrent = false,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'year_name': yearName,
      'name': yearName,
      'is_current': isCurrent,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  factory AcademicYear.fromMap(Map<String, dynamic> map) {
    return AcademicYear(
      id: (map['id'] as num?)?.toInt(),
      yearName: (map['year_name'] ?? map['name'] ?? '').toString(),
      isCurrent: map['is_current'] == 1 || map['is_current'] == true,
      createdAt: map['created_at']?.toString(),
      updatedAt: map['updated_at']?.toString(),
    );
  }
}
