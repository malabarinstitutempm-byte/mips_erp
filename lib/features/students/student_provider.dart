import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/student.dart';
import '../../core/models/batch.dart';
import '../../core/repositories/interfaces/student_repository_interface.dart';
import '../../core/repositories/supabase/supabase_student_repository.dart';
import '../courses/course_provider.dart';

final studentRepositoryProvider = Provider<StudentRepository>((ref) => SupabaseStudentRepository());

final allBatchesProvider = FutureProvider<List<Batch>>((ref) async {
  final repo = ref.watch(batchRepositoryProvider);
  return repo.getBatches(includeCompleted: true);
});

final batchesMapProvider = FutureProvider<Map<int, Batch>>((ref) async {
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

final paginatedStudentsProvider = FutureProvider.family<List<Student>, StudentFilter>((ref, filter) async {
  final repo = ref.read(studentRepositoryProvider);
  return await repo.getStudents(
    query: filter.query.trim().isEmpty ? null : filter.query.trim(),
    courseId: filter.courseId,
    year: filter.year,
    status: filter.includeDeleted ? null : filter.status,
    includeDeleted: filter.includeDeleted,
    offset: filter.page * filter.pageSize,
    limit: filter.pageSize,
  );
});

final studentsTotalCountProvider = FutureProvider.family<int, StudentFilter>((ref, filter) async {
  final repo = ref.read(studentRepositoryProvider);
  return await repo.getStudentsCount(
    query: filter.query.trim().isEmpty ? null : filter.query.trim(),
    courseId: filter.courseId,
    year: filter.year,
    status: filter.includeDeleted ? null : filter.status,
    includeDeleted: filter.includeDeleted,
  );
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
