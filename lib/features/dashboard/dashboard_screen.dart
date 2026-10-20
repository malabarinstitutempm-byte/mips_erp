import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/kpi_card.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/app_avatar.dart';
import '../layout/app_shell.dart';
import '../students/student_provider.dart';
import '../courses/course_provider.dart';
import 'dashboard_provider.dart';
import '../students/add_student_screen.dart';
import 'system_health_card.dart';
import 'today_attendance_board.dart';
import 'tomorrow_timetable_alert_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(studentsProvider(''));
    final statsAsync = ref.watch(dashboardStatsProvider);
    final coursesAsync = ref.watch(coursesProvider);
    final courseMap = coursesAsync.maybeWhen(
      data: (courses) => {for (var c in courses) if (c.id != null) c.id!: c.name},
      orElse: () => <int, String>{},
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        final kpiCards = [
          KpiCard(
            title: 'Total Students',
            value: '248',
            icon: LucideIcons.users,
            baseColor: AppColors.students.base,
            tintColor: AppColors.students.tint,
          ),
          KpiCard(
            title: 'Active Courses',
            value: '8',
            icon: LucideIcons.bookOpen,
            baseColor: AppColors.courses.base,
            tintColor: AppColors.courses.tint,
          ),
          KpiCard(
            title: 'Total Receivable',
            value: '₹24.8L',
            icon: LucideIcons.indianRupee,
            baseColor: AppColors.fees.base,
            tintColor: AppColors.fees.tint,
          ),
          KpiCard(
            title: 'Students w/ Dues',
            value: '61',
            icon: LucideIcons.alertTriangle,
            baseColor: AppColors.danger.base,
            tintColor: AppColors.danger.tint,
          ),
        ];

        final chartCard = SectionCard(
          title: 'Revenue Overview (Last 6 Months)',
          child: SizedBox(
            height: 260,
            child: Padding(
              padding: const EdgeInsets.only(top: 24.0, right: 16),
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 6,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          const titles = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
                          if (value.toInt() >= 0 && value.toInt() < titles.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(titles[value.toInt()], style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox();
                          return Text('${value.toInt()}L', style: const TextStyle(color: AppColors.textMuted, fontSize: 12));
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => const FlLine(color: AppColors.border, strokeWidth: 1, dashArray: [4, 4]),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    _buildBarGroup(0, 2.1),
                    _buildBarGroup(1, 3.2),
                    _buildBarGroup(2, 1.8),
                    _buildBarGroup(3, 4.5),
                    _buildBarGroup(4, 2.9),
                    _buildBarGroup(5, 5.2),
                  ],
                ),
              ),
            ),
          ),
        );

        final quickActionsCard = SectionCard(
          title: 'Quick Actions',
          child: Column(
            children: [
              _QuickActionTile(
                icon: LucideIcons.userPlus,
                label: 'Admit New Student',
                onTap: () => AddStudentPanel.show(context),
              ),
              _QuickActionTile(
                icon: LucideIcons.receipt,
                label: 'Record Fee Payment',
                onTap: () => ref.read(navigationProvider.notifier).state = 3,
              ),
              _QuickActionTile(
                icon: LucideIcons.fileText,
                label: 'Generate Document',
                onTap: () => ref.read(navigationProvider.notifier).state = 4,
              ),
            ],
          ),
        );

        final recentAdmissionsCard = SectionCard(
          title: 'Recent Admissions',
          padding: EdgeInsets.zero,
          child: studentsAsync.when(
            data: (students) {
              if (students.isEmpty) {
                return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No recent admissions.', style: TextStyle(color: AppColors.textMuted))));
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: students.length > 3 ? 3 : students.length,
                itemBuilder: (context, index) {
                  final s = students[index];
                  return Container(
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    child: Row(
                      children: [
                        AppAvatar(name: s.name, radius: 16),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textStrong, fontSize: 13)),
                              Text(courseMap[s.courseId] ?? (s.courseId != null ? 'Course #${s.courseId}' : 'N/A'), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            error: (_, __) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: const Row(
                      children: [
                        AppAvatar(name: 'Mohammed Shafi', radius: 16),
                        SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Mohammed Shafi', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textStrong, fontSize: 13)),
                              Text('Diploma in Medical Laboratory Technology', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: const Row(
                      children: [
                        AppAvatar(name: 'Fathima Sana', radius: 16),
                        SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Fathima Sana', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textStrong, fontSize: 13)),
                              Text('Diploma in Radiological Technology', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        if (isMobile) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PageHeader(
                  title: 'Institution Overview',
                  subtitle: 'Summary of the current academic session.',
                ),
                const TomorrowTimetableAlertCard(),
                // 2x2 KPI Grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  childAspectRatio: 1.22,
                  children: kpiCards,
                ),
                const SizedBox(height: AppSpacing.lg),
                chartCard,
                const SizedBox(height: AppSpacing.lg),
                const TodayAttendanceBoard(),
                const SizedBox(height: AppSpacing.lg),
                const SystemHealthCard(),
                const SizedBox(height: AppSpacing.lg),
                quickActionsCard,
                const SizedBox(height: AppSpacing.lg),
                recentAdmissionsCard,
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          );
        }

        // Desktop layout
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(
                title: 'Institution Overview',
                subtitle: 'Welcome back! Here is a summary of the current academic session.',
              ),
              const TomorrowTimetableAlertCard(),
              SizedBox(
                height: 148,
                child: Row(
                  children: [
                    Expanded(child: kpiCards[0]),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: kpiCards[1]),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: kpiCards[2]),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: kpiCards[3]),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const TodayAttendanceBoard(),
              const SizedBox(height: AppSpacing.lg),
              const SystemHealthCard(),
              const SizedBox(height: AppSpacing.xl),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: chartCard),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        quickActionsCard,
                        const SizedBox(height: AppSpacing.xl),
                        recentAdmissionsCard,
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        );
      },
    );
  }

  BarChartGroupData _buildBarGroup(int x, double y) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: AppColors.brand,
          width: 24,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.control),
          color: AppColors.surface,
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.brand, size: 18),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.textStrong),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(LucideIcons.chevronRight, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
