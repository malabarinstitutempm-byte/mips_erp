import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/grading_scheme.dart';
import '../../services/supabase_service.dart';
import '../interfaces/grading_repository_interface.dart';

class SupabaseGradingRepository implements GradingRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  @override
  Future<List<GradingScheme>> getGradingSchemes() async {
    final data = await _client
        .from('grading_schemes')
        .select('*')
        .order('min_percent', ascending: true);

    return (data as List).map((row) => GradingScheme.fromMap(Map<String, dynamic>.from(row))).toList();
  }

  @override
  Future<void> saveGradingScheme(GradingScheme scheme) async {
    SupabaseService.instance.assertCanWrite('save grading scheme');

    final payload = {
      'min_percent': scheme.minPercent,
      'max_percent': scheme.maxPercent,
      'grade': scheme.grade,
      'is_pass': scheme.isPass,
    };

    if (scheme.id != null) {
      await _client
          .from('grading_schemes')
          .update(payload)
          .eq('id', scheme.id!);
    } else {
      await _client
          .from('grading_schemes')
          .insert(payload);
    }
  }

  @override
  Future<void> deleteGradingScheme(int id) async {
    SupabaseService.instance.assertCanWrite('delete grading scheme');

    await _client
        .from('grading_schemes')
        .delete()
        .eq('id', id);
  }
}
