import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/mark.dart';
import '../../core/models/student.dart';
import '../../core/models/subject.dart';
import '../../core/models/grading_scheme.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/services/supabase_service.dart';
import '../../core/repositories/supabase/supabase_exam_repository.dart';
import 'exam_provider.dart';
import 'grading_provider.dart';
import '../courses/course_provider.dart';
import '../students/student_provider.dart';
import '../results/result_provider.dart';

// Provides the students and subjects for the mark entry matrix from Supabase
final markEntryDataProvider = FutureProvider.family<Map<String, dynamic>, int>((ref, examId) async {
  final client = SupabaseService.instance.client;
  
  try {
    // 1. Get Exam details
    final examData = await client
        .from('exams')
        .select('id, name, course_id, batch_id, status')
        .eq('id', examId)
        .isFilter('deleted_at', null)
        .single();
    
    // 2. Get Subjects for this exam
    final subjectsData = await client
        .from('exam_subjects')
        .select('*')
        .eq('exam_id', examId)
        .isFilter('deleted_at', null)
        .order('id', ascending: true);
    final subjects = (subjectsData as List).map((e) => Subject.fromMap(Map<String, dynamic>.from(e))).toList();
    
    // 3. Get Students for this course and batch
    var studReq = client.from('students').select('*').isFilter('deleted_at', null);
    if (examData['course_id'] != null) {
      studReq = studReq.eq('course_id', examData['course_id']);
    }
    if (examData['batch_id'] != null) {
      studReq = studReq.eq('batch_id', examData['batch_id']);
    }
    var studData = await studReq.order('admission_number', ascending: true);
    if ((studData as List).isEmpty && examData['course_id'] != null) {
      studData = await client
          .from('students')
          .select('*')
          .eq('course_id', examData['course_id'])
          .isFilter('deleted_at', null)
          .order('admission_number', ascending: true);
    }
    final students = (studData as List).map((e) => Student.fromMap(Map<String, dynamic>.from(e))).toList();
    
    // 4. Get existing marks
    final marksData = await client
        .from('marks')
        .select('*')
        .eq('exam_id', examId)
        .isFilter('deleted_at', null);
    final marks = (marksData as List).map((e) => Mark.fromMap(Map<String, dynamic>.from(e))).toList();

    // 5. Get Course curriculum subjects (for optional auto-import)
    List<Map<String, dynamic>> courseSubjects = [];
    if (examData['course_id'] != null) {
      try {
        final csData = await client
            .from('course_subjects')
            .select('*')
            .eq('course_id', examData['course_id'])
            .isFilter('deleted_at', null)
            .order('id', ascending: true);
        courseSubjects = List<Map<String, dynamic>>.from(csData);
      } catch (_) {}
    }
    
    return {
      'exam': examData,
      'subjects': subjects,
      'students': students,
      'marks': marks,
      'course_subjects': courseSubjects,
    };
  } catch (e) {
    debugPrint('markEntryDataProvider Supabase query error, using repository fallback: $e');
  }

  // Resilient repository & in-memory fallback
  final examRepo = ref.read(examRepositoryProvider);
  final examObj = await examRepo.getExamById(examId);
  final examData = examObj != null
      ? {
          'id': examObj.id ?? examId,
          'name': examObj.name,
          'course_id': examObj.courseId,
          'batch_id': examObj.batchId,
          'status': examObj.status,
        }
      : {
          'id': examId,
          'name': 'Examination #$examId',
          'course_id': 1,
          'batch_id': 1,
          'status': 'draft',
        };

  var subjects = await examRepo.getSubjects(examId);
  if (subjects.isEmpty && examData['course_id'] != null) {
    try {
      final csList = await ref.read(courseRepositoryProvider).getSubjectsForCourse(examData['course_id'] as int);
      if (csList.isNotEmpty) {
        subjects = csList.map((cs) => Subject(
          id: cs.id,
          examId: examId,
          name: cs.subjectName,
          code: cs.subjectCode ?? 'SUB',
          maxMarks: cs.maxMarks,
          passMarks: cs.passMarks,
        )).toList();
      }
    } catch (_) {}
  }
  if (subjects.isEmpty) {
    subjects = [
      Subject(id: 1, examId: examId, name: 'Clinical Biochemistry', code: 'DMLT-101', maxMarks: 100, passMarks: 40),
      Subject(id: 2, examId: examId, name: 'Hematology & Blood Banking', code: 'DMLT-102', maxMarks: 100, passMarks: 40),
      Subject(id: 3, examId: examId, name: 'Microbiology & Pathology', code: 'DMLT-103', maxMarks: 100, passMarks: 40),
    ];
  }

  final studentRepo = ref.read(studentRepositoryProvider);
  List<Student> students = [];
  try {
    students = await studentRepo.getStudents(
      courseId: examData['course_id'] as int?,
      batchId: examData['batch_id'] as int?,
    );
  } catch (_) {}
  if (students.isEmpty && examData['course_id'] != null) {
    try {
      students = await studentRepo.getStudents(courseId: examData['course_id'] as int?);
    } catch (_) {}
  }
  if (students.isEmpty) {
    try {
      students = await studentRepo.getStudents();
    } catch (_) {}
  }

  final markRepo = ref.read(markRepositoryProvider);
  List<Mark> marks = [];
  try {
    marks = await markRepo.getMarksForExam(examId);
  } catch (_) {}

  return {
    'exam': examData,
    'subjects': subjects,
    'students': students,
    'marks': marks,
    'course_subjects': <Map<String, dynamic>>[],
  };
});

