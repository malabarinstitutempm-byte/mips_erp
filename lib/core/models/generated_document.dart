class GeneratedDocument {
  final int? id;
  final int studentId;
  final int templateId;
  final String date;
  final String? filePath;
  final String? documentNumber;

  GeneratedDocument({
    this.id,
    required this.studentId,
    required this.templateId,
    required this.date,
    this.filePath,
    this.documentNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'student_id': studentId,
      'template_id': templateId,
      'date': date,
      'file_path': filePath,
      if (documentNumber != null) 'document_number': documentNumber,
    };
  }

  factory GeneratedDocument.fromMap(Map<String, dynamic> map) {
    return GeneratedDocument(
      id: map['id'],
      studentId: map['student_id'],
      templateId: map['template_id'],
      date: map['date'],
      filePath: map['file_path'],
      documentNumber: map['document_number'],
    );
  }
}

