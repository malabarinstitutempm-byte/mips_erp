import '../../models/batch.dart';
import '../../models/course.dart';
import '../../models/course_subject.dart';

abstract class CourseRepository {
  Future<List<Course>> getCourses({bool includeDeleted = false});

  Future<Course?> getCourseById(int id);

  Future<Course> createCourse(Course course, List<CourseSubject> subjects);

  Future<int> addCourse(Course course);

  Future<Course> updateCourse(Course course, [List<CourseSubject>? subjects]);

  Future<void> deleteCourse(int id);

  Future<List<CourseSubject>> getCourseSubjects(int courseId);

  Future<List<CourseSubject>> getSubjectsForCourse(int courseId);

  Future<void> saveCourseSubjects(int courseId, List<CourseSubject> subjects);

  Future<List<Batch>> getBatchesForCourse(int courseId, {bool includeCompleted = false});

  Future<bool> isCourseStructureLocked(int courseId);
}
