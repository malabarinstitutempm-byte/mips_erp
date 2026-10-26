import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/exam.dart';
import '../../core/models/subject.dart';
import '../../core/models/batch.dart';
import '../../core/models/course.dart';
import '../../core/models/course_subject.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
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
  final _overrideReasonCtrl = TextEditingController();

  int? _selectedCourseId;
  int? _selectedBatchId;
  int? _selectedPeriodNo;

  List<Batch> _batches = [];
  List<CourseSubject> _courseSubjects = [];
  bool _isLoadingBatches = false;

  final List<_SubjectEntry> _subjects = [];
  bool _isSaving = false;

  void _addSubject({String name = '', String code = '', double max = 100, double pass = 40}) {
    setState(() {
      final entry = _SubjectEntry();
      entry.nameCtrl.text = name;
      entry.codeCtrl.text = code;
      entry.maxCtrl.text = max.toStringAsFixed(0);
      entry.passCtrl.text = pass.toStringAsFixed(0);
      _subjects.add(entry);
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
    final courses = coursesAsync.valueOrNull ?? [];

    final Course? selectedCourse = _selectedCourseId != null
        ? courses.where((c) => c.id == _selectedCourseId).firstOrNull
        : null;

    final Batch? selectedBatch = _selectedBatchId != null
        ? _batches.where((b) => b.id == _selectedBatchId).firstOrNull
        : null;

    final int batchCurrentPeriod = selectedBatch != null
        ? (selectedCourse?.isYearWise == true
            ? selectedBatch.currentYear
            : (selectedCourse?.isSingle == true ? 1 : selectedBatch.currentSemester))
        : 1;

    final bool isOverrideRequired = _selectedPeriodNo != null &&
        selectedBatch != null &&
        _selectedPeriodNo! > batchCurrentPeriod;

    final String periodLabel = selectedCourse?.periodTypeLabel ?? 'Semester';
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isMobile = screenWidth < 768;

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 14)
          : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radius14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isMobile ? double.infinity : 880,
          maxHeight: isMobile ? (screenHeight * 0.94) : 760,
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Create New Examination', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // Exam Name
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Exam Name *',
                    hintText: 'e.g. Annual Theory Examination 2026',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Exam name is required' : null,
                ),
                const SizedBox(height: AppSpacing.md),

                // 3-Step Selection: Course -> Batch -> Semester/Year (NEVER auto-selected)
                Builder(
                  builder: (context) {
                    final courseSelector = DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: '1. Course *',
                        hintText: 'Select course...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      value: _selectedCourseId,
                      isExpanded: true,
                      items: courses.map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(
                          '${c.name} (${c.structure.toUpperCase()})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      )).toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() {
                          _selectedCourseId = v;
                          _selectedBatchId = null; // EXPLICIT: NEVER AUTO-SELECTED
                          _selectedPeriodNo = null; // EXPLICIT: NEVER AUTO-SELECTED
                          _batches = [];
                          _courseSubjects = [];
                          _subjects.clear();
                          _overrideReasonCtrl.clear();
                          _isLoadingBatches = true;
                        });

                        try {
                          final list = await ref.read(courseRepositoryProvider).getBatchesForCourse(v);
                          final csList = await ref.read(courseRepositoryProvider).getSubjectsForCourse(v);
                          if (mounted) {
                            setState(() {
                              _batches = list.where((b) => b.status != 'completed').toList();
                              _courseSubjects = csList;
                              _isLoadingBatches = false;
                            });
                          }
                        } catch (_) {
                          if (mounted) setState(() => _isLoadingBatches = false);
                        }
                      },
                      validator: (v) => v == null ? 'Select a course' : null,
                    );

                    final batchSelector = DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: '2. Batch *',
                        hintText: _isLoadingBatches
                            ? 'Loading batches...'
                            : (_selectedCourseId == null ? 'Select course first' : 'Select batch...'),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      value: _selectedBatchId,
                      isExpanded: true,
                      items: _batches.map((b) => DropdownMenuItem(
                        value: b.id,
                        child: Text(
                          '${b.batchName} (${b.currentPeriodLabel(selectedCourse)})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      )).toList(),
                      onChanged: _selectedCourseId == null
                          ? null
                          : (v) {
                              setState(() {
                                _selectedBatchId = v;
                                _selectedPeriodNo = null; // EXPLICIT: NEVER AUTO-SELECTED
                                _subjects.clear();
                                _overrideReasonCtrl.clear();
                              });
                            },
                      validator: (v) => v == null ? 'Select a batch' : null,
                    );

                    final periodSelector = DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: '3. $periodLabel *',
                        hintText: _selectedBatchId == null
                            ? 'Select batch first'
                            : 'Select $periodLabel...',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        helperText: selectedBatch != null
                            ? 'Batch current: ${selectedBatch.currentPeriodLabel(selectedCourse)}'
                            : null,
                        helperStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                      value: _selectedPeriodNo,
                      isExpanded: true,
                      items: selectedCourse == null
                          ? []
                          : List.generate(
                              selectedCourse.isYearWise
                                  ? selectedCourse.durationYears
                                  : (selectedCourse.isSingle ? 1 : selectedCourse.periodsCount),
                              (i) => i + 1,
                            ).map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(
                                selectedCourse.isYearWise
                                    ? 'Year $p'
                                    : (selectedCourse.isSingle ? 'Single Period (1)' : 'Semester $p'),
                                style: const TextStyle(fontSize: 13),
                              ),
                            )).toList(),
                      onChanged: _selectedBatchId == null
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() {
                                _selectedPeriodNo = v;
                                _subjects.clear();

                                // Load subjects belonging to this period
                                List<CourseSubject> periodSubjects = [];
                                if (selectedCourse?.isYearWise == true) {
                                  // For YEAR-wise course, subjects belong to that academic year
                                  periodSubjects = _courseSubjects.where((cs) => cs.periodNo == v).toList();
                                  // If no subjects tagged with period_no, also fall back to unassigned
                                  if (periodSubjects.isEmpty) {
                                    periodSubjects = _courseSubjects.where((cs) => cs.periodNo == null).toList();
                                  }
                                } else if (selectedCourse?.isSingle == true) {
                                  periodSubjects = _courseSubjects;
                                } else {
                                  // Semester-wise
                                  periodSubjects = _courseSubjects.where((cs) => cs.periodNo == v).toList();
                                  if (periodSubjects.isEmpty) {
                                    periodSubjects = _courseSubjects.where((cs) => cs.periodNo == null).toList();
                                  }
                                }

                                for (final cs in periodSubjects) {
                                  _addSubject(
                                    name: cs.subjectName,
                                    code: cs.subjectCode ?? '',
                                    max: cs.maxMarks,
                                    pass: cs.passMarks,
                                  );
                                }

                                if (periodSubjects.isEmpty) {
                                  _addSubject();
                                }
                              });
                            },
                      validator: (v) => v == null ? 'Select $periodLabel' : null,
                    );

                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          courseSelector,
                          const SizedBox(height: AppSpacing.sm),
                          batchSelector,
                          const SizedBox(height: AppSpacing.sm),
                          periodSelector,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: courseSelector),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(flex: 3, child: batchSelector),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(flex: 3, child: periodSelector),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.sm),

                // Audited Override Banner if selected period > batch current period
                if (isOverrideRequired) ...[
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.alertTriangle, color: Color(0xFFD97706), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Audited Override Required: Selected $periodLabel $_selectedPeriodNo is ahead of batch current ${selectedBatch.currentPeriodLabel(selectedCourse)}.',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _overrideReasonCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Institutional Override Reason *',
                            hintText: 'e.g. Approved board early examination / Special backlog clearance schedule',
                            isDense: true,
                            border: OutlineInputBorder(),
                            fillColor: Colors.white,
                            filled: true,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Override reason is required for future periods' : null,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.md),

                // Subjects Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Examination Subjects', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            if (selectedCourse != null && _selectedPeriodNo != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Text(
                                  selectedCourse.isYearWise
                                      ? 'Year $_selectedPeriodNo (All Year Subjects)'
                                      : (selectedCourse.isSingle ? 'Single Course' : 'Semester $_selectedPeriodNo'),
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E40AF)),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          selectedCourse?.isYearWise == true
                              ? 'For year-wise courses, all active subjects of the year appear in one sheet.'
                              : 'Auto-populated from curriculum for the selected period. Total & pass marks can be customized.',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.purple,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () => _addSubject(),
                      icon: const Icon(LucideIcons.plusCircle, size: 16),
                      label: const Text('Add Subject'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // Subjects Table
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: _subjects.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                _selectedPeriodNo == null
                                    ? 'Select Course, Batch, and $periodLabel to load curriculum subjects.'
                                    : 'No subjects found for this period. Click "+ Add Subject" to add manually.',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _subjects.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final sub = _subjects[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isMobile) ...[
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: sub.nameCtrl,
                                              decoration: const InputDecoration(labelText: 'Subject Name', isDense: true),
                                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                            ),
                                          ),
                                          if (_subjects.length > 1)
                                            IconButton(
                                              icon: Icon(LucideIcons.trash2, color: AppColors.danger.base, size: 18),
                                              onPressed: () => _removeSubject(i),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: TextFormField(
                                              controller: sub.codeCtrl,
                                              decoration: const InputDecoration(labelText: 'Code', isDense: true),
                                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Expanded(
                                            flex: 2,
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
                                            flex: 2,
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
                                        ],
                                      ),
                                    ] else ...[
                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 4,
                                            child: TextFormField(
                                              controller: sub.nameCtrl,
                                              decoration: const InputDecoration(labelText: 'Subject Name', isDense: true),
                                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Expanded(
                                            flex: 2,
                                            child: TextFormField(
                                              controller: sub.codeCtrl,
                                              decoration: const InputDecoration(labelText: 'Code', isDense: true),
                                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Expanded(
                                            flex: 2,
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
                                            flex: 2,
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
                                              icon: Icon(LucideIcons.trash2, color: AppColors.danger.base, size: 18),
                                              onPressed: () => _removeSubject(i),
                                            ),
                                        ],
                                      ),
                                    ],
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4, left: 2),
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

                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    const SizedBox(width: AppSpacing.md),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Create Examination'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCourseId == null || _selectedBatchId == null || _selectedPeriodNo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Course, Batch, and Period.')),
      );
      return;
    }

    if (_subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one subject is required for the exam.')),
      );
      return;
    }

    // Check duplicate codes
    final codes = _subjects.map((s) => s.codeCtrl.text.trim().toUpperCase()).toList();
    if (codes.toSet().length != codes.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Duplicate subject codes are not allowed.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final courses = ref.read(coursesProvider).valueOrNull ?? [];
      final selectedCourse = courses.firstWhere((c) => c.id == _selectedCourseId);

      final selectedBatch = _batches.firstWhere((b) => b.id == _selectedBatchId);
      final int batchCurrentPeriod = selectedCourse.isYearWise
          ? selectedBatch.currentYear
          : (selectedCourse.isSingle ? 1 : selectedBatch.currentSemester);

      final bool isOverride = _selectedPeriodNo! > batchCurrentPeriod;

      final pType = selectedCourse.isYearWise
          ? 'year'
          : (selectedCourse.isSingle ? 'single' : 'semester');

      final semString = selectedCourse.isYearWise
          ? 'Year $_selectedPeriodNo'
          : (selectedCourse.isSingle ? 'Period 1' : 'Semester $_selectedPeriodNo');

      final exam = Exam(
        name: _nameCtrl.text.trim(),
        academicYearId: 1,
        courseId: _selectedCourseId!,
        batchId: _selectedBatchId!,
        periodType: pType,
        periodNo: _selectedPeriodNo,
        semester: semString,
        overrideReason: isOverride ? _overrideReasonCtrl.text.trim() : null,
        examDate: DateTime.now().toIso8601String(),
        status: 'draft',
      );

      final examSubjects = _subjects.asMap().entries.map((entry) {
        final i = entry.key;
        final sub = entry.value;
        return Subject(
          examId: 0,
          name: sub.nameCtrl.text.trim(),
          code: sub.codeCtrl.text.trim(),
          maxMarks: double.parse(sub.maxCtrl.text),
          passMarks: double.parse(sub.passCtrl.text),
          theoryMarks: double.parse(sub.maxCtrl.text),
          practicalMarks: 0.0,
          displayOrder: i,
        );
      }).toList();

      final repo = ref.read(examRepositoryProvider);
      await repo.createExam(exam, examSubjects);

      if (mounted) {
        ref.invalidate(examDashboardProvider);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF16A34A),
            content: Text('Exam "${_nameCtrl.text.trim()}" created successfully!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Failed to create exam: $e')),
        );
      }
    }
  }
}
