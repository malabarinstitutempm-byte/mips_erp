import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Soft-deletes a student and related enrollments so they disappear from
/// attendance, fees, exams, and portal lists — not only the student catalog.
class CascadeDeleteHelper {
  static String _now() => DateTime.now().toIso8601String();

  static Future<void> softDeleteStudent(
    SupabaseClient client,
    int studentId, {
    String? actorId,
  }) async {
    // 1. Try dedicated PostgreSQL SECURITY DEFINER RPC
    try {
      final res = await client.rpc('admin_delete_student', params: {
        'p_student_id': studentId,
      });
      if (res is Map && res['success'] == true) {
        return;
      }
    } catch (e) {
      debugPrint('CascadeDeleteHelper admin_delete_student RPC error: $e');
    }

    final stamp = _now();
    final payload = <String, dynamic>{
      'deleted_at': stamp,
      'updated_at': stamp,
    };
    if (actorId != null) payload['deleted_by'] = actorId;

    try {
      await client.from('student_enrollments').update({
        ...payload,
        'status': 'discontinued',
      }).eq('student_id', studentId).isFilter('deleted_at', null);
    } catch (e) {
      debugPrint('CascadeDeleteHelper enrollments for student $studentId: $e');
    }

    try {
      await client.from('profiles').update({
        'active': false,
        'updated_at': stamp,
      }).eq('student_id', studentId);
    } catch (e) {
      debugPrint('CascadeDeleteHelper profiles for student $studentId: $e');
    }

    try {
      await client.from('students').update(payload).eq('id', studentId).isFilter('deleted_at', null);
    } catch (e) {
      debugPrint('CascadeDeleteHelper student $studentId: $e');
    }
  }

  static Future<Set<int>> studentIdsForBatch(SupabaseClient client, int batchId) async {
    final ids = <int>{};
    try {
      final rows = await client
          .from('students')
          .select('id')
          .eq('batch_id', batchId)
          .isFilter('deleted_at', null);
      for (final row in (rows as List)) {
        final id = row['id'];
        if (id is int) ids.add(id);
      }
    } catch (e) {
      debugPrint('CascadeDeleteHelper students by batch $batchId: $e');
    }

    try {
      final rows = await client
          .from('student_enrollments')
          .select('student_id')
          .eq('batch_id', batchId)
          .isFilter('deleted_at', null);
      for (final row in (rows as List)) {
        final id = row['student_id'];
        if (id is int) ids.add(id);
      }
    } catch (e) {
      debugPrint('CascadeDeleteHelper enrollments by batch $batchId: $e');
    }
    return ids;
  }

  static Future<Set<int>> studentIdsForCourse(SupabaseClient client, int courseId) async {
    final ids = <int>{};
    try {
      final rows = await client
          .from('students')
          .select('id')
          .eq('course_id', courseId)
          .isFilter('deleted_at', null);
      for (final row in (rows as List)) {
        final id = row['id'];
        if (id is int) ids.add(id);
      }
    } catch (e) {
      debugPrint('CascadeDeleteHelper students by course $courseId: $e');
    }

    try {
      final rows = await client
          .from('student_enrollments')
          .select('student_id')
          .eq('course_id', courseId)
          .isFilter('deleted_at', null);
      for (final row in (rows as List)) {
        final id = row['student_id'];
        if (id is int) ids.add(id);
      }
    } catch (e) {
      debugPrint('CascadeDeleteHelper enrollments by course $courseId: $e');
    }
    return ids;
  }

  static Future<List<int>> batchIdsForCourse(SupabaseClient client, int courseId) async {
    try {
      final rows = await client
          .from('batches')
          .select('id')
          .eq('course_id', courseId)
          .isFilter('deleted_at', null);
      return (rows as List)
          .map((row) => row['id'])
          .whereType<int>()
          .toList();
    } catch (e) {
      debugPrint('CascadeDeleteHelper batches by course $courseId: $e');
      return [];
    }
  }

  static Future<void> softDeleteBatch(
    SupabaseClient client,
    int batchId, {
    String? actorId,
  }) async {
    // 1. Try dedicated PostgreSQL SECURITY DEFINER RPC
    try {
      final res = await client.rpc('admin_delete_batch', params: {
        'p_batch_id': batchId,
      });
      if (res is Map && res['success'] == true) {
        return;
      }
    } catch (e) {
      debugPrint('CascadeDeleteHelper admin_delete_batch RPC error: $e');
    }

    final studentIds = await studentIdsForBatch(client, batchId);
    for (final id in studentIds) {
      await softDeleteStudent(client, id, actorId: actorId);
    }

    final stamp = _now();
    final payload = <String, dynamic>{
      'deleted_at': stamp,
      'updated_at': stamp,
    };
    if (actorId != null) payload['deleted_by'] = actorId;

    try {
      await client.from('student_enrollments').update({
        ...payload,
        'status': 'discontinued',
      }).eq('batch_id', batchId).isFilter('deleted_at', null);
    } catch (e) {
      debugPrint('CascadeDeleteHelper enrollments for batch $batchId: $e');
    }

    try {
      await client.from('batches').update(payload).eq('id', batchId).isFilter('deleted_at', null);
    } catch (e) {
      debugPrint('CascadeDeleteHelper batch $batchId: $e');
    }
  }

  static Future<void> softDeleteCourse(
    SupabaseClient client,
    int courseId, {
    String? actorId,
  }) async {
    // 1. Try dedicated PostgreSQL SECURITY DEFINER RPC
    try {
      final res = await client.rpc('admin_delete_course', params: {
        'p_course_id': courseId,
      });
      if (res is Map && res['success'] == true) {
        return;
      }
    } catch (e) {
      debugPrint('CascadeDeleteHelper admin_delete_course RPC error: $e');
    }

    final batchIds = await batchIdsForCourse(client, courseId);
    final studentIds = await studentIdsForCourse(client, courseId);

    for (final batchId in batchIds) {
      studentIds.addAll(await studentIdsForBatch(client, batchId));
    }

    for (final id in studentIds) {
      await softDeleteStudent(client, id, actorId: actorId);
    }

    for (final batchId in batchIds) {
      await softDeleteBatch(client, batchId, actorId: actorId);
    }

    final stamp = _now();
    final payload = <String, dynamic>{
      'deleted_at': stamp,
      'updated_at': stamp,
    };
    if (actorId != null) payload['deleted_by'] = actorId;

    try {
      await client.from('courses').update(payload).eq('id', courseId).isFilter('deleted_at', null);
    } catch (e) {
      debugPrint('CascadeDeleteHelper course $courseId: $e');
    }
  }
}
