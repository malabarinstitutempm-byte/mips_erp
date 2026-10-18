import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../database_helper.dart';
import '../../core/models/course.dart';
import '../../core/models/batch.dart';
import '../../core/models/course_subject.dart';

class CourseRepository {
  SupabaseClient get _supabase => SupabaseConfig.client;
  Future<Database> get _localDb async => await DatabaseHelper.instance.database;

  // ===========================================================================
  // Courses
  // ===========================================================================

  Future<List<Course>> getCourses() async {
    try {
      final res = await _supabase
          .from('courses')
          .select()
          .isFilter('deleted_at', null)
          .order('name');

      return (res as List).map((e) => Course.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final db = await _localDb;
      final maps = await db.query('courses', where: 'is_deleted = 0', orderBy: 'name');
      return maps.map((e) => Course.fromMap(e)).toList();
    }
  }

  Future<int> addCourse(Course course) async {
    final payload = <String, dynamic>{
      'name': course.name.trim(),
      'code': course.code.trim().toUpperCase(),
      'status': course.status.toLowerCase(),
      'total_fee_paise': course.totalFeePaise > 0 ? course.totalFeePaise : (course.totalFee * 100).round(),
    };

    if (course.universityId != null) payload['university_id'] = course.universityId;
    if (course.duration != null && course.duration!.isNotEmpty) payload['duration'] = course.duration;
    if (course.description != null && course.description!.isNotEmpty) payload['description'] = course.description;

    try {
      final res = await _supabase
          .from('courses')
          .insert(payload)
          .select('id')
          .single();

      final newId = res['id'] as int;

      // Local sync
      try {
        final localDb = await _localDb;
        final map = course.toMap();
        map['id'] = newId;
        await localDb.insert('courses', map, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}

      return newId;
    } catch (_) {
      final db = await _localDb;
      final map = course.toMap();
      map['created_at'] = DateTime.now().toIso8601String();
      return await db.insert('courses', map);
    }
  }

  Future<int> updateCourse(Course course) async {
    if (course.id == null) return 0;

    final payload = <String, dynamic>{
      'name': course.name.trim(),
      'code': course.code.trim().toUpperCase(),
      'status': course.status.toLowerCase(),
      'total_fee_paise': course.totalFeePaise > 0 ? course.totalFeePaise : (course.totalFee * 100).round(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (course.universityId != null) payload['university_id'] = course.universityId;
    if (course.duration != null) payload['duration'] = course.duration;
    if (course.description != null) payload['description'] = course.description;

    try {
      await _supabase
          .from('courses')
          .update(payload)
          .eq('id', course.id!);

      try {
        final localDb = await _localDb;
        await localDb.update('courses', course.toMap(), where: 'id = ?', whereArgs: [course.id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final db = await _localDb;
      return await db.update('courses', course.toMap(), where: 'id = ?', whereArgs: [course.id]);
    }
  }

  Future<int> deleteCourse(int id) async {
    try {
      await _supabase
          .from('courses')
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
            'deleted_by': _supabase.auth.currentUser?.id,
          })
          .eq('id', id);

      try {
        final localDb = await _localDb;
        await localDb.update('courses', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final db = await _localDb;
      return await db.update('courses', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
    }
  }

  // ===========================================================================
  // Batches
  // ===========================================================================

  Future<List<Batch>> getBatchesForCourse(int courseId) async {
    try {
      final res = await _supabase
          .from('batches')
          .select()
          .eq('course_id', courseId)
          .isFilter('deleted_at', null)
          .order('start_date', ascending: false);

      return (res as List).map((e) => Batch.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final db = await _localDb;
      final maps = await db.query(
        'batches',
        where: 'course_id = ? AND is_deleted = 0',
        whereArgs: [courseId],
        orderBy: 'start_date DESC',
      );
      return maps.map((e) => Batch.fromMap(e)).toList();
    }
  }

  Future<int> addBatch(Batch batch) async {
    final payload = <String, dynamic>{
      'course_id': batch.courseId,
      'batch_name': batch.batchName.trim(),
      if (batch.startDate != null) 'start_date': batch.startDate,
      if (batch.endDate != null) 'end_date': batch.endDate,
    };

    try {
      final res = await _supabase
          .from('batches')
          .insert(payload)
          .select('id')
          .single();

      final newId = res['id'] as int;

      try {
        final localDb = await _localDb;
        final map = batch.toMap();
        map['id'] = newId;
        await localDb.insert('batches', map, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}

      return newId;
    } catch (_) {
      final db = await _localDb;
      final map = batch.toMap();
      map['created_at'] = DateTime.now().toIso8601String();
      return await db.insert('batches', map);
    }
  }

  Future<int> updateBatch(Batch batch) async {
    if (batch.id == null) return 0;

    final payload = <String, dynamic>{
      'course_id': batch.courseId,
      'batch_name': batch.batchName.trim(),
      if (batch.startDate != null) 'start_date': batch.startDate,
      if (batch.endDate != null) 'end_date': batch.endDate,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await _supabase
          .from('batches')
          .update(payload)
          .eq('id', batch.id!);

      try {
        final localDb = await _localDb;
        await localDb.update('batches', batch.toMap(), where: 'id = ?', whereArgs: [batch.id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final db = await _localDb;
      return await db.update('batches', batch.toMap(), where: 'id = ?', whereArgs: [batch.id]);
    }
  }

  Future<int> deleteBatch(int id) async {
    try {
      await _supabase
          .from('batches')
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
            'deleted_by': _supabase.auth.currentUser?.id,
          })
          .eq('id', id);

      try {
        final localDb = await _localDb;
        await localDb.update('batches', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final db = await _localDb;
      return await db.update('batches', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
    }
  }

  // ===========================================================================
  // Course Curriculum Subjects
  // ===========================================================================

  Future<List<CourseSubject>> getCourseSubjects(int courseId) async {
    try {
      final res = await _supabase
          .from('course_subjects')
          .select()
          .eq('course_id', courseId)
          .isFilter('deleted_at', null)
          .order('id');

      return (res as List).map((e) => CourseSubject.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final db = await _localDb;
      final maps = await db.query('course_subjects', where: 'course_id = ?', whereArgs: [courseId]);
      return maps.map((e) => CourseSubject.fromMap(e)).toList();
    }
  }

  Future<int> addCourseSubject(CourseSubject subject) async {
    final payload = <String, dynamic>{
      'course_id': subject.courseId,
      'subject_name': subject.subjectName.trim(),
      'max_marks': subject.maxMarks,
      'pass_marks': subject.passMarks,
      if (subject.subjectCode != null) 'subject_code': subject.subjectCode!.trim(),
      if (subject.semester != null) 'semester': subject.semester,
    };

    try {
      final res = await _supabase
          .from('course_subjects')
          .insert(payload)
          .select('id')
          .single();

      final newId = res['id'] as int;

      try {
        final localDb = await _localDb;
        final map = subject.toMap();
        map['id'] = newId;
        await localDb.insert('course_subjects', map, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}

      return newId;
    } catch (_) {
      final db = await _localDb;
      return await db.insert('course_subjects', subject.toMap());
    }
  }

  Future<int> updateCourseSubject(CourseSubject subject) async {
    if (subject.id == null) return 0;

    final payload = <String, dynamic>{
      'course_id': subject.courseId,
      'subject_name': subject.subjectName.trim(),
      'max_marks': subject.maxMarks,
      'pass_marks': subject.passMarks,
      if (subject.subjectCode != null) 'subject_code': subject.subjectCode!.trim(),
      if (subject.semester != null) 'semester': subject.semester,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await _supabase
          .from('course_subjects')
          .update(payload)
          .eq('id', subject.id!);

      try {
        final localDb = await _localDb;
        await localDb.update('course_subjects', subject.toMap(), where: 'id = ?', whereArgs: [subject.id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final db = await _localDb;
      return await db.update('course_subjects', subject.toMap(), where: 'id = ?', whereArgs: [subject.id]);
    }
  }

  Future<int> deleteCourseSubject(int id) async {
    try {
      await _supabase
          .from('course_subjects')
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
            'deleted_by': _supabase.auth.currentUser?.id,
          })
          .eq('id', id);

      try {
        final localDb = await _localDb;
        await localDb.delete('course_subjects', where: 'id = ?', whereArgs: [id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final db = await _localDb;
      return await db.delete('course_subjects', where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<List<CourseSubject>> getSubjectsForCourse(int courseId) async {
    return await getCourseSubjects(courseId);
  }

  Future<void> saveCourseSubjects(int courseId, List<CourseSubject> subjects) async {
    for (final s in subjects) {
      if (s.id == null) {
        await addCourseSubject(s);
      } else {
        await updateCourseSubject(s);
      }
    }
  }
}
