// lib/features/attendance/attendance_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/repositories/interfaces/attendance_admin_repository_interface.dart';
import '../../core/repositories/supabase/supabase_attendance_admin_repository.dart';

final attendanceAdminRepositoryProvider = Provider<AttendanceAdminRepository>(
  (ref) => SupabaseAttendanceAdminRepository(),
);

// Filter state for Shortage & Low Attendance report
class AttendanceFilterState {
  final int? courseId;
  final int? batchId;
  final int? semesterNo;
  final String band; // 'all', 'shortage', 'low', 'ok'

  AttendanceFilterState({
    this.courseId,
    this.batchId,
    this.semesterNo,
    this.band = 'all',
  });

  AttendanceFilterState copyWith({
    int? courseId,
    int? batchId,
    int? semesterNo,
    String? band,
    bool clearCourse = false,
    bool clearBatch = false,
    bool clearSemester = false,
  }) {
    return AttendanceFilterState(
      courseId: clearCourse ? null : (courseId ?? this.courseId),
      batchId: clearBatch ? null : (batchId ?? this.batchId),
      semesterNo: clearSemester ? null : (semesterNo ?? this.semesterNo),
      band: band ?? this.band,
    );
  }
}

final attendanceFilterProvider = StateProvider<AttendanceFilterState>((ref) => AttendanceFilterState());

// Shortage & Low Attendance Report Provider
final shortageReportProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(attendanceAdminRepositoryProvider);
  final filter = ref.watch(attendanceFilterProvider);

  return await repo.getShortageReport(
    courseId: filter.courseId,
    batchId: filter.batchId,
    semesterNo: filter.semesterNo,
    band: filter.band,
  );
});

// Unmarked Sessions for Today Provider
final unmarkedSessionsTodayProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(attendanceAdminRepositoryProvider);
  return await repo.getUnmarkedSlots(DateTime.now());
});

// Attendance Settings Provider
final attendanceSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(attendanceAdminRepositoryProvider);
  return await repo.getAttendanceSettings();
});

// Today's Attendance Slot Status Provider (for Dashboard Board)
final todayAttendanceSlotStatusProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(attendanceAdminRepositoryProvider);
  return await repo.getAttendanceSlotStatus(DateTime.now());
});

// Review Sessions Filter & Provider
final reviewSessionsDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final attendanceReviewSessionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(attendanceAdminRepositoryProvider);
  final date = ref.watch(reviewSessionsDateProvider);
  return await repo.getAttendanceSessions(date: date);
});
