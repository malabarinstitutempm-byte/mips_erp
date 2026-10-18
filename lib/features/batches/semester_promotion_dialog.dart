import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/batch.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../courses/course_provider.dart';
import 'batch_completion_dialog.dart';

class SemesterPromotionDialog extends ConsumerStatefulWidget {
  final Batch batch;
  final VoidCallback onPromoted;

  const SemesterPromotionDialog({
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
      builder: (_) => SemesterPromotionDialog(batch: batch, onPromoted: onPromoted),
    );
  }

  @override
  ConsumerState<SemesterPromotionDialog> createState() => _SemesterPromotionDialogState();
}

class _SemesterPromotionDialogState extends ConsumerState<SemesterPromotionDialog> {
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
      final preview = await repo.previewSemesterPromotion(widget.batch.id!);
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
          content: Text('New semester start date must be after the closing semester end date.'),
        ),
      );
      return;
    }

    setState(() => _isPromoting = true);

    try {
      final repo = ref.read(batchRepositoryProvider);
      final res = await repo.promoteSemester(
        widget.batch.id!,
        _closingEndDate,
        _newStartDate,
      );

      if (!mounted) return;

      Navigator.of(context).pop(); // Close dialog

      // Show result summary dialog
      final nextSem = res['promoted_to_semester'] ?? (_previewData?['next_semester'] ?? 2);
      final nextYr = res['promoted_to_year'] ?? (_previewData?['next_year'] ?? 1);
      final count = res['students_notified'] ?? (_previewData?['total_students'] ?? 0);

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          title: Row(
            children: const [
              Icon(LucideIcons.checkCircle2, color: Color(0xFF16A34A), size: 24),
              SizedBox(width: 10),
              Text('Semester Promotion Completed', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Batch "${widget.batch.batchName}" is now promoted to Semester $nextSem (Year $nextYr)!',
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
                    const Text('• Attendance alert states have been reset for the new semester.', style: TextStyle(fontSize: 13, color: Color(0xFF166534))),
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
    final curSem = _previewData?['current_semester'] ?? widget.batch.currentSemester;
    final curYr = _previewData?['current_year'] ?? widget.batch.currentYear;
    final nextSem = _previewData?['next_semester'] ?? (curSem + 1);
    final nextYr = _previewData?['next_year'] ?? ((nextSem + 1) ~/ 2);
    final isFinal = _previewData?['is_final_semester'] == true;
    final yearWillChange = _previewData?['year_will_change'] == true;
    final students = (_previewData?['students'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final totalCount = _previewData?['total_students'] ?? students.length;
    final belowCount = _previewData?['below_minimum_count'] ?? students.where((s) => s['below_minimum'] == true).length;

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
                  Row(
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Promote Batch to Semester $nextSem',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                          ),
                          Text(
                            '${widget.batch.batchName} • Currently Semester $curSem (Year $curYr)',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ],
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
                            ? _buildFinalSemesterView()
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Year advancement notice if year changes
                                    if (yearWillChange) ...[
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFFDE68A)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(LucideIcons.sparkles, color: Color(0xFFD97706), size: 18),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                'This also moves the batch to Year $nextYr (Semester $nextSem). Timetable allocations and academic records will reflect the new year.',
                                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                    ],

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
                                                const Text('Closing Semester End Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textStrong)),
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
                                                Text('Semester $nextSem Start Date', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textStrong)),
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

                                    // Metrics Bar
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text('Total Students: $totalCount', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: belowCount > 0 ? const Color(0xFFFEF3C7) : const Color(0xFFF0FDF4),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: belowCount > 0 ? const Color(0xFFFDE68A) : const Color(0xFFBBF7D0)),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                belowCount > 0 ? LucideIcons.alertTriangle : LucideIcons.check,
                                                size: 14,
                                                color: belowCount > 0 ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Below Minimum (<75%): $belowCount',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: belowCount > 0 ? const Color(0xFF92400E) : const Color(0xFF166534),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // Student Preview Table
                                    const Text('Closing Semester Attendance Preview', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                                    const SizedBox(height: 8),
                                    Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: AppColors.border),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: students.isEmpty
                                          ? const Padding(
                                              padding: EdgeInsets.all(24),
                                              child: Center(child: Text('No active students found in this batch.', style: TextStyle(color: AppColors.textMuted))),
                                            )
                                          : Table(
                                              columnWidths: const {
                                                0: FlexColumnWidth(3),
                                                1: FlexColumnWidth(2),
                                                2: FlexColumnWidth(1.5),
                                                3: FlexColumnWidth(2.5),
                                                4: FlexColumnWidth(2.5),
                                              },
                                              children: [
                                                TableRow(
                                                  decoration: const BoxDecoration(
                                                    color: Color(0xFFF8FAFC),
                                                    borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                                                  ),
                                                  children: const [
                                                    Padding(padding: EdgeInsets.all(8), child: Text('Student', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                                    Padding(padding: EdgeInsets.all(8), child: Text('Adm No', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                                    Padding(padding: EdgeInsets.all(8), child: Text('Held', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                                    Padding(padding: EdgeInsets.all(8), child: Text('Closing Att %', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                                    Padding(padding: EdgeInsets.all(8), child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                                  ],
                                                ),
                                                ...students.map((s) {
                                                  final isBelow = s['below_minimum'] == true;
                                                  final pct = (s['attendance_percentage'] as num?)?.toDouble() ?? 100.0;

                                                  return TableRow(
                                                    decoration: BoxDecoration(
                                                      color: isBelow ? const Color(0xFFFFFBEB) : Colors.transparent,
                                                      border: const Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                                                    ),
                                                    children: [
                                                      Padding(
                                                        padding: const EdgeInsets.all(8),
                                                        child: Text(s['name'] ?? '', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                                      ),
                                                      Padding(
                                                        padding: const EdgeInsets.all(8),
                                                        child: Text(s['admission_number'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                                      ),
                                                      Padding(
                                                        padding: const EdgeInsets.all(8),
                                                        child: Text('${s['sessions_held'] ?? 0}', style: const TextStyle(fontSize: 12)),
                                                      ),
                                                      Padding(
                                                        padding: const EdgeInsets.all(8),
                                                        child: Text(
                                                          '${pct.toStringAsFixed(1)}%',
                                                          style: TextStyle(
                                                            fontSize: 12.5,
                                                            fontWeight: FontWeight.bold,
                                                            color: isBelow ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                                                          ),
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding: const EdgeInsets.all(8),
                                                        child: Align(
                                                          alignment: Alignment.centerLeft,
                                                          child: isBelow
                                                              ? Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                                  decoration: BoxDecoration(
                                                                    color: const Color(0xFFFEF3C7),
                                                                    borderRadius: BorderRadius.circular(4),
                                                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                                                  ),
                                                                  child: const Text(
                                                                    'Below 75%',
                                                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                                                                  ),
                                                                )
                                                              : Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                                  decoration: BoxDecoration(
                                                                    color: const Color(0xFFDCFCE7),
                                                                    borderRadius: BorderRadius.circular(4),
                                                                  ),
                                                                  child: const Text(
                                                                    'Eligible',
                                                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                                                  ),
                                                                ),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                }),
                                              ],
                                            ),
                                    ),
                                  ],
                                ),
                              ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Actions Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isPromoting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                  ),
                  const SizedBox(width: 12),
                  if (!isFinal && !_isLoading && _errorMessage == null)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isPromoting ? null : _executePromotion,
                      icon: _isPromoting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(LucideIcons.arrowUpRight, size: 16),
                      label: Text(_isPromoting ? 'Promoting...' : 'Promote to Semester $nextSem'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinalSemesterView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.award, color: Colors.purple, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Final Semester Reached',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong),
            ),
            const SizedBox(height: 8),
            Text(
              'Batch "${widget.batch.batchName}" is in its final semester. It cannot be promoted further. Instead, please use "Mark batch completed" to graduate this cohort.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[700], foregroundColor: Colors.white),
              onPressed: () {
                Navigator.of(context).pop();
                BatchCompletionDialog.show(
                  context,
                  batch: widget.batch,
                  onCompleted: widget.onPromoted,
                );
              },
              icon: const Icon(LucideIcons.checkCheck, size: 16),
              label: const Text('Mark Batch Completed'),
            ),
          ],
        ),
      ),
    );
  }
}
