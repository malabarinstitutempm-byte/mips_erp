import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/batch.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/status_badge.dart';
import '../courses/course_provider.dart';

class BatchCompletionDialog extends ConsumerStatefulWidget {
  final Batch batch;
  final VoidCallback onCompleted;

  const BatchCompletionDialog({
    super.key,
    required this.batch,
    required this.onCompleted,
  });

  static Future<void> show(BuildContext context, {required Batch batch, required VoidCallback onCompleted}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BatchCompletionDialog(batch: batch, onCompleted: onCompleted),
    );
  }

  @override
  ConsumerState<BatchCompletionDialog> createState() => _BatchCompletionDialogState();
}

class _BatchCompletionDialogState extends ConsumerState<BatchCompletionDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _students = [];
  final Set<int> _selectedStudentIds = {};

  DateTime _completionDate = DateTime.now();
  DateTime _accessEndDate = DateTime.now().add(const Duration(days: 90));
  bool _closeLoginsNow = false;
  bool _isSubmitting = false;

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
      final preview = await repo.previewBatchCompletion(widget.batch.id!);
      if (mounted) {
        setState(() {
          _students = preview;
          _selectedStudentIds.clear();
          for (final s in preview) {
            final sid = (s['student_id'] as num?)?.toInt();
            if (sid != null) {
              _selectedStudentIds.add(sid);
            }
          }
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

  int get _completedCount => _selectedStudentIds.length;
  int get _excludedCount => _students.length - _selectedStudentIds.length;

  Future<void> _pickCompletionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _completionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _completionDate = picked;
        _accessEndDate = picked.add(const Duration(days: 90));
      });
    }
  }

  Future<void> _pickAccessEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _accessEndDate,
      firstDate: _completionDate,
      lastDate: _completionDate.add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) {
      setState(() {
        _accessEndDate = picked;
      });
    }
  }

  Future<void> _confirmAndComplete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(LucideIcons.alertTriangle, color: Colors.amber, size: 22),
            const SizedBox(width: 10),
            const Text('Confirm Batch Completion'),
          ],
        ),
        content: Text(
          'Are you sure you want to complete batch "${widget.batch.batchName}"?\n\n'
          '• $_completedCount student(s) will be marked as COMPLETED.\n'
          '• $_excludedCount student(s) will be EXCLUDED and kept active.\n'
          '• Attendance marking will be locked for this batch.\n'
          '${_closeLoginsNow ? '• Logins will be CLOSED immediately for completed students.' : '• Read-only portal access will remain open until ${DateFormat('dd MMM yyyy').format(_accessEndDate)}.'}',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Completion'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);

    try {
      final excludedIds = _students
          .map((s) => (s['student_id'] as num?)?.toInt())
          .whereType<int>()
          .where((id) => !_selectedStudentIds.contains(id))
          .toList();

      final repo = ref.read(batchRepositoryProvider);
      final res = await repo.completeBatch(
        widget.batch.id!,
        completedOn: _completionDate,
        excludedStudentIds: excludedIds,
        accessUntilOverride: _closeLoginsNow ? null : _accessEndDate,
        closeLoginsNow: _closeLoginsNow,
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        Navigator.pop(context); // Close preview dialog

        // Show Result Summary Dialog
        _showResultSummary(
          completedCount: (res['completed_students_count'] as num?)?.toInt() ?? _completedCount,
          excludedCount: (res['excluded_students_count'] as num?)?.toInt() ?? _excludedCount,
          completedOn: _completionDate,
        );

        widget.onCompleted();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to complete batch: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showResultSummary({
    required int completedCount,
    required int excludedCount,
    required DateTime completedOn,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(LucideIcons.checkCircle2, color: Colors.green, size: 24),
            const SizedBox(width: 10),
            const Text('Batch Completed Successfully'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Batch "${widget.batch.batchName}" is now marked as COMPLETED.',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Marked Completed: $completedCount students', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('• Excluded (Still Active): $excludedCount students', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('• Completion Date: ${DateFormat('dd MMMM yyyy').format(completedOn)}'),
                  const SizedBox(height: 4),
                  Text('• Portal Access Window: ${_closeLoginsNow ? 'Closed Immediately' : 'Until ${DateFormat('dd MMM yyyy').format(_accessEndDate)}'}'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;
    final isMobile = width < 600;
    final dialogWidth = width > 900 ? 850.0 : width * 0.95;
    final dialogMaxHeight = height > 800 ? 720.0 : height * 0.92;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16, vertical: isMobile ? 12 : 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth, maxHeight: dialogMaxHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppRadius.card), topRight: Radius.circular(AppRadius.card)),
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.blue.withOpacity(0.1),
                    child: const Icon(LucideIcons.graduationCap, color: Colors.blue, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mark Batch as Completed: ${widget.batch.batchName}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Review active students, verify pending fees and attendance, and set completion date.',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Controls Banner (Date pickers & options)
            Container(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: isMobile ? 10 : 14),
              color: AppColors.bg,
              child: Wrap(
                spacing: 20,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  // Completion Date Picker
                  InkWell(
                    onTap: _pickCompletionDate,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.calendar, size: 16, color: AppColors.brand),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              isMobile
                                  ? 'Done: ${DateFormat('dd MMM yy').format(_completionDate)}'
                                  : 'Completion Date: ${DateFormat('dd MMM yyyy').format(_completionDate)}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(LucideIcons.chevronDown, size: 14, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  ),

                  // Access End Date Picker
                  if (!_closeLoginsNow)
                    InkWell(
                      onTap: _pickAccessEndDate,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.clock, size: 16, color: Colors.purple),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                isMobile
                                    ? 'Access: ${DateFormat('dd MMM yy').format(_accessEndDate)}'
                                    : 'Portal Access Until: ${DateFormat('dd MMM yyyy').format(_accessEndDate)}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(LucideIcons.chevronDown, size: 14, color: AppColors.textMuted),
                          ],
                        ),
                      ),
                    ),

                  // Immediate Close Checkbox
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _closeLoginsNow,
                        onChanged: (v) => setState(() => _closeLoginsNow = v ?? false),
                      ),
                      const Flexible(
                        child: Text(
                          'Close logins immediately',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Content Table
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(child: Text('Error: $_errorMessage', style: const TextStyle(color: Colors.red)))
                      : _students.isEmpty
                          ? const Center(
                              child: Text(
                                'No active students found in this batch.',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 15),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final isNarrow = constraints.maxWidth < 650;
                                final tableContent = SizedBox(
                                  width: isNarrow ? 700 : constraints.maxWidth,
                                  child: Column(
                                    children: [
                                // Table Header Select All
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  color: AppColors.surface,
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: _selectedStudentIds.length == _students.length,
                                        tristate: _selectedStudentIds.isNotEmpty && _selectedStudentIds.length < _students.length,
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              for (final s in _students) {
                                                final sid = (s['student_id'] as num?)?.toInt();
                                                if (sid != null) _selectedStudentIds.add(sid);
                                              }
                                            } else {
                                              _selectedStudentIds.clear();
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      const Expanded(flex: 3, child: Text('STUDENT NAME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textMuted))),
                                      const Expanded(flex: 2, child: Text('ADM / REG NO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textMuted))),
                                      const Expanded(flex: 2, child: Text('ATTENDANCE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textMuted))),
                                      const Expanded(flex: 2, child: Text('PENDING FEE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textMuted))),
                                      const Expanded(flex: 2, child: Text('OTHER COURSES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textMuted))),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),

                                // Student Rows
                                Expanded(
                                  child: ListView.separated(
                                    itemCount: _students.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (ctx, index) {
                                      final s = _students[index];
                                      final sid = (s['student_id'] as num?)?.toInt() ?? 0;
                                      final isSelected = _selectedStudentIds.contains(sid);
                                      final hasPending = s['has_pending_fee'] == true;
                                      final pendingAmt = (s['pending_fee_balance'] as num?)?.toDouble() ?? 0.0;
                                      final attPct = (s['attendance_percentage'] as num?)?.toDouble() ?? 0.0;
                                      final otherCourses = (s['other_active_enrollments_count'] as num?)?.toInt() ?? 0;

                                      return Container(
                                        color: isSelected ? Colors.transparent : Colors.amber.withOpacity(0.04),
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                        child: Row(
                                          children: [
                                            Checkbox(
                                              value: isSelected,
                                              onChanged: (val) {
                                                setState(() {
                                                  if (val == true) {
                                                    _selectedStudentIds.add(sid);
                                                  } else {
                                                    _selectedStudentIds.remove(sid);
                                                  }
                                                });
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            // Name
                                            Expanded(
                                              flex: 3,
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    s['name']?.toString() ?? 'N/A',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w600,
                                                      color: isSelected ? AppColors.textStrong : AppColors.textMuted,
                                                    ),
                                                  ),
                                                  if (!isSelected)
                                                    const Text(
                                                      'Will be EXCLUDED',
                                                      style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            // Adm / Reg
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                '${s['admission_number'] ?? 'N/A'}',
                                                style: const TextStyle(fontSize: 12.5),
                                              ),
                                            ),
                                            // Attendance
                                            Expanded(
                                              flex: 2,
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: attPct >= 75 ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      '${attPct.toStringAsFixed(1)}%',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: attPct >= 75 ? Colors.green[800] : Colors.red[800],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Pending Fee
                                            Expanded(
                                              flex: 2,
                                              child: Row(
                                                children: [
                                                  if (hasPending) ...[
                                                    StatusBadge(
                                                      text: '₹${pendingAmt.toStringAsFixed(0)} DUE',
                                                      status: BadgeStatus.danger,
                                                    ),
                                                  ] else ...[
                                                    const Text('Cleared', style: TextStyle(color: Colors.green, fontSize: 12.5, fontWeight: FontWeight.w500)),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            // Other active courses
                                            Expanded(
                                              flex: 2,
                                              child: otherCourses > 0
                                                  ? Text('$otherCourses active skill course', style: const TextStyle(fontSize: 11.5, color: Colors.purple))
                                                  : const Text('None', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );

                                if (isNarrow) {
                                  return Scrollbar(
                                    thumbVisibility: true,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: tableContent,
                                    ),
                                  );
                                }
                                return tableContent;
                              },
                            ),
            ),

            const Divider(height: 1),

            // Footer / Action Bar with Summary Line
            Container(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: isMobile ? 12 : 16),
              color: AppColors.surface,
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 13, color: AppColors.textStrong),
                            children: [
                              const TextSpan(text: 'Summary: '),
                              TextSpan(
                                text: '$_completedCount students',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                              const TextSpan(text: ' will be marked completed, '),
                              TextSpan(
                                text: '$_excludedCount excluded',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _excludedCount > 0 ? Colors.orange : AppColors.textMuted,
                                ),
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            TextButton(
                              onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brand,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              onPressed: (_isSubmitting || _isLoading || _students.isEmpty) ? null : _confirmAndComplete,
                              icon: _isSubmitting
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(LucideIcons.checkCheck, size: 16),
                              label: Text(_isSubmitting ? 'Completing...' : 'Complete Batch ($_completedCount)'),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        // Live Summary Line
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 13.5, color: AppColors.textStrong),
                              children: [
                                const TextSpan(text: 'Summary: '),
                                TextSpan(
                                  text: '$_completedCount students',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                                ),
                                const TextSpan(text: ' will be marked completed, '),
                                TextSpan(
                                  text: '$_excludedCount excluded',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _excludedCount > 0 ? Colors.orange : AppColors.textMuted,
                                  ),
                                ),
                                const TextSpan(text: '.'),
                              ],
                            ),
                          ),
                        ),

                        TextButton(
                          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brand,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          onPressed: (_isSubmitting || _isLoading || _students.isEmpty) ? null : _confirmAndComplete,
                          icon: _isSubmitting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(LucideIcons.checkCheck, size: 17),
                          label: Text(_isSubmitting ? 'Completing Batch...' : 'Complete Batch ($_completedCount)'),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
