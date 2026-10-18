import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/exam.dart';
import '../../core/models/subject.dart';
import '../../core/models/batch.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../courses/course_provider.dart';
import 'exam_provider.dart';

class AddExamDialog extends ConsumerStatefulWidget {
  const AddExamDialog({super.key});

  @override
  ConsumerState<AddExamDialog> createState() => _AddExamDialogState();
}

class _SubjectEntry {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController codeCtrl = TextEditingController();
  final TextEditingController maxCtrl = TextEditingController(text: '100');
  final TextEditingController passCtrl = TextEditingController(text: '40');
}

class _AddExamDialogState extends ConsumerState<AddExamDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  int? _selectedCourseId;
  int? _selectedBatchId;
  List<Batch> _batches = [];

  final List<_SubjectEntry> _subjects = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _addSubject(); // Add at least one
  }

  void _addSubject() {
    setState(() {
      _subjects.add(_SubjectEntry());
    });
  }

  void _removeSubject(int index) {
    if (_subjects.length > 1) {
      setState(() {
        _subjects.removeAt(index);
      });
    }
  }

  Widget _buildPresetChip(_SubjectEntry sub, String max, String pass) {
    final isSelected = sub.maxCtrl.text.trim() == max && sub.passCtrl.text.trim() == pass;
    return InkWell(
      onTap: () {
        setState(() {
          sub.maxCtrl.text = max;
          sub.passCtrl.text = pass;
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandDark : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? AppColors.brandDark : const Color(0xFFCBD5E1)),
        ),
        child: Text(
          '$max / $pass',
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textStrong,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesProvider);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radius14)),
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Create New Exam', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xl),
              
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Exam Name (e.g. 2026 Final Examination)'),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: coursesAsync.when(
                      data: (courses) => DropdownButtonFormField<int>(
                        decoration: const InputDecoration(labelText: 'Course'),
                        value: _selectedCourseId,
                        isExpanded: true,
                        items: courses.map((c) => DropdownMenuItem(
                          value: c.id, 
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) async {
                          setState(() {
                            _selectedCourseId = v;
                            _selectedBatchId = null;
                            _batches = [];
                          });
                          if (v != null) {
                            try {
                              final list = await ref.read(courseRepositoryProvider).getBatchesForCourse(v);
                              final courseSubjects = await ref.read(courseRepositoryProvider).getSubjectsForCourse(v);
                              setState(() {
                                _batches = list;
                                if (list.isNotEmpty) {
                                  _selectedBatchId = list.first.id;
                                }
                                if (courseSubjects.isNotEmpty) {
                                  _subjects.clear();
                                  for (final cs in courseSubjects) {
                                    final entry = _SubjectEntry();
                                    entry.nameCtrl.text = cs.subjectName;
                                    entry.codeCtrl.text = cs.subjectCode ?? '';
                                    entry.maxCtrl.text = cs.maxMarks.toStringAsFixed(0);
                                    entry.passCtrl.text = cs.passMarks.toStringAsFixed(0);
                                    _subjects.add(entry);
                                  }
                                }
                              });
                            } catch (_) {}
                          }
                        },
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                      loading: () => const CircularProgressIndicator(),
                      error: (_,__) => const Text('Error loading courses'),
                    ),
                  ),
                  if (_batches.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(labelText: 'Batch'),
                        value: _selectedBatchId,
                        isExpanded: true,
                        items: _batches.map((b) => DropdownMenuItem(
                          value: b.id, 
                          child: Text(b.batchName, overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) => setState(() => _selectedBatchId = v),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Subjects', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text(
                        'Auto-loaded from course curriculum. You can edit total and pass marks here or during mark entry.',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _addSubject,
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Add Subject'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              
              Expanded(
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadius.card)),
                  child: ListView.separated(
                    itemCount: _subjects.length,
                    separatorBuilder: (_,__) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final sub = _subjects[i];
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: sub.nameCtrl,
                                    decoration: const InputDecoration(labelText: 'Subject Name', isDense: true),
                                    validator: (v) => v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  flex: 1,
                                  child: TextFormField(
                                    controller: sub.codeCtrl,
                                    decoration: const InputDecoration(labelText: 'Code', isDense: true),
                                    validator: (v) => v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  flex: 1,
                                  child: TextFormField(
                                    controller: sub.maxCtrl,
                                    decoration: const InputDecoration(labelText: 'Max Marks', isDense: true),
                                    keyboardType: TextInputType.number,
                                    validator: (v) {
                                      final num = int.tryParse(v ?? '');
                                      if (num == null || num <= 0) return 'Invalid';
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  flex: 1,
                                  child: TextFormField(
                                    controller: sub.passCtrl,
                                    decoration: const InputDecoration(labelText: 'Pass Marks', isDense: true),
                                    keyboardType: TextInputType.number,
                                    validator: (v) {
                                      final pass = int.tryParse(v ?? '');
                                      final max = int.tryParse(sub.maxCtrl.text);
                                      if (pass == null || pass < 0) return 'Invalid';
                                      if (max != null && pass > max) return '> Max';
                                      return null;
                                    },
                                  ),
                                ),
                                if (_subjects.length > 1)
                                  IconButton(
                                    icon: Icon(LucideIcons.trash, color: AppColors.danger.base),
                                    onPressed: () => _removeSubject(i),
                                  ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6, left: 2),
                              child: Row(
                                children: [
                                  const Text('Presets: ', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                  _buildPresetChip(sub, '100', '40'),
                                  const SizedBox(width: 4),
                                  _buildPresetChip(sub, '100', '50'),
                                  const SizedBox(width: 4),
                                  _buildPresetChip(sub, '50', '20'),
                                  const SizedBox(width: 4),
                                  _buildPresetChip(sub, '75', '30'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: AppSpacing.md),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create Exam'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Check duplicate codes
    final codes = _subjects.map((s) => s.codeCtrl.text.trim()).toList();
    if (codes.toSet().length != codes.length) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Duplicate subject codes are not allowed.')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(examRepositoryProvider);
      
      final exam = Exam(
        name: _nameCtrl.text.trim(),
        academicYearId: 1,
        courseId: _selectedCourseId!,
        batchId: _selectedBatchId ?? 1, 
        examDate: DateTime.now().toIso8601String(),
        status: 'Draft',
      );
      
      final examId = await repo.addExam(exam);
      
      for (int i = 0; i < _subjects.length; i++) {
        final sub = _subjects[i];
        final subject = Subject(
          examId: examId,
          name: sub.nameCtrl.text.trim(),
          code: sub.codeCtrl.text.trim(),
          maxMarks: double.parse(sub.maxCtrl.text),
          passMarks: double.parse(sub.passCtrl.text),
          theoryMarks: double.parse(sub.maxCtrl.text), // simplifed
          practicalMarks: 0.0,
          displayOrder: i,
        );
        await repo.addSubject(subject);
      }
      
      if (mounted) {
        ref.invalidate(examDashboardProvider);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exam created successfully!')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create exam: $e')));
      }
    }
  }
}
