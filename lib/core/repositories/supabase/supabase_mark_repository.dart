import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/mark.dart';
import '../../services/supabase_service.dart';
import '../interfaces/mark_repository_interface.dart';

class SupabaseMarkRepository implements MarkRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  // Clean fallback marks store (no mock/dummy marks)
  static final Map<int, List<Mark>> _fallbackMarks = {};

  @override
  Future<List<Mark>> getMarksForExam(int examId) async {
    final data = await _client
        .from('marks')
        .select('*')
        .eq('exam_id', examId);

    return (data as List).map((row) => Mark.fromMap(Map<String, dynamic>.from(row))).toList();
  }

  @override
  Future<void> saveMarks({
    required int examId,
    required List<Mark> marks,
  }) async {
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
  }
}
