import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/repositories/interfaces/report_repository_interface.dart';
import '../../core/repositories/supabase/supabase_report_repository.dart';
import '../../core/repositories/supabase/supabase_batch_repository.dart';
import '../../core/services/supabase_service.dart';

final reportRepositoryProvider = Provider<ReportRepository>((ref) => SupabaseReportRepository());

class ReportsService {
  final ReportRepository _repo;

  ReportsService(this._repo);

  Future<List<Map<String, dynamic>>> getFeeCollection(String startDate, String endDate, {String? paymentMode}) async {
    final from = DateTime.tryParse(startDate);
    final to = DateTime.tryParse(endDate);
    return await _repo.getFeeCollectionReport(from: from, to: to, paymentMode: paymentMode);
  }

  Future<List<Map<String, dynamic>>> getDefaultersList({int? courseId, int? batchId}) async {
    return await _repo.getDefaultersReport(courseId: courseId, batchId: batchId);
  }

  Future<List<Map<String, dynamic>>> getBatchWiseResults(int courseId, int batchId) async {
    return await _repo.getMeritList(courseId: courseId, batchId: batchId);
  }

  Future<List<Map<String, dynamic>>> getStudentList(int courseId, int batchId) async {
    return await _repo.getStudentList(courseId: courseId, batchId: batchId);
  }

  Future<List<Map<String, dynamic>>> getCourseRevenue() async {
    return await _repo.getCourseRevenueReport();
  }

  Future<List<Map<String, dynamic>>> getAllBatches() async {
    try {
      final client = SupabaseService.instance.client;
      final data = await client
          .from('batches')
          .select('id, batch_name, start_date')
          .isFilter('deleted_at', null)
          .order('id', ascending: false);

      final list = (data as List).map((row) {
        final name = row['batch_name']?.toString() ?? row['start_date']?.toString() ?? 'Batch #${row['id']}';
        return {
          'id': (row['id'] as num).toInt(),
          'name': name,
        };
      }).toList();
      if (list.isNotEmpty) return list;
    } catch (_) {}

    final fallback = await SupabaseBatchRepository().getBatches();
    return fallback.map((b) => {
      'id': b.id ?? 1,
      'name': b.batchName,
    }).toList();
  }
}

final reportsServiceProvider = Provider((ref) => ReportsService(ref.read(reportRepositoryProvider)));

final allBatchesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.read(reportsServiceProvider).getAllBatches();
});
