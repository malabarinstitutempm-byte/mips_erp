import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/course.dart';
import '../../core/models/course_subject.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'course_provider.dart';

class AddCourseDialog extends ConsumerStatefulWidget {
  final Course? existingCourse;
  const AddCourseDialog({super.key, this.existingCourse});

  @override
  ConsumerState<AddCourseDialog> createState() => _AddCourseDialogState();
}

class _CourseSubjectRow {
  final TextEditingController nameCtrl;
  final TextEditingController codeCtrl;
  final TextEditingController maxCtrl;
  final TextEditingController passCtrl;

  _CourseSubjectRow({
    String name = '',
    String code = '',
    String max = '100',
    String pass = '40',
  })  : nameCtrl = TextEditingController(text: name),
        codeCtrl = TextEditingController(text: code),
        maxCtrl = TextEditingController(text: max),
        passCtrl = TextEditingController(text: pass);

  void dispose() {
    nameCtrl.dispose();
    codeCtrl.dispose();
    maxCtrl.dispose();
    passCtrl.dispose();
  }
}

class _AddCourseDialogState extends ConsumerState<AddCourseDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _codeCtrl;
  late TextEditingController _durationCtrl;
  late TextEditingController _feeCtrl;
  String _courseType = 'primary';

  final List<_CourseSubjectRow> _subjects = [];
  bool _isSaving = false;
  bool _isLoadingSubjects = false;

  @override
  void initState() {
    super.initState();
    _courseType = widget.existingCourse?.courseType ?? 'primary';
    _nameCtrl = TextEditingController(text: widget.existingCourse?.name);
    _codeCtrl = TextEditingController(text: widget.existingCourse?.code);
    _durationCtrl = TextEditingController(text: widget.existingCourse?.duration);
    _feeCtrl = TextEditingController(text: widget.existingCourse?.totalFee.toString() ?? '');

    if (widget.existingCourse != null && widget.existingCourse!.id != null) {
      _loadExistingSubjects(widget.existingCourse!.id!);
    } else {
      _subjects.add(_CourseSubjectRow());
    }
  }

  Future<void> _loadExistingSubjects(int courseId) async {
    setState(() => _isLoadingSubjects = true);
    try {
      final list = await ref.read(courseRepositoryProvider).getSubjectsForCourse(courseId);
      if (mounted) {
        setState(() {
          _subjects.clear();
          if (list.isNotEmpty) {
            for (final s in list) {
              _subjects.add(_CourseSubjectRow(
                name: s.subjectName,
                code: s.subjectCode ?? '',
                max: s.maxMarks.toStringAsFixed(0),
                pass: s.passMarks.toStringAsFixed(0),
              ));
            }
          } else {
            _subjects.add(_CourseSubjectRow());
          }
        });
      }
    } catch (_) {
      if (mounted && _subjects.isEmpty) {
        _subjects.add(_CourseSubjectRow());
      }
    } finally {
      if (mounted) setState(() => _isLoadingSubjects = false);
    }
  }

  void _addSubject() {
    setState(() {
      _subjects.add(_CourseSubjectRow());
    });
  }

  void _removeSubject(int index) {
    setState(() {
      final removed = _subjects.removeAt(index);
      removed.dispose();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _durationCtrl.dispose();
    _feeCtrl.dispose();
    for (final s in _subjects) {
      s.dispose();
    }
    super.dispose();
  }

  Widget _buildPresetChip(_CourseSubjectRow sub, String max, String pass) {
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final courseRepo = ref.read(courseRepositoryProvider);
      final course = Course(
        id: widget.existingCourse?.id,
        name: _nameCtrl.text.trim(),
        code: _codeCtrl.text.trim(),
        duration: _durationCtrl.text.trim(),
        courseType: _courseType,
        totalFee: double.tryParse(_feeCtrl.text.trim()) ?? 0.0,
        universityId: widget.existingCourse?.universityId ?? 1,
      );

      int courseId;
      if (widget.existingCourse == null) {
        courseId = await courseRepo.addCourse(course);
      } else {
        courseId = widget.existingCourse!.id!;
        await courseRepo.updateCourse(course);
      }

      // Save Course Subjects
      final validSubjects = _subjects
          .where((s) => s.nameCtrl.text.trim().isNotEmpty)
          .map((s) => CourseSubject(
                courseId: courseId,
                subjectName: s.nameCtrl.text.trim(),
                subjectCode: s.codeCtrl.text.trim().isEmpty ? null : s.codeCtrl.text.trim(),
                maxMarks: double.tryParse(s.maxCtrl.text.trim()) ?? 100.0,
                passMarks: double.tryParse(s.passCtrl.text.trim()) ?? 40.0,
              ))
          .toList();

      await courseRepo.saveCourseSubjects(courseId, validSubjects);

      ref.invalidate(coursesProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existingCourse == null
                ? 'Course created with ${validSubjects.length} subjects!'
                : 'Course and subjects updated successfully!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save course: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radius14)),
      child: Container(
        width: 860,
        height: 640,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                          color: AppColors.courses.tint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(LucideIcons.bookOpen, color: AppColors.courses.dark, size: 20),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        widget.existingCourse == null ? 'Create New Course' : 'Edit Course',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.lg),

              // Content Area
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Course Metadata
                    SizedBox(
                      width: 280,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Course Details',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Course Name',
                                hintText: 'e.g. Diploma in Medical Lab',
                                prefixIcon: Icon(LucideIcons.graduationCap, size: 18),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Course name is required' : null,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _codeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Course Code',
                                hintText: 'e.g. DMLT',
                                prefixIcon: Icon(LucideIcons.tag, size: 18),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Course code is required' : null,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            DropdownButtonFormField<String>(
                              value: _courseType,
                              decoration: const InputDecoration(
                                labelText: 'Course Type',
                                prefixIcon: Icon(LucideIcons.layers, size: 18),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'primary', child: Text('Primary Course')),
                                DropdownMenuItem(value: 'skill', child: Text('Skill Course (Optional)')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _courseType = val);
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _durationCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Duration',
                                hintText: 'e.g. 2 Years / 6 Months',
                                prefixIcon: Icon(LucideIcons.clock, size: 18),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _feeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Total Course Fee (₹)',
                                hintText: 'e.g. 50000',
                                prefixIcon: Icon(LucideIcons.indianRupee, size: 18),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Fee is required';
                                if (double.tryParse(v.trim()) == null) return 'Enter valid number';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: AppSpacing.xl),
                    const VerticalDivider(width: 1),
                    const SizedBox(width: AppSpacing.xl),

                    // Right Column: Course Subjects
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Curriculum Subjects',
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE0F2FE),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            'Optional',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Define optional subjects now. Total & pass marks can be edited during mark entry.',
                                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              ElevatedButton.icon(
                                onPressed: _addSubject,
                                icon: const Icon(LucideIcons.plus, size: 15),
                                label: const Text('Add Subject'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // Subjects List Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: const [
                                Expanded(flex: 4, child: Text('Subject Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                SizedBox(width: 8),
                                Expanded(flex: 2, child: Text('Code', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                SizedBox(width: 8),
                                Expanded(flex: 2, child: Text('Max Mark', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                SizedBox(width: 8),
                                Expanded(flex: 2, child: Text('Pass Mark', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                SizedBox(width: 36),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),

                          Expanded(
                            child: _isLoadingSubjects
                                ? const Center(child: CircularProgressIndicator())
                                : _subjects.isEmpty
                                    ? Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(color: AppColors.border),
                                          borderRadius: BorderRadius.circular(AppRadius.card),
                                        ),
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(LucideIcons.bookOpen, size: 36, color: AppColors.textMuted.withOpacity(0.4)),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'No Subjects Added (Optional)',
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textStrong),
                                              ),
                                              const SizedBox(height: 4),
                                              const Text(
                                                'You can create the course now and add subjects anytime later.',
                                                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 12),
                                              OutlinedButton.icon(
                                                onPressed: _addSubject,
                                                icon: const Icon(LucideIcons.plus, size: 14),
                                                label: const Text('Add Optional Subject'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(color: AppColors.border),
                                          borderRadius: BorderRadius.circular(AppRadius.card),
                                        ),
                                        child: ListView.separated(
                                          padding: const EdgeInsets.all(AppSpacing.sm),
                                          itemCount: _subjects.length,
                                          separatorBuilder: (_, __) => const Divider(height: 1),
                                          itemBuilder: (context, i) {
                                            final sub = _subjects[i];
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Expanded(
                                                        flex: 4,
                                                        child: TextFormField(
                                                          controller: sub.nameCtrl,
                                                          decoration: const InputDecoration(
                                                            hintText: 'e.g. Clinical Biochemistry',
                                                            isDense: true,
                                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                          ),
                                                          validator: (v) {
                                                            // Optional: If row is completely blank, no error
                                                            if (sub.codeCtrl.text.trim().isNotEmpty && (v == null || v.trim().isEmpty)) {
                                                              return 'Required if code entered';
                                                            }
                                                            return null;
                                                          },
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        flex: 2,
                                                        child: TextFormField(
                                                          controller: sub.codeCtrl,
                                                          decoration: const InputDecoration(
                                                            hintText: 'e.g. CB101',
                                                            isDense: true,
                                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        flex: 2,
                                                        child: TextFormField(
                                                          controller: sub.maxCtrl,
                                                          keyboardType: TextInputType.number,
                                                          decoration: const InputDecoration(
                                                            isDense: true,
                                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                          ),
                                                          validator: (v) {
                                                            if (sub.nameCtrl.text.trim().isNotEmpty) {
                                                              final n = double.tryParse(v ?? '');
                                                              if (n == null || n <= 0) return 'Invalid';
                                                            }
                                                            return null;
                                                          },
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        flex: 2,
                                                        child: TextFormField(
                                                          controller: sub.passCtrl,
                                                          keyboardType: TextInputType.number,
                                                          decoration: const InputDecoration(
                                                            isDense: true,
                                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                          ),
                                                          validator: (v) {
                                                            if (sub.nameCtrl.text.trim().isNotEmpty) {
                                                              final p = double.tryParse(v ?? '');
                                                              final m = double.tryParse(sub.maxCtrl.text);
                                                              if (p == null || p < 0) return 'Invalid';
                                                              if (m != null && p > m) return '> Max';
                                                            }
                                                            return null;
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 36,
                                                        child: IconButton(
                                                          icon: Icon(LucideIcons.trash2, size: 16, color: AppColors.danger.base),
                                                          onPressed: () => _removeSubject(i),
                                                          tooltip: 'Remove Subject',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 4, left: 2, bottom: 2),
                                                    child: Row(
                                                      children: [
                                                        const Text('Presets:', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                                        const SizedBox(width: 4),
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(widget.existingCourse == null ? 'Create Course & Subjects' : 'Save Changes'),
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
