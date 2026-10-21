import 'package:flutter/foundation.dart';
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

class DashboardSummary {
  final int totalStudents;
  final int totalCourses;
  final int totalBatches;
  final double totalFees;
  final double collectedFees;
  final double pendingFees;
  final int upcomingExams;
  final int todayMarked;
  final int todayUnmarked;
  final bool tomorrowTimetablePublished;
  final List<Map<String, dynamic>> recentPayments;
  final List<Map<String, dynamic>> recentStudents;

  DashboardSummary({
    required this.totalStudents,
    required this.totalCourses,
    required this.totalBatches,
    required this.totalFees,
    required this.collectedFees,
    required this.pendingFees,
    required this.upcomingExams,
    required this.todayMarked,
    required this.todayUnmarked,
    required this.tomorrowTimetablePublished,
    required this.recentPayments,
    required this.recentStudents,
  });

  DashboardStats toStats() => DashboardStats(
        totalStudents: totalStudents,
        totalCourses: totalCourses,
        totalFees: totalFees,
        collectedFees: collectedFees,
        upcomingExams: upcomingExams,
      );
}

final dashboardSummaryProvider = FutureProvider<DashboardSummary>((ref) async {
  final client = SupabaseService.instance.client;

  try {
    final res = await client.rpc('get_admin_dashboard_summary');
    if (res is Map) {
      final totalFeesPaise = (res['total_fee_paise'] as num?)?.toInt() ?? 0;
      final collectedFeesPaise = (res['collected_fee_paise'] as num?)?.toInt() ?? 0;
      final pendingFeesPaise = (res['pending_fee_paise'] as num?)?.toInt() ?? 0;

      return DashboardSummary(
        totalStudents: (res['total_students'] as num?)?.toInt() ?? 0,
        totalCourses: (res['total_courses'] as num?)?.toInt() ?? 0,
        totalBatches: (res['total_batches'] as num?)?.toInt() ?? 0,
        totalFees: totalFeesPaise / 100.0,
        collectedFees: collectedFeesPaise / 100.0,
        pendingFees: pendingFeesPaise / 100.0,
        upcomingExams: (res['upcoming_exams'] as num?)?.toInt() ?? 0,
        todayMarked: (res['today_sessions_marked'] as num?)?.toInt() ?? 0,
        todayUnmarked: (res['today_sessions_unmarked'] as num?)?.toInt() ?? 0,
        tomorrowTimetablePublished: res['tomorrow_timetable_published'] == true,
        recentPayments: List<Map<String, dynamic>>.from(res['recent_payments'] ?? []),
        recentStudents: List<Map<String, dynamic>>.from(res['recent_students'] ?? []),
      );
    }
  } catch (e) {
    debugPrint('get_admin_dashboard_summary fallback error: $e');
  }

  // Resilient fallback query
  final studentRes = await client
      .from('students')
      .select('id')
      .isFilter('deleted_at', null)
      .eq('status', 'active')
      .count(CountOption.exact);
  final courseRes = await client
      .from('courses')
      .select('id')
      .isFilter('deleted_at', null)
      .count(CountOption.exact);
  final examRes = await client
      .from('exams')
      .select('id')
      .isFilter('deleted_at', null)
      .neq('status', 'published')
      .count(CountOption.exact);

  return DashboardSummary(
    totalStudents: studentRes.count,
    totalCourses: courseRes.count,
    totalBatches: 0,
    totalFees: 0.0,
    collectedFees: 0.0,
    pendingFees: 0.0,
    upcomingExams: examRes.count,
    todayMarked: 0,
    todayUnmarked: 0,
    tomorrowTimetablePublished: false,
    recentPayments: const [],
    recentStudents: const [],
  );
});

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final summary = await ref.watch(dashboardSummaryProvider.future);
  return summary.toStats();
});
