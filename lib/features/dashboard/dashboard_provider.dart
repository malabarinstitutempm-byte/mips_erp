import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';

class DashboardStats {
  final int totalStudents;
  final int totalCourses;
  final double totalFees;
  final double collectedFees;
  final int upcomingExams;

  DashboardStats({
    required this.totalStudents,
    required this.totalCourses,
    required this.totalFees,
    required this.collectedFees,
    required this.upcomingExams,
  });
}

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final client = SupabaseService.instance.client;

  // 1. Total Active Students
  final studentRes = await client
      .from('students')
      .select('id')
      .isFilter('deleted_at', null)
      .eq('status', 'active')
      .count(CountOption.exact);
  final studentCount = studentRes.count;

  // 2. Total Courses
  final courseRes = await client
      .from('courses')
      .select('id')
      .isFilter('deleted_at', null)
      .count(CountOption.exact);
  final courseCount = courseRes.count;

  // 3. Fee Totals from fees ledger
  final feesData = await client
      .from('fees')
      .select('total_fee_paise, paid_amount_paise')
      .isFilter('deleted_at', null);

  int totalFeesPaise = 0;
  int collectedFeesPaise = 0;
  for (final row in (feesData as List)) {
    totalFeesPaise += (row['total_fee_paise'] as num?)?.toInt() ?? 0;
    collectedFeesPaise += (row['paid_amount_paise'] as num?)?.toInt() ?? 0;
  }

  // 4. Upcoming / Draft Exams
  final examRes = await client
      .from('exams')
      .select('id')
      .isFilter('deleted_at', null)
      .neq('status', 'published')
      .count(CountOption.exact);
  final upcomingExams = examRes.count;

  return DashboardStats(
    totalStudents: studentCount,
    totalCourses: courseCount,
    totalFees: totalFeesPaise / 100.0,
    collectedFees: collectedFeesPaise / 100.0,
    upcomingExams: upcomingExams,
  );
});
