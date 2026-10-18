// lib/core/models/student_enrollment.dart

class StudentEnrollment {
  final int id;
  final int studentId;
  final int courseId;
  final int batchId;
  final String kind; // 'primary' or 'skill'
  final String enrolledOn;
  final String status; // 'active' or 'withdrawn'
  final String? courseName;
  final String? batchName;
  final String? createdAt;

  StudentEnrollment({
    required this.id,
    required this.studentId,
    required this.courseId,
    required this.batchId,
    required this.kind,
    required this.enrolledOn,
    this.status = 'active',
    this.courseName,
    this.batchName,
    this.createdAt,
  });

  factory StudentEnrollment.fromMap(Map<String, dynamic> map) {
    return StudentEnrollment(
      id: map['id'] is int ? map['id'] : int.parse(map['id'].toString()),
      studentId: map['student_id'] is int ? map['student_id'] : int.parse(map['student_id'].toString()),
      courseId: map['course_id'] is int ? map['course_id'] : int.parse(map['course_id'].toString()),
      batchId: map['batch_id'] is int ? map['batch_id'] : int.parse(map['batch_id'].toString()),
      kind: map['kind'] ?? 'primary',
      enrolledOn: map['enrolled_on']?.toString() ?? '',
      status: map['status'] ?? 'active',
      courseName: map['courses'] != null ? map['courses']['name'] : map['course_name'],
      batchName: map['batches'] != null ? (map['batches']['batch_name'] ?? map['batches']['name']) : map['batch_name'],
      createdAt: map['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'student_id': studentId,
      'course_id': courseId,
      'batch_id': batchId,
      'kind': kind,
      'enrolled_on': enrolledOn,
      'status': status,
    };
  }
}
