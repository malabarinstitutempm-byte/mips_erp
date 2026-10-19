import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/batch.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../courses/course_provider.dart';
import 'batch_completion_dialog.dart';

class YearPromotionDialog extends ConsumerStatefulWidget {
  final Batch batch;
  final VoidCallback onPromoted;

  const YearPromotionDialog({
    super.key,
    required this.batch,
    required this.onPromoted,
  });

  static Future<void> show(
    BuildContext context, {
    required Batch batch,
    required VoidCallback onPromoted,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => YearPromotionDialog(batch: batch, onPromoted: onPromoted),
    );
  }

  @override
  ConsumerState<YearPromotionDialog> createState() => _YearPromotionDialogState();
}

class _YearPromotionDialogState extends ConsumerState<YearPromotionDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _previewData;

  DateTime _closingEndDate = DateTime.now();
  DateTime _newStartDate = DateTime.now().add(const Duration(days: 1));
  bool _isPromoting = false;

  @override
  void initState() {
    super.initState();
    _fetchPreview();
  }

  Future<void> _fetchPreview() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(batchRepositoryProvider);
      final preview = await repo.previewYearPromotion(widget.batch.id!);
      if (mounted) {
        setState(() {
          _previewData = preview;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _executePromotion() async {
    if (_newStartDate.isBefore(_closingEndDate) || _newStartDate.isAtSameMomentAs(_closingEndDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('New academic year start date must be after the closing year end date.'),
        ),
      );
      return;
    }

    setState(() => _isPromoting = true);

    try {
      final repo = ref.read(batchRepositoryProvider);
      final res = await repo.promoteYear(
        widget.batch.id!,
        _closingEndDate,
        _newStartDate,
      );

      if (!mounted) return;

      Navigator.of(context).pop(); // Close dialog

      // Show result summary dialog
      final nextYr = res['promoted_to_year'] ?? (_previewData?['next_year'] ?? (widget.batch.currentYear + 1));
      final count = res['students_notified'] ?? (_previewData?['total_students'] ?? 0);

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          title: Row(
            children: const [
              Icon(LucideIcons.checkCircle2, color: Color(0xFF16A34A), size: 24),
              SizedBox(width: 10),
              Text('Academic Year Promotion Completed', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Batch "${widget.batch.batchName}" is now promoted to Year $nextYr!',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textStrong),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• Notification dispatched to $count active student(s).', style: const TextStyle(fontSize: 13, color: Color(0xFF166534))),
                    const SizedBox(height: 4),
                    const Text('• Attendance alert states have been reset for the new academic year.', style: TextStyle(fontSize: 13, color: Color(0xFF166534))),
                    const SizedBox(height: 4),
                    const Text('• Faculty academic bulletin published.', style: TextStyle(fontSize: 13, color: Color(0xFF166534))),
                    const SizedBox(height: 4),
                    const Text('• Institutional audit log entry recorded.', style: TextStyle(fontSize: 13, color: Color(0xFF166534))),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );

      widget.onPromoted();
    } catch (e) {
      if (mounted) {
        setState(() => _isPromoting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Promotion failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final curYr = _previewData?['current_year'] ?? widget.batch.currentYear;
    final nextYr = _previewData?['next_year'] ?? (curYr + 1);
    final totalYears = _previewData?['max_years'] ?? _previewData?['total_years'] ?? (widget.batch.endYear != null && widget.batch.startYear != null ? (widget.batch.endYear! - widget.batch.startYear!) : 3);
    final isFinal = _previewData?['is_final_year'] == true;
    final totalCount = _previewData?['active_students_count'] ?? _previewData?['total_students'] ?? 0;

    final attSummary = _previewData?['attendance_summary'] as Map<String, dynamic>?;
    final examSummary = _previewData?['exam_summary'] as Map<String, dynamic>?;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: const Icon(LucideIcons.arrowUpCircle, color: Color(0xFF2563EB), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Promote Batch to Year $nextYr',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                              ),
                              Text(
                                '${widget.batch.batchName} • Currently Year $curYr of $totalYears',
                                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isPromoting ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Content Area
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(LucideIcons.alertCircle, color: Colors.red, size: 36),
                                const SizedBox(height: 8),
                                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                                const SizedBox(height: 12),
                                OutlinedButton(onPressed: _fetchPreview, child: const Text('Retry')),
                              ],
                            ),
                          )
                        : isFinal
                            ? _buildFinalYearView(curYr, totalYears)
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Year advancement summary notice
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFBFDBFE)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(LucideIcons.graduationCap, color: Color(0xFF2563EB), size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Promoting advances this batch to Academic Year $nextYr. Year $curYr will be closed and new academic period records established.',
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E40AF)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Date pickers row
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: AppColors.bg,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('Closing Year End Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textStrong)),
                                                const SizedBox(height: 6),
                                                InkWell(
                                                  onTap: () async {
                                                    final picked = await showDatePicker(
                                                      context: context,
                                                      initialDate: _closingEndDate,
                                                      firstDate: DateTime(2020),
                                                      lastDate: DateTime(2035),
                                                    );
                                                    if (picked != null) {
                                                      setState(() {
                                                        _closingEndDate = picked;
                                                        if (_newStartDate.isBefore(picked) || _newStartDate.isAtSameMomentAs(picked)) {
                                                          _newStartDate = picked.add(const Duration(days: 1));
                                                        }
                                                      });
                                                    }
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: AppColors.border),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Text(dateFormat.format(_closingEndDate), style: const TextStyle(fontSize: 13)),
                                                        const Icon(LucideIcons.calendar, size: 16, color: AppColors.textMuted),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Year $nextYr Start Date', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textStrong)),
                                                const SizedBox(height: 6),
                                                InkWell(
                                                  onTap: () async {
                                                    final picked = await showDatePicker(
                                                      context: context,
                                                      initialDate: _newStartDate,
                                                      firstDate: _closingEndDate.add(const Duration(days: 1)),
                                                      lastDate: DateTime(2035),
                                                    );
                                                    if (picked != null) {
                                                      setState(() => _newStartDate = picked);
                                                    }
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: AppColors.border),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Text(dateFormat.format(_newStartDate), style: const TextStyle(fontSize: 13)),
                                                        const Icon(LucideIcons.calendar, size: 16, color: AppColors.textMuted),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Metrics Cards
                                    Row(
                                      children: [
                                        _metricCard('Students in Batch', '$totalCount', LucideIcons.users, const Color(0xFF2563EB), const Color(0xFFEFF6FF)),
                                        const SizedBox(width: 12),
                                        _metricCard('Sessions Held', '${attSummary?['total_sessions'] ?? 0}', LucideIcons.calendarCheck, const Color(0xFF059669), const Color(0xFFECFDF5)),
                                        const SizedBox(width: 12),
                                        _metricCard('Eligible (>=75%)', '${attSummary?['eligible_students'] ?? 0}', LucideIcons.checkCheck, const Color(0xFF16A34A), const Color(0xFFF0FDF4)),
                                        const SizedBox(width: 12),
                                        _metricCard('Condonation (<75%)', '${attSummary?['condonation_students'] ?? 0}', LucideIcons.alertTriangle, const Color(0xFFD97706), const Color(0xFFFEF3C7)),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Exam Readiness Status
                                    if (examSummary != null) ...[
                                      const Text('Academic Year Exam Status', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: (examSummary['pending_marks_exams'] ?? 0) > 0 ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: (examSummary['pending_marks_exams'] ?? 0) > 0 ? const Color(0xFFFDE68A) : AppColors.border),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              (examSummary['pending_marks_exams'] ?? 0) > 0 ? LucideIcons.alertCircle : LucideIcons.checkCircle,
                                              color: (examSummary['pending_marks_exams'] ?? 0) > 0 ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                                              size: 20,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${examSummary['total_exams'] ?? 0} total exam(s) in Year $curYr • ${examSummary['pending_marks_exams'] ?? 0} pending mark entry • ${examSummary['draft_exams'] ?? 0} unpublished',
                                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textStrong),
                                                  ),
                                                  if ((examSummary['pending_marks_exams'] ?? 0) > 0)
                                                    const Text(
                                                      'Notice: Some exams for this year still have pending marks. Promotion will advance the batch to the next year regardless.',
                                                      style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isPromoting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  if (!isFinal)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: (_isLoading || _errorMessage != null || _isPromoting) ? null : _executePromotion,
                      icon: _isPromoting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(LucideIcons.arrowUpRight, size: 16),
                      label: Text(_isPromoting ? 'Promoting...' : 'Promote to Year $nextYr'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis),
                  Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinalYearView(int curYr, int totalYears) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F3FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDD6FE)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.award, size: 48, color: Color(0xFF7C3AED)),
            const SizedBox(height: 12),
            const Text(
              'Final Academic Year Reached',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5B21B6)),
            ),
            const SizedBox(height: 8),
            Text(
              'Batch "${widget.batch.batchName}" is already in Year $curYr of $totalYears (the final year of this course).\n\nYear-wise batches in their final year cannot be promoted further. To graduate this batch, use the "Mark Batch Completed" workflow.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6D28D9), height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                BatchCompletionDialog.show(
                  context,
                  batch: widget.batch,
                  onCompleted: widget.onPromoted,
                );
              },
              icon: const Icon(LucideIcons.checkCheck, size: 16),
              label: const Text('Proceed to Batch Completion'),
            ),
          ],
        ),
      ),
    );
  }
}
