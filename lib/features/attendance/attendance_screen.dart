// lib/features/attendance/attendance_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/section_card.dart';
import '../courses/course_provider.dart';
import '../reports/reports_provider.dart';
import '../reports/report_generator.dart';
import 'attendance_provider.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Settings form state
  double _minPercent = 75.0;
  double _reminderPercent = 80.0;
  double _lateWeight = 0.5;
  String _leaveHandling = 'excluded';
  bool _isSavingSettings = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unmarkedAsync = ref.watch(unmarkedSessionsTodayProvider);
    final unmarkedCount = unmarkedAsync.valueOrNull?.length ?? 0;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Attendance & Alerts',
                subtitle: 'Monitor attendance shortage, process unmarked slots, and configure rules',
                actions: [
                  OutlinedButton.icon(
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: const Text('Refresh'),
                    onPressed: () {
                      ref.invalidate(shortageReportProvider);
                      ref.invalidate(unmarkedSessionsTodayProvider);
                      ref.invalidate(attendanceSettingsProvider);
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Tab Bar Container
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: AppColors.brand,
                  unselectedLabelColor: AppColors.textMuted,
                  indicatorColor: AppColors.brand,
                  indicatorWeight: 3,
                  tabs: [
                    const Tab(
                      icon: Icon(LucideIcons.alertTriangle, size: 18),
                      text: 'Shortage & Low Attendance',
                    ),
                    Tab(
                      icon: Badge(
                        isLabelVisible: unmarkedCount > 0,
                        label: Text('$unmarkedCount'),
                        child: const Icon(LucideIcons.clock, size: 18),
                      ),
                      text: 'Unmarked Sessions Today',
                    ),
                    const Tab(
                      icon: Icon(LucideIcons.history, size: 18),
                      text: 'Session Review & Corrections',
                    ),
                    const Tab(
                      icon: Icon(LucideIcons.sliders, size: 18),
                      text: 'Attendance Settings',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Tab Views
              SizedBox(
                height: isMobile ? 850 : 680,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildShortageReportTab(isMobile),
                    _buildUnmarkedSessionsTab(isMobile),
                    _buildSessionReviewTab(isMobile),
                    _buildSettingsTab(isMobile),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Tab 1: Shortage & Low Attendance Report
  // ===========================================================================
  Widget _buildShortageReportTab(bool isMobile) {
    final filter = ref.watch(attendanceFilterProvider);
    final reportAsync = ref.watch(shortageReportProvider);
    final coursesAsync = ref.watch(coursesProvider);
    final batchesAsync = ref.watch(allBatchesProvider);

    return Column(
      children: [
        SectionCard(
          title: 'Report Filters',
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Course Filter
              Container(
                width: isMobile ? double.infinity : 200,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    isExpanded: true,
                    value: filter.courseId,
                    hint: const Text('All Courses'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Courses', overflow: TextOverflow.ellipsis)),
                      ...?coursesAsync.valueOrNull?.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (val) {
                      ref.read(attendanceFilterProvider.notifier).state = filter.copyWith(courseId: val, clearCourse: val == null);
                    },
                  ),
                ),
              ),

              // Batch Filter
              Container(
                width: isMobile ? double.infinity : 180,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    isExpanded: true,
                    value: filter.batchId,
                    hint: const Text('All Batches'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Batches', overflow: TextOverflow.ellipsis)),
                      ...?batchesAsync.valueOrNull?.map((b) => DropdownMenuItem(value: b['id'] as int, child: Text(b['name'] as String, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (val) {
                      ref.read(attendanceFilterProvider.notifier).state = filter.copyWith(batchId: val, clearBatch: val == null);
                    },
                  ),
                ),
              ),

              // Period Filter (Semester or Year depending on selected Course)
              Builder(
                builder: (context) {
                  final courses = coursesAsync.valueOrNull ?? [];
                  final selectedCourse = filter.courseId != null
                      ? courses.where((c) => c.id == filter.courseId).firstOrNull
                      : null;
                  final isYearWise = selectedCourse?.isYearWise == true;
                  final isSingle = selectedCourse?.isSingle == true;
                  final maxPeriods = selectedCourse != null
                      ? (isYearWise ? selectedCourse.durationYears : (isSingle ? 1 : selectedCourse.periodsCount))
                      : 6;

                  if (isSingle) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Single Period Course', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    );
                  }

                  return Container(
                    width: isMobile ? double.infinity : 160,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        isExpanded: true,
                        value: filter.semesterNo,
                        hint: Text(isYearWise ? 'All Years' : 'All Semesters'),
                        items: [
                          DropdownMenuItem(value: null, child: Text(isYearWise ? 'All Years' : 'All Semesters', overflow: TextOverflow.ellipsis)),
                          ...List.generate(maxPeriods, (i) => i + 1).map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(isYearWise ? 'Year $p' : 'Semester $p', overflow: TextOverflow.ellipsis),
                          )),
                        ],
                        onChanged: (val) {
                          ref.read(attendanceFilterProvider.notifier).state = filter.copyWith(semesterNo: val, clearSemester: val == null);
                        },
                      ),
                    ),
                  );
                },
              ),

              // Band Filter Segmented / Mobile Chips
              if (isMobile)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: filter.band == 'all',
                        onSelected: (_) => ref.read(attendanceFilterProvider.notifier).state = filter.copyWith(band: 'all'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Shortage (<75%)'),
                        selected: filter.band == 'shortage',
                        selectedColor: Colors.red.withValues(alpha: 0.15),
                        onSelected: (_) => ref.read(attendanceFilterProvider.notifier).state = filter.copyWith(band: 'shortage'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Low (75-80%)'),
                        selected: filter.band == 'low',
                        selectedColor: Colors.orange.withValues(alpha: 0.15),
                        onSelected: (_) => ref.read(attendanceFilterProvider.notifier).state = filter.copyWith(band: 'low'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Safe (>80%)'),
                        selected: filter.band == 'ok',
                        selectedColor: Colors.green.withValues(alpha: 0.15),
                        onSelected: (_) => ref.read(attendanceFilterProvider.notifier).state = filter.copyWith(band: 'ok'),
                      ),
                    ],
                  ),
                )
              else
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'shortage', label: Text('Shortage (<75%)')),
                    ButtonSegment(value: 'low', label: Text('Low (75-80%)')),
                    ButtonSegment(value: 'ok', label: Text('Safe (>80%)')),
                  ],
                  selected: {filter.band},
                  onSelectionChanged: (val) {
                    ref.read(attendanceFilterProvider.notifier).state = filter.copyWith(band: val.first);
                  },
                ),

              // Export Actions
              if (isMobile) ...[
                OutlinedButton.icon(
                  icon: const Icon(LucideIcons.fileSpreadsheet, size: 16),
                  label: const Text('Export Excel'),
                  onPressed: () => _exportReport(asPdf: false),
                ),
                OutlinedButton.icon(
                  icon: const Icon(LucideIcons.fileText, size: 16),
                  label: const Text('Export PDF'),
                  onPressed: () => _exportReport(asPdf: true),
                ),
              ]
              else ...[
                OutlinedButton.icon(
                  icon: const Icon(LucideIcons.fileSpreadsheet, size: 16),
                  label: const Text('Export Excel'),
                  onPressed: () => _exportReport(asPdf: false),
                ),
                OutlinedButton.icon(
                  icon: const Icon(LucideIcons.fileText, size: 16),
                  label: const Text('Export PDF'),
                  onPressed: () => _exportReport(asPdf: true),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Data Table / Mobile Cards
        Expanded(
          child: SectionCard(
            title: 'Student Attendance Summary',
            expanded: true,
            child: reportAsync.when(
              data: (data) {
                if (data.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text('No attendance records found for selected filters.', style: TextStyle(color: AppColors.textMuted)),
                    ),
                  );
                }

                if (isMobile) {
                  return ListView.separated(
                    itemCount: data.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final row = data[index];
                      final band = row['status_band']?.toString() ?? 'ok';
                      final pct = (row['percentage'] as num?)?.toDouble() ?? 100.0;
                      final miss = row['can_miss_more'] ?? 0;
                      final rec = row['recover_sessions'] ?? 0;
                      final sem = (row['semester_no'] as num?)?.toInt() ?? 1;
                      final yr = (sem + 1) ~/ 2;

                      Color bandColor;
                      String bandLabel;
                      String actionText;

                      if (band == 'shortage') {
                        bandColor = Colors.red;
                        bandLabel = 'Shortage';
                        actionText = 'Attend $rec consecutive sessions';
                      } else if (band == 'low') {
                        bandColor = Colors.orange;
                        bandLabel = 'Low Attendance';
                        actionText = miss > 0 ? 'Can miss $miss more' : 'Cannot miss any sessions';
                      } else {
                        bandColor = Colors.green;
                        bandLabel = 'Safe';
                        actionText = 'Can miss $miss more';
                      }

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          side: BorderSide(color: bandColor.withOpacity(0.3)),
                        ),
                        color: AppColors.surface,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(row['student_name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        const SizedBox(height: 2),
                                        Text(row['registration_number'] ?? row['admission_number'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: bandColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: bandColor.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      '${pct.toStringAsFixed(1)}% • $bandLabel',
                                      style: TextStyle(color: bandColor, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Text(
                                  '${row['batch_name'] ?? "Batch"} • Sem $sem (Yr $yr)',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(child: _buildStatPill('Held', '${row['sessions_held'] ?? 0}', AppColors.textStrong)),
                                    Expanded(child: _buildStatPill('Present', '${row['present_count'] ?? 0}', Colors.green)),
                                    Expanded(child: _buildStatPill('Late', '${row['late_count'] ?? 0}', Colors.orange)),
                                    Expanded(child: _buildStatPill('Absent', '${row['absent_count'] ?? 0}', Colors.red)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(LucideIcons.info, size: 14, color: bandColor),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Action: $actionText',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: bandColor),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(AppColors.bg),
                      columns: const [
                        DataColumn(label: Text('Student', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Batch', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Semester', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Sessions Held', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Present', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Late', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Absent', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Attendance %', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Status Band', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Action Needed', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: data.map((row) {
                        final band = row['status_band']?.toString() ?? 'ok';
                        final pct = (row['percentage'] as num?)?.toDouble() ?? 100.0;
                        final miss = row['can_miss_more'] ?? 0;
                        final rec = row['recover_sessions'] ?? 0;
                        final sem = (row['semester_no'] as num?)?.toInt() ?? 1;
                        final yr = (sem + 1) ~/ 2;

                        Color bandColor;
                        String bandLabel;
                        String actionText;

                        if (band == 'shortage') {
                          bandColor = Colors.red;
                          bandLabel = 'Shortage';
                          actionText = 'Attend $rec consecutive sessions';
                        } else if (band == 'low') {
                          bandColor = Colors.orange;
                          bandLabel = 'Low Attendance';
                          actionText = miss > 0 ? 'Can miss $miss more' : 'Cannot miss any sessions';
                        } else {
                          bandColor = Colors.green;
                          bandLabel = 'Normal';
                          actionText = 'Can miss $miss more';
                        }

                        return DataRow(
                          cells: [
                            DataCell(Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(row['student_name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(row['registration_number'] ?? row['admission_number'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              ],
                            )),
                            DataCell(Text(row['batch_name'] ?? 'N/A')),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Text(
                                  'Sem $sem (Yr $yr)',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                                ),
                              ),
                            ),
                            DataCell(Text('${row['sessions_held'] ?? 0}')),
                            DataCell(Text('${row['present_count'] ?? 0}', style: const TextStyle(color: Colors.green))),
                            DataCell(Text('${row['late_count'] ?? 0}', style: const TextStyle(color: Colors.orange))),
                            DataCell(Text('${row['absent_count'] ?? 0}', style: const TextStyle(color: Colors.red))),
                            DataCell(Text(
                              '${pct.toStringAsFixed(1)}%',
                              style: TextStyle(fontWeight: FontWeight.bold, color: bandColor),
                            )),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: bandColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: bandColor.withOpacity(0.3)),
                              ),
                              child: Text(bandLabel, style: TextStyle(color: bandColor, fontSize: 12, fontWeight: FontWeight.w600)),
                            )),
                            DataCell(Text(actionText, style: const TextStyle(fontSize: 12))),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error loading report: $err', style: const TextStyle(color: Colors.red))),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatPill(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Future<void> _exportReport({required bool asPdf}) async {
    final report = await ref.read(shortageReportProvider.future);
    if (report.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data to export.')));
      return;
    }

    final headers = ['Student Name', 'Reg No', 'Batch', 'Semester', 'Held', 'Present', 'Late', 'Absent', 'Percentage', 'Band'];
    final rows = report.map((r) => [
      r['student_name']?.toString() ?? '',
      r['registration_number']?.toString() ?? r['admission_number']?.toString() ?? '',
      r['batch_name']?.toString() ?? '',
      'Semester ${r['semester_no'] ?? 1}',
      r['sessions_held']?.toString() ?? '0',
      r['present_count']?.toString() ?? '0',
      r['late_count']?.toString() ?? '0',
      r['absent_count']?.toString() ?? '0',
      '${((r['percentage'] as num?)?.toDouble() ?? 100).toStringAsFixed(1)}%',
      r['status_band']?.toString() ?? 'ok',
    ]).toList();

    try {
      final path = asPdf
          ? await ReportGenerator.generatePdf('Attendance Shortage and Low Attendance Report', headers, rows)
          : await ReportGenerator.generateExcel('Attendance Shortage Report', headers, rows);

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Report exported to $path')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  // ===========================================================================
  // Tab 2: Unmarked Sessions Today
  // ===========================================================================
  Widget _buildUnmarkedSessionsTab(bool isMobile) {
    final unmarkedAsync = ref.watch(unmarkedSessionsTodayProvider);

    return SingleChildScrollView(
      child: SectionCard(
        title: 'Unmarked Sessions Today',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Classes with no submitted attendance records today. Confirm "No Class" to formally exclude from totals.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
            unmarkedAsync.when(
              data: (sessions) {
                if (sessions.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.checkCircle2, color: Colors.green, size: 48),
                          SizedBox(height: AppSpacing.sm),
                          Text('All sessions today are submitted or marked as No Class!', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('No forgotten attendance sessions detected.', style: TextStyle(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final s = sessions[index];
                    final batchName = s['batch_name'] ?? 'Batch #${s['batch_id']}';
                    final courseName = s['course_name'] ?? 'N/A';
                    final slot = s['slot']?.toString().toLowerCase() ?? 'morning';
                    final isMorning = slot == 'morning';

                    if (isMobile) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (isMorning ? Colors.orange : Colors.indigo).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isMorning ? LucideIcons.sun : LucideIcons.moon,
                                    color: isMorning ? Colors.orange : Colors.indigo,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('$batchName - ${isMorning ? "Morning Slot" : "Evening Slot"}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      Text(courseName, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.bg,
                                  foregroundColor: AppColors.textStrong,
                                ),
                                icon: const Icon(LucideIcons.calendarX, size: 16),
                                label: const Text('Confirm No Class'),
                                onPressed: () => _confirmNoClassDialog(
                                  batchId: s['batch_id'] as int,
                                  batchName: batchName,
                                  slot: slot,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (isMorning ? Colors.orange : Colors.indigo).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isMorning ? LucideIcons.sun : LucideIcons.moon,
                              color: isMorning ? Colors.orange : Colors.indigo,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$batchName - ${isMorning ? "Morning Slot" : "Evening Slot"}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text(courseName, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.bg,
                              foregroundColor: AppColors.textStrong,
                            ),
                            icon: const Icon(LucideIcons.calendarX, size: 16),
                            label: const Text('Confirm No Class'),
                            onPressed: () => _confirmNoClassDialog(
                              batchId: s['batch_id'] as int,
                              batchName: batchName,
                              slot: slot,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
              error: (err, _) => Center(child: Text('Error loading unmarked slots: $err', style: const TextStyle(color: Colors.red))),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmNoClassDialog({
    required int batchId,
    required String batchName,
    required String slot,
  }) {
    final reasonController = TextEditingController(text: 'Holiday / No classes conducted');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm No Class: $batchName ($slot)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This slot will be marked as "No Class" and will be strictly excluded from students\' total class days.'),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason (Optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final repo = ref.read(attendanceAdminRepositoryProvider);
                await repo.confirmNoClass(
                  batchId: batchId,
                  date: DateTime.now(),
                  slot: slot,
                  reason: reasonController.text.trim(),
                );
                ref.invalidate(unmarkedSessionsTodayProvider);
                ref.invalidate(attendanceReviewSessionsProvider);
                ref.invalidate(todayAttendanceSlotStatusProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Successfully confirmed No Class for $batchName ($slot)')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Tab 3: Attendance Settings
  // ===========================================================================
  Widget _buildSettingsTab(bool isMobile) {
    final settingsAsync = ref.watch(attendanceSettingsProvider);

    return settingsAsync.when(
      data: (settings) {
        _minPercent = (settings['min_attendance_percent'] as num?)?.toDouble() ?? _minPercent;
        _reminderPercent = (settings['reminder_attendance_percent'] as num?)?.toDouble() ?? _reminderPercent;
        _lateWeight = (settings['late_weight'] as num?)?.toDouble() ?? _lateWeight;
        _leaveHandling = settings['leave_handling']?.toString() ?? _leaveHandling;

        return SingleChildScrollView(
          child: SectionCard(
            title: 'Institutional Attendance Thresholds',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(
                    'Define percentage bands and calculation behavior across all courses and batches',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ),
                // Minimum Attendance Percentage
                if (isMobile) ...[
                  Text('Minimum Required Attendance: ${_minPercent.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  const Text('Falling below this threshold triggers the mandatory Shortage Warning', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  Slider(
                    value: _minPercent,
                    min: 50,
                    max: 90,
                    divisions: 40,
                    label: '${_minPercent.toInt()}%',
                    onChanged: (val) => setState(() => _minPercent = val),
                  ),
                ] else ...[
                  ListTile(
                    title: Text('Minimum Required Attendance: ${_minPercent.toInt()}%'),
                    subtitle: const Text('Falling below this threshold triggers the mandatory Shortage Warning'),
                    trailing: SizedBox(
                      width: 200,
                      child: Slider(
                        value: _minPercent,
                        min: 50,
                        max: 90,
                        divisions: 40,
                        label: '${_minPercent.toInt()}%',
                        onChanged: (val) => setState(() => _minPercent = val),
                      ),
                    ),
                  ),
                ],
                const Divider(),

                // Reminder Threshold
                if (isMobile) ...[
                  Text('Low Attendance Reminder: ${_reminderPercent.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  const Text('Students at or below this percentage receive the Low Attendance Reminder', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  Slider(
                    value: _reminderPercent,
                    min: _minPercent,
                    max: 95,
                    divisions: (95 - _minPercent).toInt(),
                    label: '${_reminderPercent.toInt()}%',
                    onChanged: (val) => setState(() => _reminderPercent = val),
                  ),
                ] else ...[
                  ListTile(
                    title: Text('Low Attendance Reminder: ${_reminderPercent.toInt()}%'),
                    subtitle: const Text('Students at or below this percentage receive the Low Attendance Reminder'),
                    trailing: SizedBox(
                      width: 200,
                      child: Slider(
                        value: _reminderPercent,
                        min: _minPercent,
                        max: 95,
                        divisions: (95 - _minPercent).toInt(),
                        label: '${_reminderPercent.toInt()}%',
                        onChanged: (val) => setState(() => _reminderPercent = val),
                      ),
                    ),
                  ),
                ],
                const Divider(),

                // Late Attendance Weight
                if (isMobile) ...[
                  Text('Late Weight: $_lateWeight', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  const Text('Weight assigned to Late presence (0.5 = counts as half a present)', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  Slider(
                    value: _lateWeight,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    label: '$_lateWeight',
                    onChanged: (val) => setState(() => _lateWeight = val),
                  ),
                ] else ...[
                  ListTile(
                    title: Text('Late Weight: $_lateWeight'),
                    subtitle: const Text('Weight assigned to Late presence (0.5 = counts as half a present)'),
                    trailing: SizedBox(
                      width: 200,
                      child: Slider(
                        value: _lateWeight,
                        min: 0.0,
                        max: 1.0,
                        divisions: 10,
                        label: '$_lateWeight',
                        onChanged: (val) => setState(() => _lateWeight = val),
                      ),
                    ),
                  ),
                ],
                const Divider(),

                // Approved Leave Handling
                if (isMobile) ...[
                  const Text('Approved Leave Handling', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  const Text('How approved leaves affect the total class count', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _leaveHandling,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'excluded', child: Text('Excluded (Neither for/against)')),
                      DropdownMenuItem(value: 'absent', child: Text('Counts as Absent')),
                      DropdownMenuItem(value: 'present', child: Text('Counts as Present')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _leaveHandling = val);
                    },
                  ),
                ] else ...[
                  ListTile(
                    title: const Text('Approved Leave Handling'),
                    subtitle: const Text('How approved leaves affect the total class count'),
                    trailing: DropdownButton<String>(
                      value: _leaveHandling,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'excluded', child: Text('Excluded (Counts neither for nor against)')),
                        DropdownMenuItem(value: 'absent', child: Text('Counts as Absent')),
                        DropdownMenuItem(value: 'present', child: Text('Counts as Present')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _leaveHandling = val);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),

                // Save Button
                Align(
                  alignment: isMobile ? Alignment.center : Alignment.centerRight,
                  child: SizedBox(
                    width: isMobile ? double.infinity : null,
                    child: FilledButton.icon(
                      icon: _isSavingSettings
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(LucideIcons.save, size: 16),
                      label: const Text('Save Attendance Settings'),
                      onPressed: _isSavingSettings ? null : _saveAttendanceSettings,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error loading settings: $err', style: const TextStyle(color: Colors.red))),
    );
  }

  Future<void> _saveAttendanceSettings() async {
    setState(() => _isSavingSettings = true);
    try {
      final repo = ref.read(attendanceAdminRepositoryProvider);
      await repo.updateAttendanceSettings({
        'min_attendance_percent': _minPercent,
        'reminder_attendance_percent': _reminderPercent,
        'late_weight': _lateWeight,
        'leave_handling': _leaveHandling,
      });
      ref.invalidate(attendanceSettingsProvider);
      ref.invalidate(shortageReportProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance settings saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save settings: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSavingSettings = false);
    }
  }

  // ===========================================================================
  // Tab 3: Session Review & Corrections
  // ===========================================================================
  Widget _buildSessionReviewTab(bool isMobile) {
    final selectedDate = ref.watch(reviewSessionsDateProvider);
    final sessionsAsync = ref.watch(attendanceReviewSessionsProvider);

    return SectionCard(
      title: 'Session Review & Administrative Corrections',
      trailing: OutlinedButton.icon(
        icon: const Icon(LucideIcons.calendar, size: 14),
        label: Text(
          '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}',
        ),
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: selectedDate,
            firstDate: DateTime(2020),
            lastDate: DateTime.now(),
          );
          if (picked != null) {
            ref.read(reviewSessionsDateProvider.notifier).state = picked;
          }
        },
      ),
      child: sessionsAsync.when(
        data: (sessions) {
          if (sessions.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No attendance sessions recorded for the selected date.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            );
          }

          if (isMobile) {
            return ListView.separated(
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final s = sessions[index];
                final date = s['date']?.toString() ?? 'N/A';
                final batchName = s['batches']?['batch_name']?.toString() ?? 'Batch #${s['batch_id']}';
                final slot = (s['slot']?.toString() ?? 'morning').toUpperCase();
                final status = s['status']?.toString() ?? 'submitted';
                final markedBy = s['teachers']?['name']?.toString() ?? 'Administrator';

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  color: AppColors.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('$batchName • $slot', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: status == 'submitted' ? const Color(0xFFE3F6EC) : const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status == 'submitted' ? 'Submitted' : 'No Class',
                                style: TextStyle(
                                  color: status == 'submitted' ? const Color(0xFF0B5D3B) : const Color(0xFF475569),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(LucideIcons.userCheck, size: 13, color: AppColors.brand),
                            const SizedBox(width: 5),
                            Text('Marked by: $markedBy', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            icon: const Icon(LucideIcons.edit2, size: 14),
                            label: const Text('Review & Correct Records', style: TextStyle(fontSize: 12)),
                            onPressed: () => _openCorrectionDialog(
                              s['id'] as int,
                              batchName,
                              slot,
                              date,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Batch', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Slot', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Marked By', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Submitted At', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: sessions.map((s) {
                final date = s['date']?.toString() ?? 'N/A';
                final batchName = s['batches']?['batch_name']?.toString() ?? 'Batch #${s['batch_id']}';
                final slot = (s['slot']?.toString() ?? 'morning').toUpperCase();
                final status = s['status']?.toString() ?? 'submitted';
                final markedBy = s['teachers']?['name']?.toString() ?? 'Administrator';
                final submittedAtRaw = s['submitted_at']?.toString() ?? '';
                String submittedAt = '';
                if (submittedAtRaw.isNotEmpty) {
                  try {
                    final dt = DateTime.parse(submittedAtRaw).toLocal();
                    submittedAt = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                  } catch (_) {}
                }

                return DataRow(
                  cells: [
                    DataCell(Text(date)),
                    DataCell(Text(batchName, style: const TextStyle(fontWeight: FontWeight.w600))),
                    DataCell(Text(slot)),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: status == 'submitted' ? const Color(0xFFE3F6EC) : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status == 'submitted' ? 'Submitted' : 'No Class',
                        style: TextStyle(
                          color: status == 'submitted' ? const Color(0xFF0B5D3B) : const Color(0xFF475569),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    )),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.userCheck, size: 14, color: AppColors.brand),
                        const SizedBox(width: 6),
                        Text(markedBy, style: const TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    )),
                    DataCell(Text(submittedAt.isNotEmpty ? submittedAt : 'N/A')),
                    DataCell(
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        icon: const Icon(LucideIcons.edit2, size: 13),
                        label: const Text('Correct', style: TextStyle(fontSize: 12)),
                        onPressed: () => _openCorrectionDialog(
                          s['id'] as int,
                          batchName,
                          slot,
                          date,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (err, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('Failed to load sessions: $err', style: const TextStyle(color: Colors.red))),
        ),
      ),
    );
  }

  void _openCorrectionDialog(int sessionId, String batchName, String slot, String date) async {
    final repo = ref.read(attendanceAdminRepositoryProvider);
    final records = await repo.getSessionRecords(sessionId);

    if (!mounted) return;

    final reasonCtrl = TextEditingController();
    final Map<int, String> newStatuses = {
      for (var r in records) r['id'] as int: (r['status']?.toString() ?? 'present').toLowerCase(),
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Administrative Attendance Correction: $batchName', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Text('$slot Slot • $date', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
          content: SizedBox(
            width: 580,
            height: 400,
            child: Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    itemCount: records.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = records[i];
                      final recId = r['id'] as int;
                      final sName = r['students']?['name'] ?? 'Student';
                      final admNo = r['students']?['admission_number'] ?? '';
                      final currentStatus = newStatuses[recId] ?? 'present';

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(sName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(admNo, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        trailing: DropdownButton<String>(
                          value: currentStatus,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 'present', child: Text('Present', style: TextStyle(color: Colors.green))),
                            DropdownMenuItem(value: 'late', child: Text('Late (0.5)', style: TextStyle(color: Colors.orange))),
                            DropdownMenuItem(value: 'absent', child: Text('Absent', style: TextStyle(color: Colors.red))),
                            DropdownMenuItem(value: 'leave', child: Text('Leave', style: TextStyle(color: Colors.grey))),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDlgState(() => newStatuses[recId] = val);
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mandatory Reason for Correction *',
                    hintText: 'e.g., Medical certificate submitted / Late arrival excused',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: const Icon(LucideIcons.check, size: 16),
              label: const Text('Save Corrections'),
              onPressed: () async {
                final reason = reasonCtrl.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reason for correction is mandatory per policy.')),
                  );
                  return;
                }

                Navigator.of(ctx).pop();

                try {
                  for (final entry in newStatuses.entries) {
                    final original = records.firstWhere((r) => r['id'] == entry.key);
                    if (original['status'] != entry.value) {
                      await repo.correctAttendanceRecord(
                        recordId: entry.key,
                        newStatus: entry.value,
                        reason: reason,
                      );
                    }
                  }

                  ref.invalidate(attendanceReviewSessionsProvider);
                  ref.invalidate(shortageReportProvider);
                  ref.invalidate(todayAttendanceSlotStatusProvider);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Attendance records corrected successfully.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to apply corrections: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