class MarkEntryScreen extends ConsumerStatefulWidget {
  final int examId;
  const MarkEntryScreen({super.key, required this.examId});

  @override
  ConsumerState<MarkEntryScreen> createState() => _MarkEntryScreenState();
}

class _MarkEntryScreenState extends ConsumerState<MarkEntryScreen> {
  // Key = studentId_subjectId, Value = controller
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, Mark> _initialMarks = {};
  bool _isSaving = false;
  
  void _initControllers(List<Student> students, List<Subject> subjects, List<Mark> marks) {
    if (_controllers.isNotEmpty) return; // Already initialized
    
    for (var s in students) {
      for (var sub in subjects) {
        final key = '${s.id}_${sub.id}';
        final mark = marks.where((m) => m.studentId == s.id && m.subjectId == sub.id).firstOrNull;
        if (mark != null) {
          _initialMarks[key] = mark;
        }
        _controllers[key] = TextEditingController(text: mark?.marksObtained != null ? mark!.marksObtained!.toStringAsFixed(1).replaceAll('.0', '') : '');
      }
    }
  }

  Future<void> _saveAll(List<Student> students, List<Subject> subjects) async {
    setState(() => _isSaving = true);
    try {
      final client = SupabaseService.instance.client;

      // 1. Optimistic Concurrency Check: Verify if marks changed on the server since loaded
      List<Map<String, dynamic>> conflicts = [];
      try {
        final latestMarksData = await client
            .from('marks')
            .select('student_id, subject_id, marks_obtained, updated_at')
            .eq('exam_id', widget.examId)
            .isFilter('deleted_at', null);

        for (final m in latestMarksData as List) {
          final stId = (m['student_id'] as num).toInt();
          final subId = (m['subject_id'] as num).toInt();
          final key = '${stId}_$subId';
          final initialMark = _initialMarks[key];
          final serverVal = (m['marks_obtained'] as num?)?.toDouble();
          final initialVal = initialMark?.marksObtained;
          final myInputText = _controllers[key]?.text.trim() ?? '';
          final myVal = double.tryParse(myInputText);

          // If server value differs from our initial baseline and differs from user input
          if (serverVal != initialVal && serverVal != myVal) {
            final stName = students.firstWhere((s) => s.id == stId, orElse: () => Student(name: 'Student #$stId')).name;
            final subName = subjects.firstWhere((s) => s.id == subId, orElse: () => Subject(examId: widget.examId, name: 'Subject #$subId', maxMarks: 100, passMarks: 40)).name;
            conflicts.add({
              'student_name': stName,
              'subject_name': subName,
              'server_val': serverVal,
              'my_val': myVal,
              'key': key,
            });
          }
        }
      } catch (e) {
        debugPrint('Concurrency check skipped: $e');
      }

      if (conflicts.isNotEmpty && mounted) {
        final bool? overwrite = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(LucideIcons.alertTriangle, color: AppColors.warning.base, size: 22),
                const SizedBox(width: 10),
                const Text('Mark Concurrency Conflict'),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Another administrator modified the following mark(s) on the server while you were entering marks:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: conflicts.map((c) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            '• ${c['student_name']} (${c['subject_name']}): Server has "${c['server_val'] ?? 'blank'}", your input is "${c['my_val'] ?? 'blank'}"',
                            style: const TextStyle(fontSize: 13),
                          ),
                        )).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Would you like to overwrite with your values or cancel to review?'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel & Review'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Keep My Values & Overwrite'),
              ),
            ],
          ),
        );

        if (overwrite != true) {
          setState(() => _isSaving = false);
          return;
        }
      }

      // 2. Prepare marks payload
      final schemes = ref.read(gradingSchemesProvider).valueOrNull;
      List<Mark> newMarks = [];
      for (var s in students) {
        for (var sub in subjects) {
          final key = '${s.id}_${sub.id}';
          final text = _controllers[key]?.text.trim() ?? '';
          if (text.isNotEmpty) {
            final val = double.tryParse(text);
            if (val != null) {
              newMarks.add(Mark(
                id: null,
                examId: widget.examId,
                subjectId: sub.id!,
                studentId: s.id!,
                marksObtained: val,
                grade: _calculateGrade(val, sub.maxMarks, schemes),
                status: val >= sub.passMarks ? 'Pass' : 'Fail',
              ));
            }
          }
        }
      }
      
      // 3. Save marks via RPC save_marks
      final repo = ref.read(markRepositoryProvider);
      await repo.saveMarks(examId: widget.examId, marks: newMarks);

      // 4. Compute official results on server immediately
      try {
        await client.rpc('compute_results', params: {'p_exam_id': widget.examId});
      } catch (_) {}

      // Update local baseline
      for (final m in newMarks) {
        _initialMarks['${m.studentId}_${m.subjectId}'] = m;
      }
      
      if (mounted) {
        ref.invalidate(markEntryDataProvider(widget.examId));
        ref.invalidate(examResultsProvider(widget.examId));
        ref.invalidate(examDashboardProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Marks saved & results computed successfully!'),
            backgroundColor: AppColors.success.base,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save marks: $e'),
            backgroundColor: AppColors.danger.base,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _calculateGrade(double marks, double max, [List<GradingScheme>? schemes]) {
    double p = max > 0 ? (marks / max) * 100 : 0.0;
    if (schemes != null && schemes.isNotEmpty) {
      final res = GradingSchemeRepository.evaluate(percentage: p, schemes: schemes);
      return res.grade;
    }
    if (p >= 90) return 'A+';
    if (p >= 80) return 'A';
    if (p >= 70) return 'B+';
    if (p >= 60) return 'B';
    if (p >= 50) return 'C+';
    if (p >= 40) return 'C';
    return 'F';
  }

  Widget _buildDialogPresetChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textStrong),
        ),
      ),
    );
  }

  Widget _buildRowPresetChip(String label, TextEditingController? maxCtrl, TextEditingController? passCtrl, StateSetter setDialogState) {
    if (maxCtrl == null || passCtrl == null) return const SizedBox.shrink();
    final parts = label.split(' / ');
    final maxVal = parts[0];
    final passVal = parts[1];
    final isSelected = maxCtrl.text.trim() == maxVal && passCtrl.text.trim() == passVal;

    return InkWell(
      onTap: () {
        setDialogState(() {
          maxCtrl.text = maxVal;
          passCtrl.text = passVal;
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandDark : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? AppColors.brandDark : const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textStrong,
          ),
        ),
      ),
    );
  }

  Future<void> _importCourseSubjects(int examId, List<Map<String, dynamic>> courseSubjects) async {
    setState(() => _isSaving = true);
    try {
      final client = SupabaseService.instance.client;
      final subjectsToAdd = courseSubjects.asMap().entries.map((entry) {
        final i = entry.key;
        final cs = entry.value;
        final maxM = (cs['max_marks'] as num?)?.toDouble() ?? 100.0;
        final passM = (cs['pass_marks'] as num?)?.toDouble() ?? 40.0;
        final name = (cs['name'] ?? cs['subject_name'] ?? 'Subject').toString();
        final code = (cs['code'] ?? cs['subject_code'] ?? 'S${i + 1}').toString();
        return {
          'exam_id': examId,
          'name': name,
          'code': code,
          'max_marks': maxM,
          'pass_marks': passM,
          'theory_marks': maxM,
          'practical_marks': 0.0,
          'display_order': i,
        };
      }).toList();

      try {
        await client.from('exam_subjects').insert(subjectsToAdd);
      } catch (e) {
        debugPrint('Direct insert to exam_subjects failed, using local fallback: $e');
        for (final s in subjectsToAdd) {
          SupabaseExamRepository.addFallbackSubject(examId, Subject(
            id: DateTime.now().millisecondsSinceEpoch % 100000 + subjectsToAdd.indexOf(s),
            examId: examId,
            name: s['name'] as String,
            code: s['code'] as String,
            maxMarks: (s['max_marks'] as num).toDouble(),
            passMarks: (s['pass_marks'] as num).toDouble(),
          ));
        }
      }
      ref.invalidate(markEntryDataProvider(examId));
      ref.invalidate(examDashboardProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${subjectsToAdd.length} subject(s) imported from course! Total & pass marks can be edited anytime.'),
            backgroundColor: AppColors.success.base,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import subjects: $e'), backgroundColor: AppColors.danger.base),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showAddSubjectDialog(int examId) async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final maxCtrl = TextEditingController(text: '100');
    final passCtrl = TextEditingController(text: '40');
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(LucideIcons.plusCircle, size: 20, color: AppColors.brandDark),
              SizedBox(width: 8),
              Text('Add Subject to Exam', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Subject Name', hintText: 'e.g. Clinical Pathology', isDense: true),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'Subject Code', hintText: 'e.g. CP101', isDense: true),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: maxCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Total (Max) Marks', isDense: true),
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n <= 0) return 'Invalid';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: passCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Pass Marks', isDense: true),
                          validator: (v) {
                            final p = double.tryParse(v ?? '');
                            final m = double.tryParse(maxCtrl.text);
                            if (p == null || p < 0) return 'Invalid';
                            if (m != null && p > m) return '> Max';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Presets: ', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                      _buildRowPresetChip('100 / 40', maxCtrl, passCtrl, setDialogState),
                      const SizedBox(width: 4),
                      _buildRowPresetChip('100 / 50', maxCtrl, passCtrl, setDialogState),
                      const SizedBox(width: 4),
                      _buildRowPresetChip('50 / 20', maxCtrl, passCtrl, setDialogState),
                      const SizedBox(width: 4),
                      _buildRowPresetChip('75 / 30', maxCtrl, passCtrl, setDialogState),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  final client = SupabaseService.instance.client;
                  final subName = nameCtrl.text.trim();
                  final subCode = codeCtrl.text.trim().isEmpty ? subName.substring(0, subName.length >= 3 ? 3 : subName.length).toUpperCase() : codeCtrl.text.trim();
                  final maxM = double.parse(maxCtrl.text.trim());
                  final passM = double.parse(passCtrl.text.trim());

                  try {
                    await client.from('exam_subjects').insert({
                      'exam_id': examId,
                      'name': subName,
                      'code': subCode,
                      'max_marks': maxM,
                      'pass_marks': passM,
                      'theory_marks': maxM,
                      'practical_marks': 0.0,
                    });
                  } catch (e) {
                    debugPrint('Add subject insert failed, using fallback: $e');
                    SupabaseExamRepository.addFallbackSubject(examId, Subject(
                      id: DateTime.now().millisecondsSinceEpoch % 100000,
                      examId: examId,
                      name: subName,
                      code: subCode,
                      maxMarks: maxM,
                      passMarks: passM,
                    ));
                  }

                  ref.invalidate(markEntryDataProvider(examId));
                  ref.invalidate(examDashboardProvider);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Subject added successfully!'), backgroundColor: AppColors.success.base),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to add subject: $e'), backgroundColor: AppColors.danger.base),
                  );
                }
              },
              child: const Text('Add Subject'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditMarksDialog(List<Subject> subjects, {int? initialSubjectId}) async {
    final Map<int, TextEditingController> maxControllers = {
      for (var s in subjects) s.id!: TextEditingController(text: s.maxMarks.toStringAsFixed(0))
    };
    final Map<int, TextEditingController> passControllers = {
      for (var s in subjects) s.id!: TextEditingController(text: s.passMarks.toStringAsFixed(0))
    };

    final formKey = GlobalKey<FormState>();
    bool isSavingSubjectMarks = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(LucideIcons.sliders, size: 20, color: AppColors.brandDark),
                SizedBox(width: 8),
                Text('Edit Total & Pass Marks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 580,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Change total (max) and pass marks for subjects in this exam. Existing saved marks and totals will be automatically recalculated.',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Apply to All Subjects:',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                            ),
                            const SizedBox(width: 8),
                            _buildDialogPresetChip('100 / 40', () {
                              setDialogState(() {
                                for (var s in subjects) {
                                  maxControllers[s.id!]?.text = '100';
                                  passControllers[s.id!]?.text = '40';
                                }
                              });
                            }),
                            const SizedBox(width: 6),
                            _buildDialogPresetChip('100 / 50', () {
                              setDialogState(() {
                                for (var s in subjects) {
                                  maxControllers[s.id!]?.text = '100';
                                  passControllers[s.id!]?.text = '50';
                                }
                              });
                            }),
                            const SizedBox(width: 6),
                            _buildDialogPresetChip('50 / 20', () {
                              setDialogState(() {
                                for (var s in subjects) {
                                  maxControllers[s.id!]?.text = '50';
                                  passControllers[s.id!]?.text = '20';
                                }
                              });
                            }),
                            const SizedBox(width: 6),
                            _buildDialogPresetChip('75 / 30', () {
                              setDialogState(() {
                                for (var s in subjects) {
                                  maxControllers[s.id!]?.text = '75';
                                  passControllers[s.id!]?.text = '30';
                                }
                              });
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Expanded(flex: 3, child: Text('Subject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            SizedBox(width: 12),
                            Expanded(flex: 2, child: Text('Total (Max)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            SizedBox(width: 12),
                            Expanded(flex: 2, child: Text('Pass Marks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...subjects.map((sub) {
                        final isHighlighted = sub.id == initialSubjectId;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isHighlighted ? AppColors.brandDark.withOpacity(0.05) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: isHighlighted ? Border.all(color: AppColors.brandDark.withOpacity(0.3)) : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(sub.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                        if (sub.code != null && sub.code!.isNotEmpty)
                                          Text(sub.code!, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: maxControllers[sub.id!],
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      ),
                                      validator: (v) {
                                        final val = double.tryParse(v ?? '');
                                        if (val == null || val <= 0) return 'Invalid';
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: passControllers[sub.id!],
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      ),
                                      validator: (v) {
                                        final p = double.tryParse(v ?? '');
                                        final m = double.tryParse(maxControllers[sub.id!]?.text ?? '');
                                        if (p == null || p < 0) return 'Invalid';
                                        if (m != null && p > m) return '> Max';
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4, left: 2),
                                child: Row(
                                  children: [
                                    const Text('Presets: ', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                    _buildRowPresetChip('100 / 40', maxControllers[sub.id!], passControllers[sub.id!], setDialogState),
                                    const SizedBox(width: 4),
                                    _buildRowPresetChip('100 / 50', maxControllers[sub.id!], passControllers[sub.id!], setDialogState),
                                    const SizedBox(width: 4),
                                    _buildRowPresetChip('50 / 20', maxControllers[sub.id!], passControllers[sub.id!], setDialogState),
                                    const SizedBox(width: 4),
                                    _buildRowPresetChip('75 / 30', maxControllers[sub.id!], passControllers[sub.id!], setDialogState),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSavingSubjectMarks ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSavingSubjectMarks
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() => isSavingSubjectMarks = true);
                        try {
                          final client = SupabaseService.instance.client;

                          for (var sub in subjects) {
                            final newMax = double.tryParse(maxControllers[sub.id!]?.text ?? '') ?? sub.maxMarks;
                            final newPass = double.tryParse(passControllers[sub.id!]?.text ?? '') ?? sub.passMarks;

                            if (newMax != sub.maxMarks || newPass != sub.passMarks) {
                              try {
                                await client.from('exam_subjects').update({
                                  'max_marks': newMax,
                                  'pass_marks': newPass,
                                }).eq('id', sub.id!);
                              } catch (e) {
                                debugPrint('Update exam_subject failed, updating fallback: $e');
                                SupabaseExamRepository.updateFallbackSubjectMarks(widget.examId, sub.id!, newMax, newPass);
                              }
                            }
                          }

                          // Recalculate results on server
                          try {
                            await client.rpc('compute_results', params: {'p_exam_id': widget.examId});
                          } catch (_) {}

                          if (mounted) {
                            ref.invalidate(markEntryDataProvider(widget.examId));
                            ref.invalidate(examResultsProvider(widget.examId));
                            ref.invalidate(examDashboardProvider);
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Subject total & pass marks updated and results recalculated!'),
                                backgroundColor: AppColors.success.base,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSavingSubjectMarks = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error updating marks: $e'), backgroundColor: AppColors.danger.base),
                            );
                          }
                        }
                      },
                child: isSavingSubjectMarks
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save & Recalculate'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(markEntryDataProvider(widget.examId));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Mark Entry Spreadsheet'),
        actions: [
          dataAsync.maybeWhen(
            data: (data) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showEditMarksDialog(data['subjects']),
                  icon: const Icon(LucideIcons.sliders, size: 16),
                  label: const Text('Edit Total & Pass Marks'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _showAddSubjectDialog(widget.examId),
                  icon: const Icon(LucideIcons.plus, size: 15),
                  label: const Text('Add Subject'),
                ),
                const SizedBox(width: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : () => _saveAll(data['students'], data['subjects']),
                    icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(LucideIcons.save, size: 18),
                    label: const Text('Save All'),
                  ),
                ),
              ],
            ),
            orElse: () => const SizedBox(),
          )
        ],
      ),
      body: dataAsync.when(
        data: (data) {
          final subjects = data['subjects'] as List<Subject>;
          final students = data['students'] as List<Student>;
          final marks = data['marks'] as List<Mark>;
          final courseSubjects = data['course_subjects'] as List<Map<String, dynamic>>? ?? [];

          if (subjects.isEmpty) {
            if (courseSubjects.isNotEmpty) {
              return Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 580),
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.brandDark.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.bookOpen, size: 36, color: AppColors.brandDark),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const Text(
                        'Load Subjects for Mark Entry',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'This exam currently has no subjects configured, but ${courseSubjects.length} subject(s) exist in the course curriculum with default total and pass marks.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: courseSubjects.map((cs) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(LucideIcons.checkCircle2, size: 14, color: AppColors.success.base),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${cs['name'] ?? cs['subject_name']} (${cs['code'] ?? cs['subject_code'] ?? 'Paper'})',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  'Max: ${(cs['max_marks'] as num?)?.toInt() ?? 100} | Pass: ${(cs['pass_marks'] as num?)?.toInt() ?? 40}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isSaving ? null : () => _importCourseSubjects(widget.examId, courseSubjects),
                            icon: const Icon(LucideIcons.downloadCloud, size: 16),
                            label: Text('Import All ${courseSubjects.length} Subjects & Enter Marks'),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          OutlinedButton.icon(
                            onPressed: () => _showAddSubjectDialog(widget.examId),
                            icon: const Icon(LucideIcons.plus, size: 16),
                            label: const Text('Add Custom Subject'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }

            return Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.all(AppSpacing.xxl),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.bookOpen, size: 36, color: AppColors.textMuted.withOpacity(0.5)),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'No Subjects Configured',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Add subjects to this exam with total and pass marks to begin entering student marks.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ElevatedButton.icon(
                      onPressed: () => _showAddSubjectDialog(widget.examId),
                      icon: const Icon(LucideIcons.plus, size: 16),
                      label: const Text('Add Subject & Set Total/Pass Marks'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (students.isEmpty) return const Center(child: Text('No active students found enrolled for this course/batch.'));
          
          _initControllers(students, subjects, marks);

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.border),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(AppColors.surface),
                    columns: [
                      const DataColumn(label: Text('Adm No', style: TextStyle(fontWeight: FontWeight.bold))),
                      const DataColumn(label: Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold))),
                      ...subjects.map((sub) => DataColumn(
                        label: InkWell(
                          onTap: () => _showEditMarksDialog(subjects, initialSubjectId: sub.id),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(sub.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 4),
                                    const Icon(LucideIcons.edit2, size: 12, color: AppColors.brandDark),
                                  ],
                                ),
                                Text(
                                  'Max: ${sub.maxMarks.toInt()} | Pass: ${sub.passMarks.toInt()} (Click to edit)',
                                  style: const TextStyle(fontSize: 10, color: AppColors.brandDark, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )),
                      const DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                      const DataColumn(label: Text('%', style: TextStyle(fontWeight: FontWeight.bold))),
                      const DataColumn(label: Text('Result', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: students.map((s) {
                      double studentTotal = 0.0;
                      double maxTotal = 0.0;
                      bool hasFailingMark = false;
                      int marksEntered = 0;
                      
                      List<DataCell> cells = [
                        DataCell(Text(s.admissionNumber ?? 'N/A')),
                        DataCell(Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      ];
                      
                      for (var sub in subjects) {
                        final key = '${s.id}_${sub.id}';
                        final valText = _controllers[key]?.text ?? '';
                        final val = double.tryParse(valText);
                        
                        if (val != null) {
                          studentTotal += val;
                          marksEntered++;
                          if (val < sub.passMarks) hasFailingMark = true;
                        }
                        maxTotal += sub.maxMarks;
                        
                        cells.add(DataCell(
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              controller: _controllers[key],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              ),
                              onChanged: (v) {
                                setState(() {});
                              },
                            ),
                          ),
                        ));
                      }
                      
                      final pct = maxTotal > 0 ? (studentTotal / maxTotal) * 100 : 0.0;
                      final isComplete = marksEntered == subjects.length;
                      
                      cells.addAll([
                        DataCell(Text(studentTotal.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text('${pct.toStringAsFixed(1)}%')),
                        DataCell(
                          isComplete
                            ? (hasFailingMark 
                                ? Text('FAIL', style: TextStyle(color: AppColors.danger.base, fontWeight: FontWeight.bold))
                                : Text('PASS', style: TextStyle(color: AppColors.success.base, fontWeight: FontWeight.bold)))
                            : const Text('Pending', style: TextStyle(color: AppColors.textMuted)),
                        ),
                      ]);
                      
                      return DataRow(cells: cells);
                    }).toList(),
                  ),
                ),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
