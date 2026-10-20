import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/section_card.dart';
import '../courses/course_provider.dart';
import 'reports_provider.dart';
import 'report_generator.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  int? _selectedCourseId;
  int? _selectedBatchId;
  bool _isLoading = false;

  void _showError(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showSuccess(String path) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
  }

  // 1. Fee Collection
  Future<void> _generateFeeCollection(bool asPdf) async {
    if (_startDate == null || _endDate == null) {
      _showError('Please select start and end dates.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final s = DateFormat('yyyy-MM-dd').format(_startDate!);
      final e = DateFormat('yyyy-MM-dd').format(_endDate!);
      final data = await ref.read(reportsServiceProvider).getFeeCollection(s, e);
      if (data.isEmpty) { _showError('No data found.'); return; }

      final headers = ['Date', 'Student', 'Adm No', 'Course', 'Amount (Rs)', 'Mode', 'Ref No'];
      final rows = data.map((d) => [
        d['date'], d['student_name'], d['admission_number'], d['course_name'],
        d['amount'], d['payment_mode'], d['reference_number']
      ]).toList();

      final title = 'Fee Collection Report ($s to $e)';
      final path = asPdf ? await ReportGenerator.generatePdf(title, headers, rows)
                         : await ReportGenerator.generateExcel(title, headers, rows);
      _showSuccess(path);
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 2. Defaulters
  Future<void> _generateDefaulters(bool asPdf) async {
    setState(() => _isLoading = true);
    try {
      final data = await ref.read(reportsServiceProvider).getDefaultersList();
      if (data.isEmpty) { _showError('No data found.'); return; }

      final headers = ['Student', 'Adm No', 'Phone', 'Course', 'Batch', 'Fee Head', 'Due Date', 'Pending (Rs)'];
      final rows = data.map((d) => [
        d['student_name'], d['admission_number'], d['phone'], d['course_name'],
        d['batch_name'], d['fee_head'], d['due_date'], d['pending_amount']
      ]).toList();

      final title = 'Fee Defaulters List';
      final path = asPdf ? await ReportGenerator.generatePdf(title, headers, rows)
                         : await ReportGenerator.generateExcel(title, headers, rows);
      _showSuccess(path);
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 3. Batch Results
  Future<void> _generateBatchResults(bool asPdf) async {
    if (_selectedCourseId == null || _selectedBatchId == null) {
      _showError('Please select Course and Batch.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final data = await ref.read(reportsServiceProvider).getBatchWiseResults(_selectedCourseId!, _selectedBatchId!);
      if (data.isEmpty) { _showError('No data found.'); return; }

      final headers = ['Student', 'Adm No', 'Exam', 'Total Marks', 'Percentage', 'Grade', 'Status'];
      final rows = data.map((d) => [
        d['student_name'], d['admission_number'], d['exam_name'],
        d['total_marks'], d['percentage']?.toStringAsFixed(2), d['grade'], d['status']
      ]).toList();

      final title = 'Batch-wise Results';
      final path = asPdf ? await ReportGenerator.generatePdf(title, headers, rows)
                         : await ReportGenerator.generateExcel(title, headers, rows);
      _showSuccess(path);
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 4. Student List
  Future<void> _generateStudentList(bool asPdf) async {
    if (_selectedCourseId == null || _selectedBatchId == null) {
      _showError('Please select Course and Batch.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final data = await ref.read(reportsServiceProvider).getStudentList(_selectedCourseId!, _selectedBatchId!);
      if (data.isEmpty) { _showError('No data found.'); return; }

      final headers = ['Name', 'Adm No', 'Reg No', 'Gender', 'Phone', 'Status'];
      final rows = data.map((d) => [
        d['name'], d['admission_number'], d['registration_number'],
        d['gender'], d['phone'], d['status']
      ]).toList();

      final title = 'Student List';
      final path = asPdf ? await ReportGenerator.generatePdf(title, headers, rows)
                         : await ReportGenerator.generateExcel(title, headers, rows);
      _showSuccess(path);
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 5. Course Revenue
  Future<void> _generateCourseRevenue(bool asPdf) async {
    setState(() => _isLoading = true);
    try {
      final data = await ref.read(reportsServiceProvider).getCourseRevenue();
      if (data.isEmpty) { _showError('No data found.'); return; }

      final headers = ['Course', 'Code', 'Students', 'Total Revenue (Rs)', 'Collected (Rs)', 'Outstanding (Rs)'];
      final rows = data.map((d) => [
        d['course_name'],
        d['course_code'],
        d['total_students'] ?? d['enrolled_students'] ?? 0,
        d['total_revenue'] ?? (((d['total_revenue_paise'] as num?)?.toDouble() ?? 0) / 100.0),
        d['total_collected'] ?? (((d['total_collected_paise'] as num?)?.toDouble() ?? 0) / 100.0),
        d['total_pending'] ?? (((d['total_pending_paise'] as num?)?.toDouble() ?? 0) / 100.0),
      ]).toList();

      final title = 'Course Financial Summary';
      final path = asPdf ? await ReportGenerator.generatePdf(title, headers, rows)
                         : await ReportGenerator.generateExcel(title, headers, rows);
      _showSuccess(path);
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null ? DateTimeRange(start: _startDate!, end: _endDate!) : null,
    );
    if (range != null) {
      setState(() {
        _startDate = range.start;
        _endDate = range.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesProvider);
    final batchesAsync = ref.watch(allBatchesProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 750;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Reports',
              subtitle: 'Generate and export data for analytics and compliance.',
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
                child: Column(
                  children: [
                    // Global Filters
                    SectionCard(
                      title: 'Global Parameters',
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 750;
                          final datePicker = SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDateRange(context),
                              icon: const Icon(LucideIcons.calendar, size: 16),
                              label: Text(
                                _startDate != null && _endDate != null
                                    ? '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}'
                                    : 'Select Date Range',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );

                          final courseDropdown = coursesAsync.when(
                            data: (courses) => DropdownButtonFormField<int>(
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Course'),
                              value: _selectedCourseId,
                              items: courses.map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name, overflow: TextOverflow.ellipsis),
                              )).toList(),
                              onChanged: (v) => setState(() => _selectedCourseId = v),
                            ),
                            loading: () => const LinearProgressIndicator(),
                            error: (_,__) => const SizedBox(),
                          );

                          final batchDropdown = batchesAsync.when(
                            data: (batches) => DropdownButtonFormField<int>(
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Batch'),
                              value: _selectedBatchId,
                              items: batches.map((b) => DropdownMenuItem(
                                value: b['id'] as int,
                                child: Text(b['name'] as String, overflow: TextOverflow.ellipsis),
                              )).toList(),
                              onChanged: (v) => setState(() => _selectedBatchId = v),
                            ),
                            loading: () => const LinearProgressIndicator(),
                            error: (_,__) => const SizedBox(),
                          );

                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                datePicker,
                                const SizedBox(height: AppSpacing.md),
                                courseDropdown,
                                const SizedBox(height: AppSpacing.md),
                                batchDropdown,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(flex: 3, child: datePicker),
                              const SizedBox(width: AppSpacing.lg),
                              Expanded(flex: 4, child: courseDropdown),
                              const SizedBox(width: AppSpacing.lg),
                              Expanded(flex: 3, child: batchDropdown),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    
                    // Reports Grid
                    GridView.count(
                      crossAxisCount: isMobile ? 1 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: isMobile ? AppSpacing.md : AppSpacing.xl,
                      mainAxisSpacing: isMobile ? AppSpacing.md : AppSpacing.xl,
                      childAspectRatio: isMobile ? 2.1 : 2.5,
                      children: [
                        _ReportCard(
                          title: 'Fee Collection',
                          subtitle: 'View payments collected in the selected date range.',
                          icon: LucideIcons.indianRupee,
                          onExcel: () => _generateFeeCollection(false),
                          onPdf: () => _generateFeeCollection(true),
                        ),
                        _ReportCard(
                          title: 'Defaulters List',
                          subtitle: 'List of students with pending fee installments.',
                          icon: LucideIcons.alertTriangle,
                          onExcel: () => _generateDefaulters(false),
                          onPdf: () => _generateDefaulters(true),
                        ),
                        _ReportCard(
                          title: 'Batch-wise Results',
                          subtitle: 'Academic results for the selected Course and Batch.',
                          icon: LucideIcons.graduationCap,
                          onExcel: () => _generateBatchResults(false),
                          onPdf: () => _generateBatchResults(true),
                        ),
                        _ReportCard(
                          title: 'Student List',
                          subtitle: 'Directory of students in the selected Course and Batch.',
                          icon: LucideIcons.users,
                          onExcel: () => _generateStudentList(false),
                          onPdf: () => _generateStudentList(true),
                        ),
                        _ReportCard(
                          title: 'Course Financial Summary',
                          subtitle: 'Revenue, collected fees, and outstanding dues per course.',
                          icon: LucideIcons.pieChart,
                          onExcel: () => _generateCourseRevenue(false),
                          onPdf: () => _generateCourseRevenue(true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onExcel;
  final VoidCallback onPdf;

  const _ReportCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onExcel,
    required this.onPdf,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.reports.tint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.reports.base),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onExcel,
                  icon: const Icon(LucideIcons.fileSpreadsheet, size: 16, color: Colors.green),
                  label: const Text('Excel'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPdf,
                  icon: const Icon(LucideIcons.fileText, size: 16, color: Colors.red),
                  label: const Text('PDF'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

