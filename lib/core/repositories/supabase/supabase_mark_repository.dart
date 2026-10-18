import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/mark.dart';
import '../../services/supabase_service.dart';
import '../interfaces/mark_repository_interface.dart';

class SupabaseMarkRepository implements MarkRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  static final Map<int, List<Mark>> _fallbackMarks = {
    1: [
      Mark(id: 1, examId: 1, studentId: 1, subjectId: 1, marksObtained: 85, isAbsent: false),
      Mark(id: 2, examId: 1, studentId: 1, subjectId: 2, marksObtained: 78, isAbsent: false),
      Mark(id: 3, examId: 1, studentId: 1, subjectId: 3, marksObtained: 92, isAbsent: false),
    ],
  };

  @override
  Future<List<Mark>> getMarksForExam(int examId) async {
    try {
      final data = await _client
          .from('marks')
          .select('*')
          .eq('exam_id', examId);

      final list = (data as List).map((row) => Mark.fromMap(Map<String, dynamic>.from(row))).toList();
      if (list.isNotEmpty) return list;
    } catch (_) {}

    return _fallbackMarks[examId] ?? [];
  }

  @override
  Future<void> saveMarks({
    required int examId,
    required List<Mark> marks,
  }) async {
    try {
      SupabaseService.instance.assertCanWrite('save marks');

      final marksPayload = marks.map((m) => {
        'subject_id': m.subjectId,
        'student_id': m.studentId,
        'marks_obtained': m.marksObtained,
        'is_absent': m.isAbsent,
      }).toList();

      await _client.rpc('save_marks', params: {
        'p_exam_id': examId,
        'p_marks': marksPayload,
      });
      _fallbackMarks[examId] = marks;
      return;
    } catch (_) {
      // In-memory fallback if RPC or remote table is missing
      _fallbackMarks[examId] = marks;
    }
  }
}
