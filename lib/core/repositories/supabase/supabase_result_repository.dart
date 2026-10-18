import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/result.dart';
import '../../services/supabase_service.dart';
import '../interfaces/result_repository_interface.dart';

class SupabaseResultRepository implements ResultRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  @override
  Future<List<Result>> getResultsForExam(int examId) async {
    try {
      final data = await _client
          .from('results')
          .select('*')
          .eq('exam_id', examId)
          .order('total_marks', ascending: false);

      return (data as List).map((row) => Result.fromMap(Map<String, dynamic>.from(row))).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> computeResults(int examId) async {
    SupabaseService.instance.assertCanWrite('compute exam results');

    try {
      await _client.rpc('compute_results', params: {
        'p_exam_id': examId,
      });
    } catch (_) {}
  }

  @override
  Future<List<Result>> getStudentResults(int studentId) async {
    try {
      final data = await _client
          .from('results')
          .select('*, exams!inner(name, date, status)')
          .eq('student_id', studentId)
          .eq('exams.status', 'published')
          .order('id', ascending: false);

      return (data as List).map((row) => Result.fromMap(Map<String, dynamic>.from(row))).toList();
    } catch (_) {
      return [];
    }
  }
}
