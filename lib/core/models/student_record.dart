class StudentRecord {
  final String id;
  final int studentId;
  final int recordTypeId;
  final String filePath;
  final String originalFilename;
  final String extension;
  final int sizeBytes;
  final String sha256;
  final String? documentNumber;
  final String? issueDate;
  final String? expiryDate;
  final String? notes;
  final String status;
  final String? replacedById;
  final String uploadedAt;
  final String? uploadedBy;

  StudentRecord({
    required this.id,
    required this.studentId,
    required this.recordTypeId,
    required this.filePath,
    required this.originalFilename,
    required this.extension,
    required this.sizeBytes,
    required this.sha256,
    this.documentNumber,
    this.issueDate,
    this.expiryDate,
    this.notes,
    this.status = 'current',
    this.replacedById,
    required this.uploadedAt,
    this.uploadedBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'student_id': studentId,
      'record_type_id': recordTypeId,
      'file_path': filePath,
      'original_filename': originalFilename,
      'extension': extension,
      'size_bytes': sizeBytes,
      'sha256': sha256,
      'document_number': documentNumber,
      'issue_date': issueDate,
      'expiry_date': expiryDate,
      'notes': notes,
      'status': status,
      'replaced_by_id': replacedById,
      'uploaded_at': uploadedAt,
      'uploaded_by': uploadedBy,
    };
  }

  factory StudentRecord.fromMap(Map<String, dynamic> map) {
    return StudentRecord(
      id: map['id'],
      studentId: map['student_id'],
      recordTypeId: map['record_type_id'],
      filePath: map['file_path'],
      originalFilename: map['original_filename'],
      extension: map['extension'],
      sizeBytes: map['size_bytes'],
      sha256: map['sha256'],
      documentNumber: map['document_number'],
      issueDate: map['issue_date'],
      expiryDate: map['expiry_date'],
      notes: map['notes'],
      status: map['status'] ?? 'current',
      replacedById: map['replaced_by_id'],
      uploadedAt: map['uploaded_at'],
      uploadedBy: map['uploaded_by'],
    );
  }
}
