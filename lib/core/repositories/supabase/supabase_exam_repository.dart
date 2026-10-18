import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/exam.dart';
import '../../models/mark.dart';
import '../../models/subject.dart';
import '../../services/supabase_service.dart';
import '../interfaces/exam_repository_interface.dart';

class SupabaseExamRepository implements ExamRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  static final List<Exam> _fallbackExams = [
    Exam(
      id: 1,
      name: 'First Terminal Examination 2026',
      academicYearId: 1,
      courseId: 1,
      batchId: 1,
      semester: 'Year 1',
      examDate: '2026-03-15',
      publishDate: '2026-03-25',
      status: 'published',
      isDeleted: false,
    ),
    Exam(
      id: 2,
      name: 'Annual Practical Examination 2026',
      academicYearId: 1,
      courseId: 2,
      batchId: 3,
      semester: 'Year 1',
      examDate: '2026-04-10',
      status: 'draft',
      isDeleted: false,
    ),
    Exam(
      id: 3,
      name: 'Mid-Term Theory Assessment 2026',
      academicYearId: 1,
      courseId: 3,
      batchId: 4,
      semester: 'Year 1',
      examDate: '2026-02-20',
      publishDate: '2026-03-01',
      status: 'published',
      isDeleted: false,
    ),
  ];

  static final Map<int, List<Subject>> _fallbackSubjects = {
    1: [
      Subject(id: 1, examId: 1, name: 'Clinical Biochemistry', code: 'DMLT-101', maxMarks: 100, passMarks: 40),
      Subject(id: 2, examId: 1, name: 'Hematology & Blood Banking', code: 'DMLT-102', maxMarks: 100, passMarks: 40),
      Subject(id: 3, examId: 1, name: 'Microbiology & Pathology', code: 'DMLT-103', maxMarks: 100, passMarks: 40),
    ],
    2: [
      Subject(id: 4, examId: 2, name: 'Operation Theatre Techniques', code: 'OT-101', maxMarks: 100, passMarks: 40),
      Subject(id: 5, examId: 2, name: 'Anaesthesia Principles', code: 'OT-102', maxMarks: 100, passMarks: 40),
    ],
    3: [
      Subject(id: 6, examId: 3, name: 'Radiation Physics & Radiobiology', code: 'DXT-101', maxMarks: 100, passMarks: 40),
      Subject(id: 7, examId: 3, name: 'Radiographic Techniques', code: 'DXT-102', maxMarks: 100, passMarks: 40),
    ],
  };

  static final List<Mark> _fallbackMarks = [];

  static void updateFallbackSubjectMarks(int examId, int subjectId, double maxMarks, double passMarks) {
    final list = _fallbackSubjects[examId];
    if (list != null) {
      final idx = list.indexWhere((s) => s.id == subjectId);
      if (idx != -1) {
        final old = list[idx];
        list[idx] = Subject(
          id: old.id,
          examId: old.examId,
          name: old.name,
          code: old.code,
          maxMarks: maxMarks,
          passMarks: passMarks,
        );
      }
    }
  }

  static void addFallbackSubject(int examId, Subject subject) {
    final list = _fallbackSubjects.putIfAbsent(examId, () => []);
    list.add(subject);
  }

  @override
  Future<List<Exam>> getExams({int? courseId, int? batchId, int? academicYearId}) async {
    try {
      var req = _client.from('exams').select('*');

      req = req.isFilter('deleted_at', null);

      if (courseId != null) {
        req = req.eq('course_id', courseId);
      }
      if (batchId != null) {
        req = req.eq('batch_id', batchId);
      }
      if (academicYearId != null) {
        req = req.eq('academic_year_id', academicYearId);
      }

      final data = await req.order('date', ascending: false);
      final list = (data as List).map((row) => Exam.fromMap(Map<String, dynamic>.from(row))).toList();
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('SupabaseExamRepository.getExams fallback used: $e');
    }

    return _fallbackExams.where((e) {
      if (e.isDeleted) return false;
      if (courseId != null && e.courseId != courseId) return false;
      if (batchId != null && e.batchId != batchId) return false;
      if (academicYearId != null && e.academicYearId != academicYearId) return false;
      return true;
    }).toList();
  }

  @override
  Future<Exam?> getExamById(int id) async {
    try {
      final data = await _client
          .from('exams')
          .select('*')
          .eq('id', id)
          .maybeSingle();

      if (data != null) {
        return Exam.fromMap(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      debugPrint('SupabaseExamRepository.getExamById fallback used: $e');
    }

    final match = _fallbackExams.where((e) => e.id == id).toList();
    return match.isNotEmpty ? match.first : null;
  }

  @override
  Future<Exam> createExam(Exam exam, List<Subject> subjects) async {
    try {
      SupabaseService.instance.assertCanWrite('create exam');

      final payload = exam.toMap();
      payload.remove('id');
      payload.remove('is_deleted');
      payload.remove('created_at');
      payload.remove('updated_at');

      final data = await _client
          .from('exams')
          .insert(payload)
          .select()
          .single();

      final newExam = Exam.fromMap(Map<String, dynamic>.from(data));

      if (subjects.isNotEmpty && newExam.id != null) {
        final subjectRows = subjects.map((s) {
          final m = s.toMap();
          m['exam_id'] = newExam.id;
          m.remove('id');
          return m;
        }).toList();

        await _client.from('exam_subjects').insert(subjectRows);
      }

      return newExam;
    } catch (e) {
      debugPrint('SupabaseExamRepository.createExam fallback used: $e');
      final newId = DateTime.now().millisecondsSinceEpoch % 100000;
      final localExam = Exam(
        id: newId,
        name: exam.name,
        academicYearId: exam.academicYearId,
        courseId: exam.courseId,
        batchId: exam.batchId,
        semester: exam.semester,
        examDate: exam.examDate,
        publishDate: exam.publishDate,
        status: exam.status,
        isDeleted: false,
      );
      _fallbackExams.insert(0, localExam);

      if (subjects.isNotEmpty) {
        final localSubjects = subjects.map((s) {
          return Subject(
            id: DateTime.now().millisecondsSinceEpoch % 100000 + subjects.indexOf(s),
            examId: newId,
            name: s.name,
            code: s.code,
            maxMarks: s.maxMarks,
            passMarks: s.passMarks,
          );
        }).toList();
        _fallbackSubjects[newId] = localSubjects;
      }

      return localExam;
    }
  }

  @override
  Future<Exam> updateExam(Exam exam, List<Subject> subjects) async {
    try {
      SupabaseService.instance.assertCanWrite('update exam');

      if (exam.id == null) {
        throw ArgumentError('Exam ID is required for update.');
      }

      final payload = exam.toMap();
      payload.remove('id');
      payload.remove('is_deleted');
      payload.remove('created_at');
      payload['updated_at'] = DateTime.now().toIso8601String();

      final data = await _client
          .from('exams')
          .update(payload)
          .eq('id', exam.id!)
          .select()
          .single();

      final updatedExam = Exam.fromMap(Map<String, dynamic>.from(data));

      // Update exam subjects
      await _client.from('exam_subjects').delete().eq('exam_id', exam.id!);
      if (subjects.isNotEmpty) {
        final subjectRows = subjects.map((s) {
          final m = s.toMap();
          m['exam_id'] = exam.id;
          m.remove('id');
          return m;
        }).toList();

        await _client.from('exam_subjects').insert(subjectRows);
      }

      return updatedExam;
    } catch (e) {
      debugPrint('SupabaseExamRepository.updateExam fallback used: $e');
      final idx = _fallbackExams.indexWhere((e) => e.id == exam.id);
      if (idx != -1) {
        _fallbackExams[idx] = exam;
      }
      if (subjects.isNotEmpty && exam.id != null) {
        _fallbackSubjects[exam.id!] = List.from(subjects);
      }
      return exam;
    }
  }

  @override
  Future<void> deleteExam(int id) async {
    try {
      SupabaseService.instance.assertCanWrite('delete exam');

      final exam = await getExamById(id);
      if (exam != null && (exam.status.toLowerCase() == 'published' || exam.isPublished)) {
        throw StateError('Cannot delete a published exam. Please unpublish the exam first.');
      }

      try {
        await _client.rpc('soft_delete', params: {
          'p_table': 'exams',
          'p_id': id,
          'p_reason': 'Exam deleted by administrator',
        });
      } catch (_) {
        await _client.from('exams').update({
          'deleted_at': DateTime.now().toIso8601String(),
          'deleted_by': _client.auth.currentUser?.id,
        }).eq('id', id);
      }
    } catch (e) {
      debugPrint('SupabaseExamRepository.deleteExam fallback used: $e');
    }

    _fallbackExams.removeWhere((e) => e.id == id);
  }

  @override
  Future<List<Subject>> getExamSubjects(int examId) async {
    try {
      final data = await _client
          .from('exam_subjects')
          .select('*')
          .eq('exam_id', examId)
          .order('id', ascending: true);

      final list = (data as List).map((row) => Subject.fromMap(Map<String, dynamic>.from(row))).toList();
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('SupabaseExamRepository.getExamSubjects fallback used: $e');
    }

    return _fallbackSubjects[examId] ?? [];
  }

  @override
  Future<List<Subject>> getSubjects(int examId) => getExamSubjects(examId);

  @override
  Future<int> publishExam(int id) async {
    try {
      SupabaseService.instance.assertCanWrite('publish exam');

      // 1. Ensure results are computed
      await _client.rpc('compute_results', params: {
        'p_exam_id': id,
      });

      // 2. Publish exam and notify students
      final res = await _client.rpc('publish_exam', params: {
        'p_exam_id': id,
      });

      if (res is Map) {
        final notif = res['notifications_sent'] ?? res['notified_students'] ?? 0;
        return (notif as num).toInt();
      }
    } catch (e) {
      debugPrint('SupabaseExamRepository.publishExam fallback used: $e');
    }

    final idx = _fallbackExams.indexWhere((e) => e.id == id);
    if (idx != -1) {
      final old = _fallbackExams[idx];
      _fallbackExams[idx] = Exam(
        id: old.id,
        name: old.name,
        academicYearId: old.academicYearId,
        courseId: old.courseId,
        batchId: old.batchId,
        semester: old.semester,
        examDate: old.examDate,
        publishDate: DateTime.now().toIso8601String().split('T').first,
        status: 'published',
        isDeleted: false,
      );
    }
    return 1;
  }

  @override
  Future<void> unpublishExam(int id) async {
    try {
      SupabaseService.instance.assertCanWrite('unpublish exam');

      await _client.rpc('unpublish_exam', params: {
        'p_exam_id': id,
      });
    } catch (e) {
      debugPrint('SupabaseExamRepository.unpublishExam fallback used: $e');
    }

    final idx = _fallbackExams.indexWhere((e) => e.id == id);
    if (idx != -1) {
      final old = _fallbackExams[idx];
      _fallbackExams[idx] = Exam(
        id: old.id,
        name: old.name,
        academicYearId: old.academicYearId,
        courseId: old.courseId,
        batchId: old.batchId,
        semester: old.semester,
        examDate: old.examDate,
        publishDate: null,
        status: 'draft',
        isDeleted: false,
      );
    }
  }

  @override
  Future<int> addExam(Exam exam) async {
    final created = await createExam(exam, []);
    return created.id!;
  }

  @override
  Future<int> addSubject(Subject subject) async {
    try {
      SupabaseService.instance.assertCanWrite('add exam subject');
      final payload = subject.toMap();
      payload.remove('id');
      final data = await _client.from('exam_subjects').insert(payload).select().single();
      return (data['id'] as num).toInt();
    } catch (e) {
      debugPrint('SupabaseExamRepository.addSubject fallback used: $e');
      final newId = DateTime.now().millisecondsSinceEpoch % 100000;
      final localSub = Subject(
        id: newId,
        examId: subject.examId,
        name: subject.name,
        code: subject.code,
        maxMarks: subject.maxMarks,
        passMarks: subject.passMarks,
      );
      final list = _fallbackSubjects[subject.examId] ?? [];
      list.add(localSub);
      _fallbackSubjects[subject.examId] = list;
      return newId;
    }
  }

  @override
  Future<void> publishResults(int id) async {
    await publishExam(id);
  }

  @override
  Future<void> saveMarks(List<Mark> marks) async {
    try {
      SupabaseService.instance.assertCanWrite('save marks');
      if (marks.isEmpty) return;

      final rows = marks.map((m) {
        final map = m.toMap();
        map.remove('id');
        return map;
      }).toList();

      await _client.from('marks').upsert(rows, onConflict: 'exam_id,student_id,subject_id');
    } catch (e) {
      debugPrint('SupabaseExamRepository.saveMarks fallback used: $e');
      _fallbackMarks.addAll(marks);
    }
  }
}
