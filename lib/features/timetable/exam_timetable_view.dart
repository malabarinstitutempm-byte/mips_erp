// lib/features/timetable/exam_timetable_view.dart
// Admin Exam Timetable Schedule Manager with Add, Edit, Delete and Batch Filtering

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/exam_timetable_entry.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/section_card.dart';
import '../reports/reports_provider.dart';
import 'exam_timetable_provider.dart';

class ExamTimetableScheduleView extends ConsumerStatefulWidget {
  const ExamTimetableScheduleView({super.key});

  @override
  ConsumerState<ExamTimetableScheduleView> createState() => _ExamTimetableScheduleViewState();
}

class _ExamTimetableScheduleViewState extends ConsumerState<ExamTimetableScheduleView> {
  int? _selectedBatchId;

  @override
  Widget build(BuildContext context) {
    final batchesAsync = ref.watch(allBatchesProvider);
    final examEntriesAsync = ref.watch(examTimetableProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Controls Bar
        SectionCard(
          title: 'Examination Timetable Configuration',
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int?>(
                  value: _selectedBatchId,
                  decoration: const InputDecoration(
                    labelText: 'Filter by Course Batch',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All Institutional Batches'),
                    ),
                    if (batchesAsync.valueOrNull != null)
                      ...batchesAsync.valueOrNull!.map((b) {
                        return DropdownMenuItem<int?>(
                          value: b['id'] as int,
                          child: Text(b['name'] as String),
                        );
                      }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedBatchId = val);
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              FilledButton.icon(
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add Exam Paper'),
                onPressed: () => _openAddEditDialog(context, null),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // List of Exam Papers
        examEntriesAsync.when(
          data: (entries) {
            final filtered = _selectedBatchId == null
                ? entries
                : entries.where((e) => e.batchId == _selectedBatchId).toList();

            if (filtered.isEmpty) {
              return SectionCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.calendarX, size: 48, color: AppColors.textMuted),
                        const SizedBox(height: 12),
                        const Text(
                          'No Examination Papers Scheduled',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Click "Add Exam Paper" above to schedule theory and practical examination timetables.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          icon: const Icon(LucideIcons.plus, size: 16),
                          label: const Text('Add Exam Paper Now'),
                          onPressed: () => _openAddEditDialog(context, null),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return SectionCard(
              title: 'Scheduled Examination Papers (${filtered.length})',
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final paper = filtered[index];
                  final parsedDate = DateTime.tryParse(paper.examDate);
                  final formattedDate = parsedDate != null
                      ? DateFormat('EEEE, MMM d, yyyy').format(parsedDate)
                      : paper.examDate;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date Badge
                        Container(
                          width: 80,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                          decoration: BoxDecoration(
                            color: AppColors.brandTint,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.brand.withOpacity(0.3)),
                          ),
                          child: Column(
                            children: [
                              Text(
                                parsedDate != null ? DateFormat('MMM').format(parsedDate).toUpperCase() : 'EXAM',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.brandDark),
                              ),
                              Text(
                                parsedDate != null ? DateFormat('d').format(parsedDate) : '--',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.brandDark),
                              ),
                              Text(
                                parsedDate != null ? DateFormat('EEE').format(parsedDate) : '',
                                style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),

                        // Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    paper.subjectName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.blueGrey.shade200),
                                    ),
                                    child: Text(
                                      paper.subjectCode,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${paper.examName} • ${paper.batchName}',
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(LucideIcons.clock, size: 14, color: AppColors.brand),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${paper.startTime} - ${paper.endTime}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 16),
                                  const Icon(LucideIcons.mapPin, size: 14, color: Colors.redAccent),
                                  const SizedBox(width: 4),
                                  Text(
                                    paper.room,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              if (paper.instructions.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  paper.instructions,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Action Buttons
                        IconButton(
                          icon: const Icon(LucideIcons.edit2, size: 16, color: AppColors.brand),
                          tooltip: 'Edit Exam Paper',
                          onPressed: () => _openAddEditDialog(context, paper),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.redAccent),
                          tooltip: 'Delete Exam Paper',
                          onPressed: () => _confirmDeleteDialog(context, paper.id, paper.subjectName),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
          error: (e, _) => Center(child: Text('Error loading exam timetable: $e')),
        ),
      ],
    );
  }

  void _openAddEditDialog(BuildContext context, ExamTimetableEntry? existing) {
    final isEditing = existing != null;
    final batchesAsync = ref.read(allBatchesProvider);
    final batches = batchesAsync.valueOrNull ?? [];

    int selectedBatchId = existing?.batchId ?? (batches.isNotEmpty ? (batches.first['id'] as int) : 1);
    String selectedBatchName = existing?.batchName ?? (batches.isNotEmpty ? (batches.first['name'] as String) : 'DMLT Batch A (2023-2025)');

    final examNameCtrl = TextEditingController(text: existing?.examName ?? 'First Semester University Examination 2026');
    final subjectNameCtrl = TextEditingController(text: existing?.subjectName ?? '');
    final subjectCodeCtrl = TextEditingController(text: existing?.subjectCode ?? '');
    final examDateCtrl = TextEditingController(text: existing?.examDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 7))));
    final startTimeCtrl = TextEditingController(text: existing?.startTime ?? '10:00');
    final endTimeCtrl = TextEditingController(text: existing?.endTime ?? '13:00');
    final roomCtrl = TextEditingController(text: existing?.room ?? 'Main Examination Hall A');
    final instructionsCtrl = TextEditingController(text: existing?.instructions ?? 'Reporting time: 30 minutes before exam start. Hall ticket mandatory.');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(isEditing ? LucideIcons.edit : LucideIcons.calendarPlus, color: AppColors.brand, size: 20),
                const SizedBox(width: 8),
                Text(isEditing ? 'Edit Exam Paper' : 'Schedule Exam Paper'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedBatchId,
                      decoration: const InputDecoration(labelText: 'Course Batch *'),
                      items: batches.isNotEmpty
                          ? batches.map((b) => DropdownMenuItem<int>(value: b['id'] as int, child: Text(b['name'] as String))).toList()
                          : const [DropdownMenuItem<int>(value: 1, child: Text('DMLT Batch A (2023-2025)'))],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedBatchId = val;
                            final found = batches.firstWhere((b) => b['id'] == val, orElse: () => {'name': 'Primary Batch'});
                            selectedBatchName = found['name'] as String;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: examNameCtrl, decoration: const InputDecoration(labelText: 'Exam Title *')),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(flex: 3, child: TextField(controller: subjectNameCtrl, decoration: const InputDecoration(labelText: 'Subject Name *', hintText: 'e.g. Clinical Biochemistry'))),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: TextField(controller: subjectCodeCtrl, decoration: const InputDecoration(labelText: 'Paper Code *', hintText: 'e.g. MLT101'))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: examDateCtrl, decoration: const InputDecoration(labelText: 'Exam Date (YYYY-MM-DD) *', prefixIcon: Icon(LucideIcons.calendar, size: 16)))),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: roomCtrl, decoration: const InputDecoration(labelText: 'Exam Hall / Room *', prefixIcon: Icon(LucideIcons.mapPin, size: 16)))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: startTimeCtrl, decoration: const InputDecoration(labelText: 'Start Time (HH:mm) *', prefixIcon: Icon(LucideIcons.clock, size: 16)))),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: endTimeCtrl, decoration: const InputDecoration(labelText: 'End Time (HH:mm) *', prefixIcon: Icon(LucideIcons.clock, size: 16)))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: instructionsCtrl, decoration: const InputDecoration(labelText: 'Special Candidate Instructions'), maxLines: 2),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final subj = subjectNameCtrl.text.trim();
                  final code = subjectCodeCtrl.text.trim();
                  if (subj.isEmpty || code.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter subject name and code.')));
                    return;
                  }

                  Navigator.pop(ctx);
                  if (isEditing) {
                    await ref.read(examTimetableProvider.notifier).updateEntry(
                          existing.copyWith(
                            batchId: selectedBatchId,
                            batchName: selectedBatchName,
                            examName: examNameCtrl.text.trim(),
                            subjectName: subj,
                            subjectCode: code,
                            examDate: examDateCtrl.text.trim(),
                            startTime: startTimeCtrl.text.trim(),
                            endTime: endTimeCtrl.text.trim(),
                            room: roomCtrl.text.trim(),
                            instructions: instructionsCtrl.text.trim(),
                          ),
                        );
                  } else {
                    await ref.read(examTimetableProvider.notifier).addEntry(
                          batchId: selectedBatchId,
                          batchName: selectedBatchName,
                          examName: examNameCtrl.text.trim(),
                          subjectName: subj,
                          subjectCode: code,
                          examDate: examDateCtrl.text.trim(),
                          startTime: startTimeCtrl.text.trim(),
                          endTime: endTimeCtrl.text.trim(),
                          room: roomCtrl.text.trim(),
                          instructions: instructionsCtrl.text.trim(),
                        );
                  }

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(isEditing ? 'Exam paper updated successfully.' : 'Exam paper scheduled successfully.')),
                    );
                  }
                },
                child: Text(isEditing ? 'Save Changes' : 'Schedule Paper'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteDialog(BuildContext context, int id, String subjectName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Exam Paper'),
        content: Text('Are you sure you want to delete "$subjectName" from the examination timetable?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(examTimetableProvider.notifier).deleteEntry(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exam paper removed.')));
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
