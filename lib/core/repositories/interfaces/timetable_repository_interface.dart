// lib/core/repositories/interfaces/timetable_repository_interface.dart

import '../../../core/models/timetable.dart';

abstract class TimetableRepository {
  Future<List<Timetable>> getTimetables(int batchId);

  Future<Timetable?> getPublishedTimetable(int batchId);

  Future<Timetable> createTimetable({
    required int batchId,
    required String title,
    required String effectiveFrom,
  });

  Future<List<TimetableEntry>> getTimetableEntries(int timetableId);

  Future<TimetableEntry> saveTimetableEntry(TimetableEntry entry);

  Future<void> deleteTimetableEntry(int entryId);

  Future<Map<String, dynamic>> publishTimetable(int timetableId);

  Future<Map<String, dynamic>> archiveTimetable(int timetableId);

  Future<String?> checkTeacherClash({
    required int teacherId,
    required int weekday,
    required String startTime,
    required String endTime,
    int? excludeEntryId,
  });

  Future<Timetable> copyTimetable({
    required int sourceTimetableId,
    required int targetBatchId,
    required String newTitle,
  });
}
