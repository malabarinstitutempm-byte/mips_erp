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

  @override
  Future<List<Course>> getCourses({bool includeDeleted = false}) async {
    var req = _client.from('courses').select('*');

    if (!includeDeleted) {
      req = req.isFilter('deleted_at', null);
    }

    final data = await req.order('name', ascending: true);
    return (data as List).map((row) => Course.fromMap(Map<String, dynamic>.from(row))).toList();
  }

  @override
  Future<Course?> getCourseById(int id) async {
    final data = await _client
        .from('courses')
        .select('*')
        .eq('id', id)
        .maybeSingle();

    if (data != null) {
      return Course.fromMap(Map<String, dynamic>.from(data));
    }
    return null;
  }

  @override
  Future<Course> createCourse(Course course, List<CourseSubject> subjects) async {
    SupabaseService.instance.assertCanWrite('create course');

    final payload = course.toMap();
    payload.remove('id');
    payload.remove('total_fee');
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
      await saveCourseSubjects(newCourse.id!, subjects);
    }

    return newCourse;
  }

  @override
  Future<int> addCourse(Course course) async {
    final created = await createCourse(course, []);
    return created.id!;
  }

  @override
  Future<Course> updateCourse(Course course, [List<CourseSubject>? subjects]) async {
    SupabaseService.instance.assertCanWrite('update course');

    if (course.id == null) {
      throw ArgumentError('Course ID is required for update.');
    }

    final payload = course.toMap();
    payload.remove('id');
    payload.remove('total_fee');
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
  }

  @override
  Future<void> deleteCourse(int id) async {
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
  }

  @override
  Future<List<CourseSubject>> getCourseSubjects(int courseId) async {
    final data = await _client
        .from('course_subjects')
        .select('*')
        .eq('course_id', courseId)
        .isFilter('deleted_at', null)
        .order('id', ascending: true);

    return (data as List).map((row) => CourseSubject.fromMap(Map<String, dynamic>.from(row))).toList();
  }

  @override
  Future<List<CourseSubject>> getSubjectsForCourse(int courseId) async {
    return await getCourseSubjects(courseId);
  }

  @override
  Future<void> saveCourseSubjects(int courseId, List<CourseSubject> subjects) async {
    SupabaseService.instance.assertCanWrite('save course subjects');

    // Remove old course subjects
    await _client.from('course_subjects').delete().eq('course_id', courseId);

    if (subjects.isNotEmpty) {
      final subjectRows = subjects.map((s) {
        final m = s.toMap();
        m['course_id'] = courseId;
        m.remove('id');
        m.remove('name');
        m.remove('code');
        return m;
      }).toList();

      await _client.from('course_subjects').insert(subjectRows);
    }
  }

  @override
  Future<List<Batch>> getBatchesForCourse(int courseId, {bool includeCompleted = false}) async {
    var req = _client
        .from('batches')
        .select('*')
        .eq('course_id', courseId)
        .isFilter('deleted_at', null);

    if (!includeCompleted) {
      req = req.eq('status', 'active');
    }

    final data = await req.order('id', ascending: true);
    return (data as List).map((row) => Batch.fromMap(Map<String, dynamic>.from(row))).toList();
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
