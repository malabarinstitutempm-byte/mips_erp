class StudentRecordType {
  final int? id;
  final String name;
  final String category;
  final String? description;
  final bool isRequired;
  final bool allowMultiple;
  final String allowedExtensions;
  final bool isSystem;
  final bool isActive;
  final int sortOrder;

  StudentRecordType({
    this.id,
    required this.name,
    required this.category,
    this.description,
    this.isRequired = false,
    this.allowMultiple = false,
    this.allowedExtensions = 'pdf,jpg,jpeg,png',
    this.isSystem = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'category': category,
      'description': description,
      'is_required': isRequired ? 1 : 0,
      'allow_multiple': allowMultiple ? 1 : 0,
      'allowed_extensions': allowedExtensions,
      'is_system': isSystem ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'sort_order': sortOrder,
    };
  }

  factory StudentRecordType.fromMap(Map<String, dynamic> map) {
    return StudentRecordType(
      id: map['id'],
      name: map['name'],
      category: map['category'],
      description: map['description'],
      isRequired: (map['is_required'] ?? 0) == 1,
      allowMultiple: (map['allow_multiple'] ?? 0) == 1,
      allowedExtensions: map['allowed_extensions'] ?? 'pdf,jpg,jpeg,png',
      isSystem: (map['is_system'] ?? 0) == 1,
      isActive: (map['is_active'] ?? 1) == 1,
      sortOrder: map['sort_order'] ?? 0,
    );
  }
}
