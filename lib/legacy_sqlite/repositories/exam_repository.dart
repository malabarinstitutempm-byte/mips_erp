import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../database_helper.dart';
import '../../core/models/exam.dart';
import '../../core/models/subject.dart';
import '../../core/models/mark.dart';

class ExamRepository {
  SupabaseClient get _supabase => SupabaseConfig.client;
  Future<Database> get _localDb async => await DatabaseHelper.instance.database;

  // ===========================================================================
  // Exams
  // ===========================================================================

  Future<List<Exam>> getExams() async {
    try {
      final res = await _supabase
          .from('exams')
          .select()
          .isFilter('deleted_at', null)
          .order('id', ascending: false);

      return (res as List).map((e) => Exam.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final db = await _localDb;
      final maps = await db.query('exams', where: 'is_deleted = 0', orderBy: 'id DESC');
      return maps.map((e) => Exam.fromMap(e)).toList();
    }
  }

  Future<int> addExam(Exam exam) async {
    final payload = <String, dynamic>{
      'name': exam.name.trim(),
      'course_id': exam.courseId,
      'batch_id': exam.batchId,
      'academic_year_id': exam.academicYearId,
      'status': exam.status.toLowerCase(),
      if (exam.semester != null) 'semester': exam.semester,
      if (exam.examDate != null) 'exam_date': exam.examDate,
    };

    try {
      final res = await _supabase
          .from('exams')
          .insert(payload)
          .select('id')
          .single();

      final newId = res['id'] as int;

      try {
        final localDb = await _localDb;
        final map = exam.toMap();
        map['id'] = newId;
        await localDb.insert('exams', map, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}

      return newId;
    } catch (_) {
      final db = await _localDb;
      final map = exam.toMap();
      map['created_at'] = DateTime.now().toIso8601String();
      return await db.insert('exams', map);
    }
  }

  Future<int> updateExam(Exam exam) async {
    if (exam.id == null) return 0;

    final payload = <String, dynamic>{
      'name': exam.name.trim(),
      'course_id': exam.courseId,
      'batch_id': exam.batchId,
      'academic_year_id': exam.academicYearId,
      'status': exam.status.toLowerCase(),
      if (exam.semester != null) 'semester': exam.semester,
      if (exam.examDate != null) 'exam_date': exam.examDate,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await _supabase
          .from('exams')
          .update(payload)
          .eq('id', exam.id!);

      try {
        final localDb = await _localDb;
        await localDb.update('exams', exam.toMap(), where: 'id = ?', whereArgs: [exam.id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final db = await _localDb;
      return await db.update('exams', exam.toMap(), where: 'id = ?', whereArgs: [exam.id]);
    }
  }

  Future<int> deleteExam(int id) async {
    try {
      await _supabase
          .from('exams')
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
            'deleted_by': _supabase.auth.currentUser?.id,
          })
          .eq('id', id);

      try {
        final localDb = await _localDb;
        await localDb.update('exams', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final db = await _localDb;
      return await db.update('exams', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
    }
  }

  // ===========================================================================
  // Subjects (Mapped to exam_subjects in Supabase)
  // ===========================================================================

  Future<List<Subject>> getSubjects(int examId) async {
    try {
      final res = await _supabase
          .from('exam_subjects')
          .select()
          .eq('exam_id', examId)
          .isFilter('deleted_at', null)
          .order('display_order', ascending: true)
          .order('id', ascending: true);

      return (res as List).map((e) => Subject.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final db = await _localDb;
      final maps = await db.query('subjects', where: 'exam_id = ?', whereArgs: [examId], orderBy: 'display_order ASC');
      return maps.map((e) => Subject.fromMap(e)).toList();
    }
  }

  Future<int> addSubject(Subject subject) async {
    final payload = <String, dynamic>{
      'exam_id': subject.examId,
      'name': subject.name.trim(),
      'code': (subject.code ?? subject.name.substring(0, 3)).trim().toUpperCase(),
      'max_marks': subject.maxMarks,
      'pass_marks': subject.passMarks,
      'theory_marks': subject.theoryMarks ?? subject.maxMarks,
      'practical_marks': subject.practicalMarks ?? 0.0,
      'display_order': subject.displayOrder,
    };

    try {
      final res = await _supabase
          .from('exam_subjects')
          .insert(payload)
          .select('id')
          .single();

      final newId = res['id'] as int;

      try {
        final localDb = await _localDb;
        final map = subject.toMap();
        map['id'] = newId;
        await localDb.insert('subjects', map, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}

      return newId;
    } catch (_) {
      final db = await _localDb;
      return await db.insert('subjects', subject.toMap());
    }
  }

  // ===========================================================================
  // Marks & Result Processing
  // ===========================================================================

  Future<List<Mark>> getMarksForSubject(int examId, int subjectId) async {
    try {
      final res = await _supabase
          .from('marks')
          .select()
          .eq('exam_id', examId)
          .eq('subject_id', subjectId)
          .isFilter('deleted_at', null);

      return (res as List).map((e) => Mark.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final db = await _localDb;
      final maps = await db.query('marks', where: 'exam_id = ? AND subject_id = ?', whereArgs: [examId, subjectId]);
      return maps.map((e) => Mark.fromMap(e)).toList();
    }
  }

  Future<void> saveMarks(List<Mark> marks) async {
    if (marks.isEmpty) return;
    final examId = marks.first.examId;

    try {
      final marksJson = marks.map((m) {
        final isAbsent = m.status?.toLowerCase() == 'absent' || m.marksObtained == null;
        return {
          'subject_id': m.subjectId,
          'student_id': m.studentId,
          'marks_obtained': isAbsent ? null : m.marksObtained,
          'is_absent': isAbsent,
        };
      }).toList();

      // Invoke server-side save_marks RPC
      await _supabase.rpc('save_marks', params: {
        'p_exam_id': examId,
        'p_marks': marksJson,
      });

      // Local backup sync
      try {
        final localDb = await _localDb;
        for (final m in marks) {
          await localDb.insert('marks', m.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } catch (_) {}
    } catch (_) {
      // Local fallback
      final db = await _localDb;
      await db.transaction((txn) async {
        for (final mark in marks) {
          await txn.insert('marks', mark.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    }
  }

  Future<void> publishResults(int examId) async {
    try {
      // 1. Calculate Pass/Fail, percentages, and ranks using server-side grading schemes
      await _supabase.rpc('compute_results', params: {'p_exam_id': examId});

      // 2. Publish exam and notify students
      await _supabase.rpc('publish_exam', params: {
        'p_exam_id': examId,
        'p_force_notify': false,
      });

      // Local sync
      try {
        final localDb = await _localDb;
        await localDb.update(
          'exams',
          {'status': 'Published', 'publish_date': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [examId],
        );
      } catch (_) {}
    } catch (_) {
      // Local fallback
      final db = await _localDb;
      await db.update(
        'exams',
        {'status': 'Published', 'publish_date': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [examId],
      );
    }
  }

  Future<void> unpublishExam(int examId) async {
    try {
      await _supabase.rpc('unpublish_exam', params: {'p_exam_id': examId});

      // Local sync
      try {
        final localDb = await _localDb;
        await localDb.update(
          'exams',
          {'status': 'Draft', 'publish_date': null},
          where: 'id = ?',
          whereArgs: [examId],
        );
      } catch (_) {}
    } catch (_) {
      final localDb = await _localDb;
      await localDb.update(
        'exams',
        {'status': 'Draft', 'publish_date': null},
        where: 'id = ?',
        whereArgs: [examId],
      );
    }
  }
}
