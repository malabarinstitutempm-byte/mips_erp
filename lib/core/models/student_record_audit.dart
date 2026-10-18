class StudentRecordAudit {
  final int? id;
  final int studentId;
  final String? recordId;
  final String action;
  final String? performedBy;
  final String performedAt;
  final String? details;

  StudentRecordAudit({
    this.id,
    required this.studentId,
    this.recordId,
    required this.action,
    this.performedBy,
    required this.performedAt,
    this.details,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'student_id': studentId,
      'record_id': recordId,
      'action': action,
      'performed_by': performedBy,
      'performed_at': performedAt,
      'details': details,
    };
  }

  factory StudentRecordAudit.fromMap(Map<String, dynamic> map) {
    return StudentRecordAudit(
      id: map['id'],
      studentId: map['student_id'],
      recordId: map['record_id'],
      action: map['action'],
      performedBy: map['performed_by'],
      performedAt: map['performed_at'],
      details: map['details'],
    );
  }
}
