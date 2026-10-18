import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/batch.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../courses/course_provider.dart';

class SemesterDatesDialog extends ConsumerStatefulWidget {
  final Batch batch;
  final VoidCallback onUpdated;

  const SemesterDatesDialog({
    super.key,
    required this.batch,
    required this.onUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required Batch batch,
    required VoidCallback onUpdated,
  }) {
    return showDialog(
      context: context,
      builder: (_) => SemesterDatesDialog(batch: batch, onUpdated: onUpdated),
    );
  }

  @override
  ConsumerState<SemesterDatesDialog> createState() => _SemesterDatesDialogState();
}

class _SemesterDatesDialogState extends ConsumerState<SemesterDatesDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _semesters = [];

  @override
  void initState() {
    super.initState();
    _loadSemesters();
  }

  Future<void> _loadSemesters() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(batchRepositoryProvider);
      final list = await repo.getBatchSemesters(widget.batch.id!);
      if (mounted) {
        setState(() {
          _semesters = list;
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

  Future<void> _editSemesterDates(Map<String, dynamic> sem) async {
    final semNo = (sem['semester_no'] as num).toInt();
    final initialStart = DateTime.tryParse(sem['start_date']?.toString() ?? '') ?? DateTime.now();
    final initialEnd = sem['end_date'] != null ? DateTime.tryParse(sem['end_date'].toString()) : null;

    DateTime startDate = initialStart;
    DateTime? endDate = initialEnd;
    final reasonCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final dateFormat = DateFormat('yyyy-MM-dd');

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          title: Row(
            children: [
              const Icon(LucideIcons.calendar, color: Color(0xFF2563EB), size: 20),
              const SizedBox(width: 8),
              Text('Edit Semester $semNo Dates', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Start Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: startDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setDialogState(() => startDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(dateFormat.format(startDate), style: const TextStyle(fontSize: 13)),
                          const Icon(LucideIcons.calendar, size: 16, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('End Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      if (endDate != null)
                        InkWell(
                          onTap: () => setDialogState(() => endDate = null),
                          child: const Text('Clear (Ongoing)', style: TextStyle(fontSize: 11.5, color: Colors.blue)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: endDate ?? startDate.add(const Duration(days: 150)),
                        firstDate: startDate,
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setDialogState(() => endDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(endDate != null ? dateFormat.format(endDate!) : 'Ongoing (None)', style: const TextStyle(fontSize: 13)),
                          const Icon(LucideIcons.calendar, size: 16, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Reason / Explanation (Required if sessions exist outside range)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Academic calendar revised by institutional board',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(10),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save Dates'),
            ),
          ],
        ),
      ),
    );

    if (updated == true && mounted) {
      try {
        final repo = ref.read(batchRepositoryProvider);
        await repo.updateBatchSemesterDates(
          widget.batch.id!,
          semNo,
          startDate,
          endDate,
          reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF16A34A),
            content: Text('Semester $semNo dates successfully updated.'),
          ),
        );
        _loadSemesters();
        widget.onUpdated();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text('Failed to update dates: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 600),
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
                        child: const Icon(LucideIcons.calendarRange, color: Color(0xFF2563EB), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Semester Dates Manager', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                          Text('${widget.batch.batchName} • Academic Date Boundaries', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // Semesters List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                        ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
                        : _semesters.isEmpty
                            ? const Center(child: Text('No semester records configured yet.', style: TextStyle(color: AppColors.textMuted)))
                            : ListView.separated(
                                itemCount: _semesters.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (ctx, idx) {
                                  final s = _semesters[idx];
                                  final semNo = (s['semester_no'] as num).toInt();
                                  final yr = (semNo + 1) ~/ 2;
                                  final status = (s['status'] ?? 'active').toString();
                                  final isActive = status == 'active';
                                  final start = s['start_date']?.toString() ?? 'N/A';
                                  final end = s['end_date']?.toString() ?? 'Ongoing';

                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: isActive ? const Color(0xFF93C5FD) : AppColors.border),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isActive ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: isActive ? const Color(0xFFBFDBFE) : const Color(0xFFCBD5E1)),
                                          ),
                                          child: Column(
                                            children: [
                                              Text('Sem $semNo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isActive ? const Color(0xFF1D4ED8) : const Color(0xFF475569))),
                                              Text('Year $yr', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      status.toUpperCase(),
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: isActive ? const Color(0xFF15803D) : const Color(0xFF64748B),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text('Date Range: $start  →  $end', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textStrong)),
                                            ],
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: const Color(0xFF2563EB),
                                            side: const BorderSide(color: Color(0xFFBFDBFE)),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                          onPressed: () => _editSemesterDates(s),
                                          icon: const Icon(LucideIcons.edit2, size: 13),
                                          label: const Text('Edit Dates', style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
