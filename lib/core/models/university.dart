class University {
  final int? id;
  final String name;
  final String? createdAt;
  final String? updatedAt;

  University({
    this.id,
    required this.name,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  factory University.fromMap(Map<String, dynamic> map) {
    return University(
      id: (map['id'] as num?)?.toInt(),
      name: (map['name'] ?? '').toString(),
      createdAt: map['created_at']?.toString(),
      updatedAt: map['updated_at']?.toString(),
    );
  }
}
