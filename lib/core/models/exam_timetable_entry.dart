// lib/core/models/exam_timetable_entry.dart

class ExamTimetableEntry {
  final int id;
  final int examId;
  final String examName;
  final int batchId;
  final String batchName;
  final String subjectName;
  final String subjectCode;
  final String examDate;
  final String startTime;
  final String endTime;
  final String room;
  final String instructions;

  ExamTimetableEntry({
    required this.id,
    required this.examId,
    required this.examName,
    required this.batchId,
    required this.batchName,
    required this.subjectName,
    required this.subjectCode,
    required this.examDate,
    required this.startTime,
    required this.endTime,
    required this.room,
    this.instructions = 'Reporting time: 30 minutes before exam start. Hall ticket mandatory.',
  });

  factory ExamTimetableEntry.fromMap(Map<String, dynamic> map) {
    return ExamTimetableEntry(
      id: (map['id'] as num?)?.toInt() ?? 0,
      examId: (map['exam_id'] as num?)?.toInt() ?? 0,
      examName: map['exam_name'] as String? ?? 'Term Examination',
      batchId: (map['batch_id'] as num?)?.toInt() ?? 0,
      batchName: map['batch_name'] as String? ?? 'Primary Batch',
      subjectName: map['subject_name'] as String? ?? 'Subject',
      subjectCode: map['subject_code'] as String? ?? 'SUB101',
      examDate: map['exam_date'] as String? ?? '',
      startTime: map['start_time'] as String? ?? '10:00',
      endTime: map['end_time'] as String? ?? '13:00',
      room: map['room'] as String? ?? 'Exam Hall 1',
      instructions: map['instructions'] as String? ?? 'Reporting time: 30 minutes before exam start. Hall ticket mandatory.',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'exam_id': examId,
      'exam_name': examName,
      'batch_id': batchId,
      'batch_name': batchName,
      'subject_name': subjectName,
      'subject_code': subjectCode,
      'exam_date': examDate,
      'start_time': startTime,
      'end_time': endTime,
      'room': room,
      'instructions': instructions,
    };
  }

  ExamTimetableEntry copyWith({
    int? id,
    int? examId,
    String? examName,
    int? batchId,
    String? batchName,
    String? subjectName,
    String? subjectCode,
    String? examDate,
    String? startTime,
    String? endTime,
    String? room,
    String? instructions,
  }) {
    return ExamTimetableEntry(
      id: id ?? this.id,
      examId: examId ?? this.examId,
      examName: examName ?? this.examName,
      batchId: batchId ?? this.batchId,
      batchName: batchName ?? this.batchName,
      subjectName: subjectName ?? this.subjectName,
      subjectCode: subjectCode ?? this.subjectCode,
      examDate: examDate ?? this.examDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      room: room ?? this.room,
      instructions: instructions ?? this.instructions,
    );
  }
}
