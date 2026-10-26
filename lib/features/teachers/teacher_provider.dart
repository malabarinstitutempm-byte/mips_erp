import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/teacher.dart';
import '../../core/repositories/interfaces/teacher_admin_repository_interface.dart';
import '../../core/repositories/supabase/supabase_teacher_admin_repository.dart';

final teacherAdminRepositoryProvider = Provider<TeacherAdminRepository>((ref) {
  return SupabaseTeacherAdminRepository();
});

final teachersListProvider = FutureProvider.autoDispose<List<Teacher>>((ref) async {
  final repo = ref.watch(teacherAdminRepositoryProvider);
  return repo.getTeachers();
});

final teacherSearchQueryProvider = StateProvider<String>((ref) => '');

// Filter: 'All' | 'Active' | 'Inactive' | 'Locked'
final teacherStatusFilterProvider = StateProvider<String>((ref) => 'All');

final filteredTeachersProvider = Provider<AsyncValue<List<Teacher>>>((ref) {
  final teachersAsync = ref.watch(teachersListProvider);
  final query = ref.watch(teacherSearchQueryProvider).trim().toLowerCase();
  final filter = ref.watch(teacherStatusFilterProvider);

  return teachersAsync.whenData((teachers) {
    return teachers.where((teacher) {
      // 1. Status Filter
      if (filter == 'Active') {
        if (teacher.effectiveStatus != 'Active') return false;
      } else if (filter == 'Inactive') {
        if (teacher.effectiveStatus != 'Inactive') return false;
      } else if (filter == 'Locked') {
        if (teacher.effectiveStatus != 'Locked') return false;
      }

      // 2. Search Query (Name, Phone, or Username)
      if (query.isNotEmpty) {
        final nameMatch = teacher.name.toLowerCase().contains(query);
        final userMatch = teacher.loginUsername.toLowerCase().contains(query);
        final phoneMatch = (teacher.phone ?? '').toLowerCase().contains(query);
        if (!nameMatch && !userMatch && !phoneMatch) return false;
      }

      return true;
    }).toList();
  });
});

final teacherDetailProvider = FutureProvider.family<Teacher?, int>((ref, teacherId) async {
  final repo = ref.watch(teacherAdminRepositoryProvider);
  return repo.getTeacherById(teacherId);
});

final teacherSessionsProvider = FutureProvider.family<List<Map<String, dynamic>>, int>((ref, teacherId) async {
  final repo = ref.watch(teacherAdminRepositoryProvider);
  return repo.getTeacherSessions(teacherId);
});

final teacherAuditHistoryProvider = FutureProvider.family<List<Map<String, dynamic>>, ({int teacherId, String? userId})>((ref, arg) async {
  final repo = ref.watch(teacherAdminRepositoryProvider);
  return repo.getTeacherAuditHistory(arg.teacherId, userId: arg.userId);
});
