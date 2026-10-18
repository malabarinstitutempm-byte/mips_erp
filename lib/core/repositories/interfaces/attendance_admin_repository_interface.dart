abstract class AttendanceAdminRepository {
  Future<List<Map<String, dynamic>>> getAttendanceSessions({
    DateTime? date,
    int? batchId,
    int? subjectId,
    int? teacherId,
    String? status,
  });

  Future<List<Map<String, dynamic>>> getSessionRecords(int sessionId);

  Future<void> correctAttendanceRecord({
    required int recordId,
    required String newStatus,
    required String reason,
  });

  Future<List<Map<String, dynamic>>> getAttendanceChanges(int recordId);

  Future<List<Map<String, dynamic>>> getUnsubmittedSessionsToday();

  // Phase 4 & 12 additions:
  Future<Map<String, dynamic>?> getAttendanceSummary(int studentId, {int? enrollmentId, int? semesterNo});

  Future<List<Map<String, dynamic>>> getShortageReport({
    int? courseId,
    int? batchId,
    int? semesterNo,
    String? band, // 'all', 'shortage', 'low'
  });

  Future<List<Map<String, dynamic>>> getUnmarkedSlots(DateTime date);

  Future<Map<String, dynamic>> confirmNoClass({
    required int batchId,
    required DateTime date,
    required String slot,
    String? reason,
  });

  Future<Map<String, dynamic>> getAttendanceSettings();

  Future<void> updateAttendanceSettings(Map<String, dynamic> settings);

  Future<List<Map<String, dynamic>>> getAttendanceSlotStatus(DateTime date);
}
