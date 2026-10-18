// lib/core/models/timetable.dart

class Timetable {
  final int id;
  final int batchId;
  final String title;
  final String status; // 'draft', 'published', 'archived'
  final String effectiveFrom;
  final String? publishedAt;
  final String? batchName;
  final String? courseName;
  final List<TimetableEntry> entries;

  Timetable({
    required this.id,
    required this.batchId,
    required this.title,
    this.status = 'draft',
    required this.effectiveFrom,
    this.publishedAt,
    this.batchName,
    this.courseName,
    this.entries = const [],
  });

  bool get isPublished => status == 'published';

  factory Timetable.fromMap(Map<String, dynamic> map, [List<TimetableEntry> entries = const []]) {
    return Timetable(
      id: map['id'] is int ? map['id'] : int.parse(map['id'].toString()),
      batchId: map['batch_id'] is int ? map['batch_id'] : int.parse(map['batch_id'].toString()),
      title: map['title'] ?? '',
      status: map['status'] ?? 'draft',
      effectiveFrom: map['effective_from']?.toString() ?? '',
      publishedAt: map['published_at']?.toString(),
      batchName: map['batches'] != null ? (map['batches']['batch_name'] ?? map['batches']['name']) : map['batch_name'],
      courseName: map['batches'] != null && map['batches']['courses'] != null
          ? map['batches']['courses']['name']
          : map['course_name'],
      entries: entries,
    );
  }
}

class TimetableEntry {
  final int id;
  final int timetableId;
  final int weekday; // 1 = Monday ... 6 = Saturday
  final String slot; // 'morning', 'evening'
  final String startTime;
  final String endTime;
  final int? subjectId;
  final int? teacherId;
  final String? room;
  final String? subjectName;
  final String? teacherName;

  TimetableEntry({
    required this.id,
    required this.timetableId,
    required this.weekday,
    required this.slot,
    required this.startTime,
    required this.endTime,
    this.subjectId,
    this.teacherId,
    this.room,
    this.subjectName,
    this.teacherName,
  });

  factory TimetableEntry.fromMap(Map<String, dynamic> map) {
    return TimetableEntry(
      id: map['id'] is int ? map['id'] : int.parse(map['id'].toString()),
      timetableId: map['timetable_id'] is int ? map['timetable_id'] : int.parse(map['timetable_id'].toString()),
      weekday: map['weekday'] is int ? map['weekday'] : int.parse(map['weekday'].toString()),
      slot: map['slot'] ?? 'morning',
      startTime: map['start_time']?.toString() ?? '09:00',
      endTime: map['end_time']?.toString() ?? '10:00',
      subjectId: map['subject_id'] != null ? (map['subject_id'] is int ? map['subject_id'] : int.tryParse(map['subject_id'].toString())) : null,
      teacherId: map['teacher_id'] != null ? (map['teacher_id'] is int ? map['teacher_id'] : int.tryParse(map['teacher_id'].toString())) : null,
      room: map['room']?.toString(),
      subjectName: map['course_subjects'] != null ? map['course_subjects']['name'] : map['subject_name'],
      teacherName: map['teachers'] != null ? map['teachers']['name'] : map['teacher_name'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id > 0) 'id': id,
      'timetable_id': timetableId,
      'weekday': weekday,
      'slot': slot,
      'start_time': startTime,
      'end_time': endTime,
      'subject_id': subjectId,
      'teacher_id': teacherId,
      'room': room,
    };
  }
}
