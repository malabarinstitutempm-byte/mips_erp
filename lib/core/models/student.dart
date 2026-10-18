class Student {
  final int? id;
  final String? admissionNumber;
  final String? registrationNumber;
  final String name;
  final int? courseId;
  final int? batchId;
  final int? universityId;
  final String? dob;
  final String? gender;
  final String? phone;
  final String? email;
  final String? address;
  final String? admissionDate;
  final int? academicYearId;
  final String status;
  final String? completedOn;
  final String? profilePhotoPath;
  final String? profilePhotoThumbPath;
  final String? profilePhotoUpdatedAt;
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;
  final String? deletedBy;
  final bool isDeleted;
  final String? importId;

  Student({
    this.id,
    this.admissionNumber,
    this.registrationNumber,
    required this.name,
    this.courseId,
    this.batchId,
    this.universityId,
    this.dob,
    this.gender = 'Male',
    this.phone,
    this.email,
    this.address,
    this.admissionDate,
    this.academicYearId,
    this.status = 'active',
    this.completedOn,
    this.profilePhotoPath,
    this.profilePhotoThumbPath,
    this.profilePhotoUpdatedAt,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.deletedBy,
    this.isDeleted = false,
    this.importId,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (admissionNumber != null) 'admission_number': admissionNumber,
      if (registrationNumber != null) 'registration_number': registrationNumber,
      'name': name,
      if (courseId != null) 'course_id': courseId,
      if (batchId != null) 'batch_id': batchId,
      if (universityId != null) 'university_id': universityId,
      if (dob != null) 'dob': dob,
      if (gender != null) 'gender': gender,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (address != null) 'address': address,
      if (admissionDate != null) 'admission_date': admissionDate,
      if (academicYearId != null) 'academic_year_id': academicYearId,
      'status': status,
      if (completedOn != null) 'completed_on': completedOn,
      if (profilePhotoPath != null) 'profile_photo_path': profilePhotoPath,
      if (profilePhotoThumbPath != null) 'profile_photo_thumb_path': profilePhotoThumbPath,
      if (profilePhotoUpdatedAt != null) 'profile_photo_updated_at': profilePhotoUpdatedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (deletedBy != null) 'deleted_by': deletedBy,
      'is_deleted': isDeleted ? 1 : 0,
      if (importId != null) 'import_id': importId,
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    final isDel = map['deleted_at'] != null || map['is_deleted'] == 1 || map['is_deleted'] == true;

    return Student(
      id: (map['id'] as num?)?.toInt(),
      admissionNumber: map['admission_number']?.toString(),
      registrationNumber: map['registration_number']?.toString(),
      name: (map['name'] ?? '').toString(),
      courseId: (map['course_id'] as num?)?.toInt(),
      batchId: (map['batch_id'] as num?)?.toInt(),
      universityId: (map['university_id'] as num?)?.toInt(),
      dob: map['dob']?.toString(),
      gender: map['gender']?.toString() ?? 'Male',
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      address: map['address']?.toString(),
      admissionDate: map['admission_date']?.toString(),
      academicYearId: (map['academic_year_id'] as num?)?.toInt(),
      status: map['status']?.toString() ?? 'active',
      completedOn: map['completed_on']?.toString(),
      profilePhotoPath: map['profile_photo_path']?.toString(),
      profilePhotoThumbPath: map['profile_photo_thumb_path']?.toString(),
      profilePhotoUpdatedAt: map['profile_photo_updated_at']?.toString(),
      createdAt: map['created_at']?.toString(),
      updatedAt: map['updated_at']?.toString(),
      deletedAt: map['deleted_at']?.toString(),
      deletedBy: map['deleted_by']?.toString(),
      isDeleted: isDel,
      importId: map['import_id']?.toString(),
    );
  }

  Student copyWithPhoto({
    String? profilePhotoPath,
    String? profilePhotoThumbPath,
    String? profilePhotoUpdatedAt,
  }) {
    return Student(
      id: id,
      admissionNumber: admissionNumber,
      registrationNumber: registrationNumber,
      name: name,
      courseId: courseId,
      batchId: batchId,
      universityId: universityId,
      dob: dob,
      gender: gender,
      phone: phone,
      email: email,
      address: address,
      admissionDate: admissionDate,
      academicYearId: academicYearId,
      status: status,
      completedOn: completedOn,
      profilePhotoPath: profilePhotoPath ?? this.profilePhotoPath,
      profilePhotoThumbPath: profilePhotoThumbPath ?? this.profilePhotoThumbPath,
      profilePhotoUpdatedAt: profilePhotoUpdatedAt ?? this.profilePhotoUpdatedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      deletedBy: deletedBy,
      isDeleted: isDeleted,
      importId: importId,
    );
  }
}
