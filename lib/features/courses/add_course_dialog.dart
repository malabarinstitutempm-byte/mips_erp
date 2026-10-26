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
  int? id;
  int? periodNo;
  final TextEditingController nameCtrl;
  final TextEditingController codeCtrl;
  final TextEditingController maxCtrl;
  final TextEditingController passCtrl;

  _CourseSubjectRow({
    this.id,
    this.periodNo,
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
  String _structure = 'semester'; // 'semester', 'year', 'single'
  String _attendanceBasis = 'semester'; // 'semester', 'year', 'none'
  bool _isStructureLocked = false;

  final List<_CourseSubjectRow> _subjects = [];
  bool _isSaving = false;
  bool _isLoadingSubjects = false;
  int _mobileTabIndex = 0; // 0 = Course Details, 1 = Subjects

  // Selected tab: 1..N for periods, or -1 for "Unassigned"
  int _selectedTabPeriod = 1;

  @override
  void initState() {
    super.initState();
    final c = widget.existingCourse;
    _courseType = c?.courseType ?? 'primary';
    _structure = c?.structure ?? (_courseType == 'skill' ? 'single' : 'semester');
    _attendanceBasis = c?.attendanceBasis ?? (_structure == 'single' ? 'none' : _structure);

    _nameCtrl = TextEditingController(text: c?.name);
    _codeCtrl = TextEditingController(text: c?.code);
    _durationCtrl = TextEditingController(text: c?.duration ?? '2 Years');
    _feeCtrl = TextEditingController(text: c?.totalFee.toString() ?? '');

    if (c != null && c.id != null) {
      _checkStructureLock(c.id!);
      _loadExistingSubjects(c.id!);
    } else {
      _subjects.add(_CourseSubjectRow(periodNo: _structure == 'single' ? null : 1));
    }
  }

  Future<void> _checkStructureLock(int courseId) async {
    try {
      final locked = await ref.read(courseRepositoryProvider).isCourseStructureLocked(courseId);
      if (mounted) setState(() => _isStructureLocked = locked);
    } catch (_) {}
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
                id: s.id,
                periodNo: s.periodNo,
                name: s.subjectName,
                code: s.subjectCode ?? '',
                max: s.maxMarks.toStringAsFixed(0),
                pass: s.passMarks.toStringAsFixed(0),
              ));
            }
          } else {
            _subjects.add(_CourseSubjectRow(periodNo: _structure == 'single' ? null : 1));
          }
        });
      }
    } catch (_) {
      if (mounted && _subjects.isEmpty) {
        _subjects.add(_CourseSubjectRow(periodNo: _structure == 'single' ? null : 1));
      }
    } finally {
      if (mounted) setState(() => _isLoadingSubjects = false);
    }
  }

  int get _durationYears {
    final match = RegExp(r'\d+').firstMatch(_durationCtrl.text);
    if (match != null) {
      final val = int.tryParse(match.group(0)!);
      if (val != null && val > 0) return val;
    }
    return 2;
  }

  int get _totalPeriods {
    if (_structure == 'single') return 1;
    if (_structure == 'year') return _durationYears;
    return _durationYears * 2;
  }

  String get _periodLabel => _structure == 'year' ? 'Year' : 'Semester';

  List<_CourseSubjectRow> get _currentPeriodSubjects {
    if (_structure == 'single') return _subjects;
    if (_selectedTabPeriod == -1) {
      return _subjects.where((s) => s.periodNo == null).toList();
    }
    return _subjects.where((s) => s.periodNo == _selectedTabPeriod).toList();
  }

  bool get _hasUnassignedSubjects =>
      _structure != 'single' && _subjects.any((s) => s.periodNo == null);

  void _addSubject() {
    setState(() {
      _subjects.add(_CourseSubjectRow(
        periodNo: _structure == 'single'
            ? null
            : (_selectedTabPeriod == -1 ? 1 : _selectedTabPeriod),
      ));
    });
  }

  void _removeSubject(_CourseSubjectRow row) {
    setState(() {
      _subjects.remove(row);
      row.dispose();
    });
  }

  void _copySubjectsFromDialog() {
    final periods = List.generate(_totalPeriods, (i) => i + 1)
        .where((p) => p != _selectedTabPeriod)
        .toList();

    if (periods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other periods available to copy from.')),
      );
      return;
    }

    int sourcePeriod = periods.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Copy Subjects to $_periodLabel $_selectedTabPeriod'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select the $_periodLabel to copy subjects from:'),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: sourcePeriod,
                decoration: InputDecoration(
                  labelText: 'Source $_periodLabel',
                  border: const OutlineInputBorder(),
                ),
                items: periods.map((p) {
                  final count = _subjects.where((s) => s.periodNo == p).length;
                  return DropdownMenuItem(
                    value: p,
                    child: Text('$_periodLabel $p ($count subjects)'),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => sourcePeriod = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final toCopy = _subjects.where((s) => s.periodNo == sourcePeriod).toList();
                if (toCopy.isEmpty) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('No subjects found in $_periodLabel $sourcePeriod to copy.')),
                  );
                  return;
                }

                setState(() {
                  for (final s in toCopy) {
                    _subjects.add(_CourseSubjectRow(
                      periodNo: _selectedTabPeriod == -1 ? 1 : _selectedTabPeriod,
                      name: s.nameCtrl.text.trim(),
                      code: s.codeCtrl.text.trim(),
                      max: s.maxCtrl.text.trim(),
                      pass: s.passCtrl.text.trim(),
                    ));
                  }
                });

                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied ${toCopy.length} subjects to $_periodLabel $_selectedTabPeriod!')),
                );
              },
              child: const Text('Copy Subjects'),
            ),
          ],
        ),
      ),
    );
  }

  void _assignUnassignedDialog(_CourseSubjectRow sub) {
    int targetPeriod = 1;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Assign "${sub.nameCtrl.text}" to $_periodLabel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: targetPeriod,
                decoration: InputDecoration(labelText: 'Target $_periodLabel'),
                items: List.generate(_totalPeriods, (i) => i + 1).map((p) {
                  return DropdownMenuItem(value: p, child: Text('$_periodLabel $p'));
                }).toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => targetPeriod = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                setState(() => sub.periodNo = targetPeriod);
                Navigator.pop(ctx);
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
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
        structure: _structure,
        attendanceBasis: _attendanceBasis,
        totalFee: double.tryParse(_feeCtrl.text.trim()) ?? 0.0,
        universityId: widget.existingCourse?.universityId ?? 1,
      );

      // Prepare Course Subjects
      final validSubjects = _subjects
          .where((s) => s.nameCtrl.text.trim().isNotEmpty)
          .map((s) => CourseSubject(
                id: s.id,
                courseId: widget.existingCourse?.id ?? 0,
                periodNo: _structure == 'single' ? null : s.periodNo,
                subjectName: s.nameCtrl.text.trim(),
                subjectCode: s.codeCtrl.text.trim().isEmpty ? null : s.codeCtrl.text.trim(),
                maxMarks: double.tryParse(s.maxCtrl.text.trim()) ?? 100.0,
                passMarks: double.tryParse(s.passCtrl.text.trim()) ?? 40.0,
              ))
          .toList();

      if (widget.existingCourse == null) {
        await courseRepo.createCourse(course, validSubjects);
      } else {
        await courseRepo.updateCourse(course, validSubjects);
      }

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

  Widget _buildCourseConfigForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Course Configuration',
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

        // Structure Choice
        DropdownButtonFormField<String>(
          value: _structure,
          decoration: InputDecoration(
            labelText: 'Course Structure',
            prefixIcon: const Icon(LucideIcons.layoutGrid, size: 18),
            helperText: _isStructureLocked ? 'Locked by academic records' : 'Determines syllabus and exam periods',
          ),
          items: const [
            DropdownMenuItem(value: 'semester', child: Text('Semester-wise')),
            DropdownMenuItem(value: 'year', child: Text('Year-wise')),
            DropdownMenuItem(value: 'single', child: Text('Single Subject List')),
          ],
          onChanged: _isStructureLocked
              ? null
              : (val) {
                  if (val != null) {
                    setState(() {
                      _structure = val;
                      _attendanceBasis = val == 'single' ? 'none' : val;
                      _selectedTabPeriod = 1;
                    });
                  }
                },
        ),
        const SizedBox(height: AppSpacing.md),

        // Attendance Basis
        DropdownButtonFormField<String>(
          value: _attendanceBasis,
          decoration: const InputDecoration(
            labelText: 'Attendance Basis',
            prefixIcon: Icon(LucideIcons.calendarCheck, size: 18),
            helperText: 'Attendance evaluation window',
          ),
          items: const [
            DropdownMenuItem(value: 'semester', child: Text('Semester-basis (6 Months)')),
            DropdownMenuItem(value: 'year', child: Text('Year-basis (Annual)')),
            DropdownMenuItem(value: 'none', child: Text('No Attendance Tracking')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _attendanceBasis = val);
          },
        ),
        const SizedBox(height: AppSpacing.md),

        DropdownButtonFormField<String>(
          value: _courseType,
          decoration: const InputDecoration(
            labelText: 'Course Category',
            prefixIcon: Icon(LucideIcons.layers, size: 18),
          ),
          items: const [
            DropdownMenuItem(value: 'primary', child: Text('Primary Degree/Diploma')),
            DropdownMenuItem(value: 'skill', child: Text('Certified Skill Course')),
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
            hintText: 'e.g. 2 Years / 1 Year',
            prefixIcon: Icon(LucideIcons.clock, size: 18),
          ),
          onChanged: (_) => setState(() {}),
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
    );
  }

  Widget _buildSubjectsEditor({required bool isMobile}) {
    final curSubs = _currentPeriodSubjects;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Period Tabs Header
        if (_structure != 'single') ...[
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int p = 1; p <= _totalPeriods; p++) ...[
                        InkWell(
                          onTap: () => setState(() => _selectedTabPeriod = p),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedTabPeriod == p
                                  ? AppColors.brandDark
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _selectedTabPeriod == p
                                    ? AppColors.brandDark
                                    : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '$_periodLabel $p',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTabPeriod == p ? Colors.white : AppColors.textStrong,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _selectedTabPeriod == p ? Colors.white24 : Colors.black12,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_subjects.where((s) => s.periodNo == p).length}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _selectedTabPeriod == p ? Colors.white : AppColors.textMuted,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Unassigned Tab if any exist
                      if (_hasUnassignedSubjects) ...[
                        InkWell(
                          onTap: () => setState(() => _selectedTabPeriod = -1),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedTabPeriod == -1
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _selectedTabPeriod == -1
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFFFCA5A5),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.alertCircle,
                                  size: 13,
                                  color: _selectedTabPeriod == -1 ? Colors.white : const Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Unassigned',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTabPeriod == -1 ? Colors.white : const Color(0xFFDC2626),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(${_subjects.where((s) => s.periodNo == null).length})',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTabPeriod == -1 ? Colors.white : const Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _copySubjectsFromDialog,
                  icon: const Icon(LucideIcons.copy, size: 13),
                  label: const Text('Copy from...'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],

        // Subtitle & Add button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _structure == 'single'
                    ? 'Curriculum Subjects (${_subjects.length})'
                    : (_selectedTabPeriod == -1
                        ? 'Unassigned Subjects'
                        : '$_periodLabel $_selectedTabPeriod Subjects (${curSubs.length})'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            FilledButton.icon(
              onPressed: _addSubject,
              icon: const Icon(LucideIcons.plus, size: 14),
              label: Text(_structure == 'single' ? 'Add Subject' : 'Add to $_periodLabel $_selectedTabPeriod'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.purple,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // Table Header (Desktop Only)
        if (!isMobile) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Expanded(flex: 5, child: Text('Subject Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                const Expanded(flex: 3, child: Text('Code', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                const Expanded(flex: 2, child: Text('Max', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                const Expanded(flex: 2, child: Text('Pass', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                const Expanded(flex: 3, child: Text('Presets', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                if (_selectedTabPeriod == -1)
                  const Expanded(flex: 3, child: Text('Assign', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(width: 32),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],

        // Subjects List Rows
        Expanded(
          child: _isLoadingSubjects
              ? const Center(child: CircularProgressIndicator())
              : curSubs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.bookOpen, size: 36, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            _selectedTabPeriod == -1
                                ? 'No unassigned subjects!'
                                : 'No subjects added for $_periodLabel $_selectedTabPeriod yet.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: Colors.purple),
                            onPressed: _addSubject,
                            icon: const Icon(LucideIcons.plus, size: 14),
                            label: const Text('Add First Subject'),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: curSubs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final sub = curSubs[index];
                        if (isMobile) {
                          // Mobile Card View
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: sub.nameCtrl,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          labelText: 'Subject Name',
                                          hintText: 'e.g. Clinical Biochemistry',
                                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(LucideIcons.trash2, size: 18, color: Color(0xFFEF4444)),
                                      onPressed: () => _removeSubject(sub),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: TextFormField(
                                        controller: sub.codeCtrl,
                                        style: const TextStyle(fontSize: 12),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          labelText: 'Code',
                                          hintText: 'BIO101',
                                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: sub.maxCtrl,
                                        style: const TextStyle(fontSize: 12),
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          labelText: 'Max',
                                          hintText: '100',
                                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: sub.passCtrl,
                                        style: const TextStyle(fontSize: 12),
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          labelText: 'Pass',
                                          hintText: '40',
                                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Text('Presets: ', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                    _buildPresetChip(sub, '100', '40'),
                                    const SizedBox(width: 4),
                                    _buildPresetChip(sub, '50', '20'),
                                    const SizedBox(width: 4),
                                    _buildPresetChip(sub, '75', '30'),
                                    if (_selectedTabPeriod == -1) ...[
                                      const Spacer(),
                                      OutlinedButton(
                                        onPressed: () => _assignUnassignedDialog(sub),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        ),
                                        child: const Text('Assign', style: TextStyle(fontSize: 11)),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          );
                        }

                        // Desktop Table Row
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: TextFormField(
                                  controller: sub.nameCtrl,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: 'e.g. Clinical Biochemistry',
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: sub.codeCtrl,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: 'e.g. BIO101',
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: sub.maxCtrl,
                                  style: const TextStyle(fontSize: 12),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '100',
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: sub.passCtrl,
                                  style: const TextStyle(fontSize: 12),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '40',
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    _buildPresetChip(sub, '100', '40'),
                                    const SizedBox(width: 4),
                                    _buildPresetChip(sub, '50', '20'),
                                  ],
                                ),
                              ),
                              if (_selectedTabPeriod == -1) ...[
                                const SizedBox(width: 6),
                                Expanded(
                                  flex: 3,
                                  child: OutlinedButton(
                                    onPressed: () => _assignUnassignedDialog(sub),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    ),
                                    child: const Text('Assign', style: TextStyle(fontSize: 11)),
                                  ),
                                ),
                              ],
                              IconButton(
                                icon: const Icon(LucideIcons.trash2, size: 16, color: Color(0xFFEF4444)),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: () => _removeSubject(sub),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isMobile = screenWidth < 768;

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 14)
          : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radius14)),
      child: Container(
        width: isMobile ? double.infinity : 980,
        height: isMobile ? (screenHeight * 0.94) : 700,
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
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
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1),

              // Locked Warning Banner (if structure is locked)
              if (_isStructureLocked) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: Row(
                    children: const [
                      Icon(LucideIcons.lock, size: 16, color: Color(0xFFB45309)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Course structure is locked because exams, marks, or attendance records already exist for this course.',
                          style: TextStyle(fontSize: 12, color: Color(0xFFB45309), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Mobile Tabs Switcher
              if (isMobile) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _mobileTabIndex = 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _mobileTabIndex == 0 ? AppColors.brandDark : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.bookOpen, size: 14, color: _mobileTabIndex == 0 ? Colors.white : AppColors.textStrong),
                                const SizedBox(width: 6),
                                Text(
                                  '1. Course Info',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _mobileTabIndex == 0 ? Colors.white : AppColors.textStrong,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _mobileTabIndex = 1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _mobileTabIndex == 1 ? Colors.purple : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.listOrdered, size: 14, color: _mobileTabIndex == 1 ? Colors.white : AppColors.textStrong),
                                const SizedBox(width: 6),
                                Text(
                                  '2. Subjects (${_subjects.length})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _mobileTabIndex == 1 ? Colors.white : AppColors.textStrong,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ] else ...[
                const SizedBox(height: AppSpacing.md),
              ],

              // Content Area
              Expanded(
                child: isMobile
                    ? (_mobileTabIndex == 0
                        ? SingleChildScrollView(child: _buildCourseConfigForm())
                        : _buildSubjectsEditor(isMobile: true))
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column: Course Metadata
                          SizedBox(
                            width: 290,
                            child: SingleChildScrollView(
                              child: _buildCourseConfigForm(),
                            ),
                          ),

                          const SizedBox(width: AppSpacing.lg),
                          const VerticalDivider(width: 1),
                          const SizedBox(width: AppSpacing.lg),

                          // Right Column: Period Tabs & Subject Editor
                          Expanded(
                            child: _buildSubjectsEditor(isMobile: false),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),

              // Bottom Actions
              if (isMobile) ...[
                if (_mobileTabIndex == 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton(
                        onPressed: _isSaving ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.purple),
                        onPressed: () {
                          if (_formKey.currentState?.validate() ?? false) {
                            setState(() => _mobileTabIndex = 1);
                          }
                        },
                        icon: const Icon(LucideIcons.arrowRight, size: 16),
                        label: Text('Next: Subjects (${_subjects.length}) →'),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _mobileTabIndex = 0),
                        icon: const Icon(LucideIcons.arrowLeft, size: 16),
                        label: const Text('Back to Info'),
                      ),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        child: _isSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(widget.existingCourse == null ? 'Create Course' : 'Save Changes'),
                      ),
                    ],
                  ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(widget.existingCourse == null ? 'Create Course' : 'Save Changes'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
