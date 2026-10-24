import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/batch.dart';
import '../../models/course.dart';
import '../../models/course_subject.dart';
import '../../services/supabase_service.dart';
import '../interfaces/course_repository_interface.dart';
import 'cascade_delete_helper.dart';
import 'supabase_batch_repository.dart';

class SupabaseCourseRepository implements CourseRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  // Clean fallback institutional courses store (no mock/dummy courses)
  static final List<Course> _fallbackCourses = [];
  static List<Course> get fallbackCourses => List.unmodifiable(_fallbackCourses);
  static final Map<int, List<CourseSubject>> _fallbackSubjects = {};

  @override
  Future<List<Course>> getCourses({bool includeDeleted = false}) async {
    try {
      var req = _client.from('courses').select('*');

      if (!includeDeleted) {
        req = req.isFilter('deleted_at', null);
      }

      final data = await req.order('name', ascending: true);
      return (data as List).map((row) => Course.fromMap(Map<String, dynamic>.from(row))).toList();
    } catch (e) {
      debugPrint('SupabaseCourseRepository.getCourses fallback used: $e');
      return [];
    }
  }

  @override
  Future<Course?> getCourseById(int id) async {
    try {
      final data = await _client
          .from('courses')
          .select('*')
          .eq('id', id)
          .maybeSingle();

      if (data != null) {
        return Course.fromMap(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      debugPrint('SupabaseCourseRepository.getCourseById fallback used for id $id: $e');
    }

    final match = _fallbackCourses.where((c) => c.id == id).toList();
    return match.isNotEmpty ? match.first : null;
  }

  @override
  Future<Course> createCourse(Course course, List<CourseSubject> subjects) async {
    try {
      SupabaseService.instance.assertCanWrite('create course');

      final payload = course.toMap();
      payload.remove('id');
      payload.remove('is_deleted');
      payload.remove('created_at');
      payload.remove('updated_at');

      final data = await _client
          .from('courses')
          .insert(payload)
          .select()
          .single();

      final newCourse = Course.fromMap(Map<String, dynamic>.from(data));

      if (subjects.isNotEmpty && newCourse.id != null) {
        final subjectRows = subjects.map((s) {
          final m = s.toMap();
          m['course_id'] = newCourse.id;
          m.remove('id');
          return m;
        }).toList();

        await _client.from('course_subjects').insert(subjectRows);
      }

      return newCourse;
    } catch (e) {
      debugPrint('SupabaseCourseRepository.createCourse saving locally: $e');
      final newId = DateTime.now().millisecondsSinceEpoch % 100000;
      final localCourse = Course(
        id: newId,
        name: course.name,
        code: course.code,
        universityId: course.universityId,
        duration: course.duration,
        totalFee: course.totalFee,
        totalFeePaise: course.totalFeePaise,
        courseType: course.courseType,
        description: course.description,
        status: course.status,
        isDeleted: false,
      );

      _fallbackCourses.add(localCourse);

      if (subjects.isNotEmpty) {
        final attachedSubjects = subjects.map((s) {
          return CourseSubject(
            id: DateTime.now().millisecondsSinceEpoch % 100000 + subjects.indexOf(s),
            courseId: newId,
            semester: s.semester,
            subjectName: s.subjectName,
            subjectCode: s.subjectCode,
            maxMarks: s.maxMarks,
            passMarks: s.passMarks,
          );
        }).toList();
        _fallbackSubjects[newId] = attachedSubjects;
      }

      return localCourse;
    }
  }

  @override
  Future<int> addCourse(Course course) async {
    final created = await createCourse(course, []);
    return created.id!;
  }

  @override
  Future<Course> updateCourse(Course course, [List<CourseSubject>? subjects]) async {
    try {
      SupabaseService.instance.assertCanWrite('update course');

      if (course.id == null) {
        throw ArgumentError('Course ID is required for update.');
      }

      final payload = course.toMap();
      payload.remove('id');
      payload.remove('is_deleted');
      payload.remove('created_at');
      payload['updated_at'] = DateTime.now().toIso8601String();

      final data = await _client
          .from('courses')
          .update(payload)
          .eq('id', course.id!)
          .select()
          .single();

      final updatedCourse = Course.fromMap(Map<String, dynamic>.from(data));

      if (subjects != null) {
        await saveCourseSubjects(course.id!, subjects);
      }

      return updatedCourse;
    } catch (e) {
      debugPrint('SupabaseCourseRepository.updateCourse fallback used for id ${course.id}: $e');
      final idx = _fallbackCourses.indexWhere((c) => c.id == course.id);
      if (idx != -1) {
        _fallbackCourses[idx] = course;
      } else {
        _fallbackCourses.add(course);
      }

      if (subjects != null && course.id != null) {
        _fallbackSubjects[course.id!] = List.from(subjects);
      }

      return course;
    }
  }

  @override
  Future<void> deleteCourse(int id) async {
    try {
      SupabaseService.instance.assertCanWrite('delete course');
      try {
        await _client.rpc('soft_delete', params: {
          'p_table': 'courses',
          'p_id': id,
          'p_reason': 'Course deleted by administrator',
        });
      } catch (_) {}

      await CascadeDeleteHelper.softDeleteCourse(
        _client,
        id,
        actorId: _client.auth.currentUser?.id,
      );
    } catch (e) {
      debugPrint('SupabaseCourseRepository.deleteCourse fallback used for id $id: $e');
      _fallbackCourses.removeWhere((c) => c.id == id);
    }
  }

  @override
  Future<List<CourseSubject>> getCourseSubjects(int courseId) async {
    try {
      final data = await _client
          .from('course_subjects')
          .select('*')
          .eq('course_id', courseId)
          .isFilter('deleted_at', null)
          .order('id', ascending: true);

      final list = (data as List).map((row) => CourseSubject.fromMap(Map<String, dynamic>.from(row))).toList();
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('SupabaseCourseRepository.getCourseSubjects fallback used for courseId $courseId: $e');
    }

    return _fallbackSubjects[courseId] ?? [];
  }

  @override
  Future<List<CourseSubject>> getSubjectsForCourse(int courseId) async {
    return await getCourseSubjects(courseId);
  }

  @override
  Future<void> saveCourseSubjects(int courseId, List<CourseSubject> subjects) async {
    try {
      SupabaseService.instance.assertCanWrite('save course subjects');

      // Remove old course subjects
      await _client.from('course_subjects').delete().eq('course_id', courseId);

      if (subjects.isNotEmpty) {
        final subjectRows = subjects.map((s) {
          final m = s.toMap();
          m['course_id'] = courseId;
          m.remove('id');
          return m;
        }).toList();

        await _client.from('course_subjects').insert(subjectRows);
      }
    } catch (e) {
      debugPrint('SupabaseCourseRepository.saveCourseSubjects fallback saving locally: $e');
      _fallbackSubjects[courseId] = List.from(subjects);
    }
  }

  @override
  Future<List<Batch>> getBatchesForCourse(int courseId, {bool includeCompleted = false}) async {
    try {
      var req = _client
          .from('batches')
          .select('*')
          .eq('course_id', courseId)
          .isFilter('deleted_at', null);

      if (!includeCompleted) {
        req = req.eq('status', 'active');
      }

      final data = await req.order('id', ascending: true);

      final list = (data as List).map((row) => Batch.fromMap(Map<String, dynamic>.from(row))).toList();
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('SupabaseCourseRepository.getBatchesForCourse fallback used for courseId $courseId: $e');
    }

    return await SupabaseBatchRepository().getBatches(courseId: courseId, includeCompleted: includeCompleted);
  }

  @override
  Future<bool> isCourseStructureLocked(int courseId) async {
    try {
      final exams = await _client.from('exams').select('id').eq('course_id', courseId).isFilter('deleted_at', null).limit(1);
      if (exams.isNotEmpty) return true;

      final batches = await _client.from('batches').select('id').eq('course_id', courseId).isFilter('deleted_at', null);
      if (batches.isNotEmpty) {
        final bIds = batches.map((b) => b['id']).toList();
        final sessions = await _client.from('attendance_sessions').select('id').inFilter('batch_id', bIds).limit(1);
        if (sessions.isNotEmpty) return true;
      }
    } catch (e) {
      debugPrint('SupabaseCourseRepository.isCourseStructureLocked check error: $e');
    }
    return false;
  }
}

