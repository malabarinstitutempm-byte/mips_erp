import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/course.dart';
import '../../core/models/course_subject.dart';
import '../../core/repositories/interfaces/course_repository_interface.dart';
import '../../core/repositories/interfaces/batch_repository_interface.dart';
import '../../core/repositories/supabase/supabase_course_repository.dart';
import '../../core/repositories/supabase/supabase_batch_repository.dart';

final courseRepositoryProvider = Provider<CourseRepository>((ref) => SupabaseCourseRepository());
final batchRepositoryProvider = Provider<BatchRepository>((ref) => SupabaseBatchRepository());

final coursesProvider = FutureProvider<List<Course>>((ref) async {
  ref.keepAlive();
  try {
    final repo = ref.read(courseRepositoryProvider);
    final list = await repo.getCourses();
    if (list.isNotEmpty) return list;
  } catch (_) {}
  return SupabaseCourseRepository.fallbackCourses;
});

final courseSubjectsProvider = FutureProvider.family<List<CourseSubject>, int>((ref, courseId) async {
  final repo = ref.read(courseRepositoryProvider);
  return await repo.getSubjectsForCourse(courseId);
});
