import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/student.dart';
import '../../core/models/batch.dart';
import '../../core/repositories/interfaces/student_repository_interface.dart';
import '../../core/repositories/supabase/supabase_student_repository.dart';
import '../../core/services/supabase_service.dart';
import '../courses/course_provider.dart';

final studentRepositoryProvider = Provider<StudentRepository>((ref) => SupabaseStudentRepository());

final allBatchesProvider = FutureProvider.autoDispose<List<Batch>>((ref) async {
  final repo = ref.watch(batchRepositoryProvider);
  return repo.getBatches(includeCompleted: true);
});

final batchesMapProvider = FutureProvider.autoDispose<Map<int, Batch>>((ref) async {
  final batches = await ref.watch(allBatchesProvider.future);
  return {for (var b in batches) if (b.id != null) b.id!: b};
});

class StudentFilter {
  final String query;
  final int? courseId;
  final int? year;
  final String? status;
  final bool includeDeleted;
  final int page;
  final int pageSize;

  const StudentFilter({
    this.query = '',
    this.courseId,
    this.year,
    this.status = 'active',
    this.includeDeleted = false,
    this.page = 0,
    this.pageSize = 25,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudentFilter &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          courseId == other.courseId &&
          year == other.year &&
          status == other.status &&
          includeDeleted == other.includeDeleted &&
          page == other.page &&
          pageSize == other.pageSize;

  @override
  int get hashCode =>
      query.hashCode ^
      courseId.hashCode ^
      (year?.hashCode ?? 0) ^
      status.hashCode ^
      includeDeleted.hashCode ^
      page.hashCode ^
      pageSize.hashCode;
}

class StudentListResult {
  final List<Student> students;
  final int totalCount;

  const StudentListResult({
    required this.students,
    required this.totalCount,
  });
}

final studentListResultProvider = FutureProvider.family<StudentListResult, StudentFilter>((ref, filter) async {
  final client = SupabaseService.instance.client;
  try {
    final res = await client.rpc('get_admin_student_list', params: {
      'p_query': filter.query.trim().isEmpty ? null : filter.query.trim(),
      'p_course_id': filter.courseId,
      'p_batch_id': null,
      'p_status': filter.includeDeleted ? 'all' : filter.status,
      'p_limit': filter.pageSize,
      'p_offset': filter.page * filter.pageSize,
    });
    if (res is Map) {
      final totalCount = (res['total_count'] as num?)?.toInt() ?? 0;
      final rawList = res['students'] as List? ?? [];
      final students = rawList.map((item) => Student.fromMap(Map<String, dynamic>.from(item))).toList();
      return StudentListResult(students: students, totalCount: totalCount);
    }
  } catch (_) {
    // Fallback to separate queries if RPC is unavailable
  }

  final repo = ref.read(studentRepositoryProvider);
  final students = await repo.getStudents(
    query: filter.query.trim().isEmpty ? null : filter.query.trim(),
    courseId: filter.courseId,
    year: filter.year,
    status: filter.includeDeleted ? null : filter.status,
    includeDeleted: filter.includeDeleted,
    offset: filter.page * filter.pageSize,
    limit: filter.pageSize,
  );
  final totalCount = await repo.getStudentsCount(
    query: filter.query.trim().isEmpty ? null : filter.query.trim(),
    courseId: filter.courseId,
    year: filter.year,
    status: filter.includeDeleted ? null : filter.status,
    includeDeleted: filter.includeDeleted,
  );
  return StudentListResult(students: students, totalCount: totalCount);
});

final paginatedStudentsProvider = FutureProvider.family<List<Student>, StudentFilter>((ref, filter) async {
  final result = await ref.watch(studentListResultProvider(filter).future);
  return result.students;
});

final studentsTotalCountProvider = FutureProvider.family<int, StudentFilter>((ref, filter) async {
  final result = await ref.watch(studentListResultProvider(filter).future);
  return result.totalCount;
});

final studentsProvider = FutureProvider.family<List<Student>, String>((ref, query) async {
  final repo = ref.read(studentRepositoryProvider);
  return await repo.getStudents(query: query.isEmpty ? null : query);
});

final nextAdmissionNumberProvider = FutureProvider<String>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  return await repo.getNextAdmissionNumber();
});

final courseStudentsProvider = FutureProvider.family<List<Student>, int>((ref, courseId) async {
  final repo = ref.read(studentRepositoryProvider);
  return await repo.getStudents(courseId: courseId);
});
