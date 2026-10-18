import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../interfaces/report_repository_interface.dart';

class SupabaseReportRepository implements ReportRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  @override
  Future<Map<String, dynamic>> getDashboardKPIs() async {
    try {
      final res = await _client.rpc('get_dashboard_kpis');
      return Map<String, dynamic>.from(res as Map);
    } catch (_) {
      final studentCount = await _client
          .from('students')
          .select('id')
          .isFilter('deleted_at', null)
          .eq('status', 'active')
          .count(CountOption.exact);

      final coursesCount = await _client
          .from('courses')
          .select('id')
          .isFilter('deleted_at', null)
          .count(CountOption.exact);

      final batchesCount = await _client
          .from('batches')
          .select('id')
          .isFilter('deleted_at', null)
          .count(CountOption.exact);

      final feesData = await _client
          .from('fees')
          .select('total_fee_paise, paid_amount_paise, pending_amount_paise')
          .isFilter('deleted_at', null);

      int totalFeePaise = 0;
      int paidPaise = 0;
      int pendingPaise = 0;

      for (final r in (feesData as List)) {
        totalFeePaise += (r['total_fee_paise'] as num?)?.toInt() ?? 0;
        paidPaise += (r['paid_amount_paise'] as num?)?.toInt() ?? 0;
        pendingPaise += (r['pending_amount_paise'] as num?)?.toInt() ?? 0;
      }

      return {
        'total_students': studentCount.count,
        'total_courses': coursesCount.count,
        'total_batches': batchesCount.count,
        'total_fee_paise': totalFeePaise,
        'collected_fee_paise': paidPaise,
        'pending_fee_paise': pendingPaise,
      };
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getFeeCollectionReport({
    DateTime? from,
    DateTime? to,
    String? paymentMode,
  }) async {
    final sDate = from != null ? from.toIso8601String().split('T')[0] : '2000-01-01';
    final eDate = to != null ? to.toIso8601String().split('T')[0] : '2100-01-01';
    final mode = (paymentMode == null || paymentMode.isEmpty || paymentMode.toLowerCase() == 'all')
        ? null
        : paymentMode.toLowerCase();

    try {
      final res = await _client.rpc('report_fee_collection', params: {
        'p_start_date': sDate,
        'p_end_date': eDate,
        'p_payment_mode': mode,
      });
      return (res as List).map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      // Fallback query if RPC isn't deployed yet
      var req = _client
          .from('payments')
          .select('id, payment_date, amount_paise, payment_mode, reference_number, remarks, students(name, admission_number, courses(name), batches(batch_name))')
          .eq('is_cancelled', false)
          .isFilter('deleted_at', null)
          .gte('payment_date', sDate)
          .lte('payment_date', eDate);

      if (mode != null) {
        req = req.eq('payment_mode', mode);
      }

      final data = await req.order('payment_date', ascending: false);
      return (data as List).map((row) {
        final st = row['students'] as Map<String, dynamic>?;
        final cr = st?['courses'] as Map<String, dynamic>?;
        final bt = st?['batches'] as Map<String, dynamic>?;
        final amountPaise = (row['amount_paise'] as num?)?.toInt() ?? 0;
        return {
          'id': row['id'],
          'date': row['payment_date'],
          'student_name': st?['name']?.toString() ?? 'N/A',
          'admission_number': st?['admission_number']?.toString() ?? 'N/A',
          'course_name': cr?['name']?.toString() ?? 'N/A',
          'batch_name': bt?['batch_name']?.toString() ?? 'N/A',
          'amount_paise': amountPaise,
          'amount': amountPaise / 100.0,
          'payment_mode': row['payment_mode']?.toString() ?? 'other',
          'reference_number': row['reference_number']?.toString() ?? '',
          'remarks': row['remarks']?.toString() ?? '',
        };
      }).toList();
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getCourseRevenueReport() async {
    try {
      final res = await _client.rpc('report_course_revenue');
      return (res as List).map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      final data = await _client
          .from('view_course_financial_summary')
          .select('*')
          .order('course_name', ascending: true);
      return (data as List).map((row) => Map<String, dynamic>.from(row)).toList();
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getDefaultersReport({
    int? courseId,
    int? batchId,
  }) async {
    try {
      final res = await _client.rpc('report_defaulters', params: {
        'p_course_id': courseId,
        'p_batch_id': batchId,
      });
      return (res as List).map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      var req = _client
          .from('view_fee_defaulters')
          .select('*');
      if (courseId != null) req = req.eq('course_id', courseId);
      if (batchId != null) req = req.eq('batch_id', batchId);
      final data = await req.order('pending_amount_paise', ascending: false);
      return (data as List).map((row) => Map<String, dynamic>.from(row)).toList();
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getMeritList({
    int? examId,
    int? courseId,
    int? batchId,
    int limit = 50,
  }) async {
    try {
      final res = await _client.rpc('report_merit_list', params: {
        'p_exam_id': examId,
        'p_course_id': courseId,
        'p_batch_id': batchId,
      });
      return (res as List).map((row) => Map<String, dynamic>.from(row)).take(limit).toList();
    } catch (_) {
      var req = _client.from('view_merit_list').select('*');
      if (examId != null) req = req.eq('exam_id', examId);
      if (courseId != null) req = req.eq('course_id', courseId);
      if (batchId != null) req = req.eq('batch_id', batchId);
      final data = await req.order('percentage', ascending: false).limit(limit);
      return (data as List).map((row) => Map<String, dynamic>.from(row)).toList();
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getStudentList({
    int? courseId,
    int? batchId,
    String? status,
  }) async {
    try {
      final res = await _client.rpc('report_student_list', params: {
        'p_course_id': courseId,
        'p_batch_id': batchId,
        'p_status': status,
      });
      return (res as List).map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      var req = _client
          .from('students')
          .select('id, name, admission_number, registration_number, phone, gender, admission_date, status, courses(name), batches(batch_name)')
          .isFilter('deleted_at', null);

      if (courseId != null) req = req.eq('course_id', courseId);
      if (batchId != null) req = req.eq('batch_id', batchId);
      if (status != null) req = req.eq('status', status);

      final data = await req.order('name', ascending: true);
      return (data as List).map((row) {
        final cr = row['courses'] as Map<String, dynamic>?;
        final bt = row['batches'] as Map<String, dynamic>?;
        return {
          'id': row['id'],
          'name': row['name'],
          'admission_number': row['admission_number'] ?? 'N/A',
          'registration_number': row['registration_number'] ?? 'N/A',
          'phone': row['phone'] ?? 'N/A',
          'gender': row['gender'] ?? 'N/A',
          'course_name': cr?['name'] ?? 'N/A',
          'batch_name': bt?['batch_name'] ?? 'N/A',
          'admission_date': row['admission_date']?.toString() ?? 'N/A',
          'status': row['status'] ?? 'active',
        };
      }).toList();
    }
  }
}
