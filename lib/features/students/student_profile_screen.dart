import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'student_documents_tab.dart';
import 'student_results_tab.dart';
import 'student_fees_tab.dart';
import 'student_account_tab.dart';
import '../../shared/widgets/student_hero_photo.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/models/student.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/status_badge.dart';
import 'add_student_screen.dart';
import 'student_provider.dart';
import '../courses/course_provider.dart';
import '../../core/models/batch.dart';
import '../../shared/widgets/section_card.dart';

class StudentProfileScreen extends ConsumerStatefulWidget {
  final Student student;

  const StudentProfileScreen({super.key, required this.student});

  @override
  ConsumerState<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends ConsumerState<StudentProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Student _student;

  @override
  void initState() {
    super.initState();
    _student = widget.student;
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshStudent() async {
    ref.invalidate(allBatchesProvider);
    ref.invalidate(batchesMapProvider);
    if (_student.id != null) {
      final updated = await ref.read(studentRepositoryProvider).getStudentById(_student.id!);
      if (updated != null && mounted) {
        setState(() {
          _student = updated;
        });
      }
    }
  }

  void _confirmDeleteStudent() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: AppColors.danger.base, size: 22),
            const SizedBox(width: 10),
            const Text('Delete Student?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${_student.name}" (Admission No: ${_student.admissionNumber ?? "N/A"})?\n\nThis will remove the student from active lists, fees, and exams.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger.base,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (_student.id != null) {
                await ref.read(studentRepositoryProvider).deleteStudent(_student.id!);
                ref.invalidate(studentsProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Student "${_student.name}" deleted successfully.')),
                  );
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Delete Student'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMarkCompletedDialog() async {
    DateTime selectedDate = DateTime.now();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(LucideIcons.checkCircle, color: Colors.teal, size: 22),
              const SizedBox(width: 10),
              const Text('Mark Student as Completed'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to mark "${_student.name}" as COMPLETED?\n\n'
                '• The student will keep read-only portal access to results, fee receipts, and attendance.\n'
                '• Attendance marking and attendance alerts will stop for this student.\n',
                style: const TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 10),
              const Text('Completion Date *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Icon(LucideIcons.calendar, size: 16, color: AppColors.brand),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[700], foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm Completion'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && _student.id != null) {
      try {
        await ref.read(studentRepositoryProvider).completeStudent(
          _student.id!,
          completedOn: selectedDate,
        );
        await _refreshStudent();
        ref.invalidate(studentsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Student "${_student.name}" marked as completed.'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to complete student: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showReopenStudentDialog() async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(LucideIcons.rotateCcw, color: Colors.orange, size: 22),
            const SizedBox(width: 10),
            const Text('Reopen Student'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to reopen "${_student.name}"?\n\n'
                '• The student will be restored to ACTIVE status.\n'
                '• Full active portal access and attendance tracking will resume.\n',
                style: const TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 10),
              const Text('Reason for Reopening *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              TextFormField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Enter justification (e.g. Course resumption, re-admission)...',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Reason is required';
                  if (val.trim().length < 5) return 'Min 5 characters required';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Reopen Student'),
          ),
        ],
      ),
    );

    if (confirmed == true && _student.id != null) {
      try {
        await ref.read(studentRepositoryProvider).reopenStudent(
          _student.id!,
          reason: reasonController.text.trim(),
        );
        await _refreshStudent();
        ref.invalidate(studentsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Student "${_student.name}" reopened successfully.'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to reopen student: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesProvider);
    final batchesAsync = ref.watch(allBatchesProvider);
    final isMobile = MediaQuery.of(context).size.width < 800;

    final courseName = coursesAsync.maybeWhen(
      data: (courses) {
        final match = courses.where((c) => c.id == _student.courseId).toList();
        if (match.isNotEmpty) return match.first.name;
        return _student.courseId != null ? 'Course #${_student.courseId}' : 'No Course Assigned';
      },
      orElse: () => _student.courseId != null ? 'Course #${_student.courseId}' : 'N/A',
    );

    final batch = batchesAsync.maybeWhen(
      data: (batches) {
        final match = batches.where((b) => b.id == _student.batchId).toList();
        return match.isNotEmpty ? match.first : null;
      },
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Student Profile', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: OutlinedButton.icon(
              onPressed: _confirmDeleteStudent,
              icon: Icon(LucideIcons.trash2, size: 15, color: AppColors.danger.base),
              label: Text('Delete Student', style: TextStyle(color: AppColors.danger.base, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.danger.base.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Padding(
            padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero Card
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? AppSpacing.lg : AppSpacing.xxl),
                    child: isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  StudentHeroPhoto(
                                    student: _student,
                                    onChangePhoto: () async {
                                      await AddStudentPanel.show(context, student: _student);
                                      await _refreshStudent();
                                    },
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _student.name,
                                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                            color: AppColors.textStrong,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: AppSpacing.sm,
                                          runSpacing: AppSpacing.xs,
                                          children: [
                                            StatusBadge(
                                              text: _student.status == 'completed' ? 'COMPLETED' : _student.status.toUpperCase(),
                                              status: _student.status == 'completed'
                                                  ? BadgeStatus.info
                                                  : _student.status == 'discontinued'
                                                      ? BadgeStatus.neutral
                                                      : _student.status == 'tc_issued'
                                                          ? BadgeStatus.warning
                                                          : BadgeStatus.success,
                                            ),
                                            if (batch != null)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: AppColors.brand.withOpacity(0.08),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: AppColors.brand.withOpacity(0.25)),
                                                ),
                                                child: Text(
                                                  'Sem ${batch.currentSemester} (Yr ${batch.currentYear})',
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.brand),
                                                ),
                                              ),
                                            if (_student.status == 'completed' && _student.completedOn != null)
                                              Text(
                                                '(${_student.completedOn})',
                                                style: const TextStyle(color: Colors.purple, fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        Text(
                                          '${_student.admissionNumber ?? 'N/A'} • $courseName',
                                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                                        ),
                                        if (_student.phone != null && _student.phone!.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(LucideIcons.phone, size: 13, color: AppColors.textMuted),
                                              const SizedBox(width: 4),
                                              Text(_student.phone!, style: const TextStyle(color: AppColors.textBody, fontSize: 12)),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              const Divider(height: 1),
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (_student.status == 'active')
                                    ElevatedButton.icon(
                                      onPressed: _showMarkCompletedDialog,
                                      icon: const Icon(LucideIcons.checkCircle, size: 14),
                                      label: const Text('Mark Completed', style: TextStyle(fontSize: 12)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal[700],
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                    )
                                  else if (_student.status == 'completed')
                                    ElevatedButton.icon(
                                      onPressed: _showReopenStudentDialog,
                                      icon: const Icon(LucideIcons.rotateCcw, size: 14),
                                      label: const Text('Reopen Student', style: TextStyle(fontSize: 12)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange[800],
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                    ),
                                  OutlinedButton.icon(
                                    onPressed: () => _showAddSkillCourseDialog(),
                                    icon: const Icon(LucideIcons.sparkles, size: 14, color: Colors.purple),
                                    label: const Text('Add Skill Course', style: TextStyle(color: Colors.purple, fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: Colors.purple.withOpacity(0.4)),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await AddStudentPanel.show(context, student: _student);
                                      await _refreshStudent();
                                    },
                                    icon: const Icon(LucideIcons.edit3, size: 14),
                                    label: const Text('Edit Profile', style: TextStyle(fontSize: 12)),
                                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _confirmDeleteStudent,
                                    icon: Icon(LucideIcons.trash2, size: 14, color: AppColors.danger.base),
                                    label: Text('Delete', style: TextStyle(color: AppColors.danger.base, fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: AppColors.danger.base.withValues(alpha: 0.4)),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              StudentHeroPhoto(
                                student: _student,
                                onChangePhoto: () async {
                                  await AddStudentPanel.show(context, student: _student);
                                  await _refreshStudent();
                                },
                              ),
                              const SizedBox(width: AppSpacing.xxl),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: AppSpacing.md,
                                      runSpacing: AppSpacing.sm,
                                      children: [
                                        Text(_student.name, style: Theme.of(context).textTheme.displayMedium?.copyWith(color: AppColors.textStrong)),
                                        StatusBadge(
                                          text: _student.status == 'completed' ? 'COMPLETED' : _student.status.toUpperCase(),
                                          status: _student.status == 'completed'
                                              ? BadgeStatus.info
                                              : _student.status == 'discontinued'
                                                  ? BadgeStatus.neutral
                                                  : _student.status == 'tc_issued'
                                                      ? BadgeStatus.warning
                                                      : BadgeStatus.success,
                                        ),
                                        if (batch != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: AppColors.brand.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: AppColors.brand.withOpacity(0.25)),
                                            ),
                                            child: Text(
                                              'Semester ${batch.currentSemester} (Year ${batch.currentYear})',
                                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.brand),
                                            ),
                                          ),
                                        if (_student.status == 'completed' && _student.completedOn != null)
                                          Text(
                                            '(${_student.completedOn})',
                                            style: const TextStyle(color: Colors.purple, fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      '${_student.admissionNumber ?? 'N/A'} • $courseName • ${batch != null ? batch.batchName : 'No Batch'} • ${_student.gender ?? 'Male'}',
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    Row(
                                      children: [
                                        const Icon(LucideIcons.phone, size: 16, color: AppColors.textMuted),
                                        const SizedBox(width: AppSpacing.sm),
                                        Text(_student.phone ?? 'No phone provided', style: const TextStyle(color: AppColors.textBody)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (_student.status == 'active') ...[
                                    ElevatedButton.icon(
                                      onPressed: _showMarkCompletedDialog,
                                      icon: const Icon(LucideIcons.checkCircle, size: 14),
                                      label: const Text('Mark Completed', style: TextStyle(fontSize: 12.5)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal[700],
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                  ] else if (_student.status == 'completed') ...[
                                    ElevatedButton.icon(
                                      onPressed: _showReopenStudentDialog,
                                      icon: const Icon(LucideIcons.rotateCcw, size: 14),
                                      label: const Text('Reopen Student', style: TextStyle(fontSize: 12.5)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange[800],
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                  ],
                                  OutlinedButton.icon(
                                    onPressed: () => _showAddSkillCourseDialog(),
                                    icon: const Icon(LucideIcons.sparkles, size: 14, color: Colors.purple),
                                    label: const Text('Add Skill Course', style: TextStyle(color: Colors.purple, fontSize: 12.5)),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: Colors.purple.withOpacity(0.4)),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await AddStudentPanel.show(context, student: _student);
                                      await _refreshStudent();
                                    },
                                    icon: const Icon(LucideIcons.edit3, size: 14),
                                    label: const Text('Edit Profile', style: TextStyle(fontSize: 12.5)),
                                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  OutlinedButton.icon(
                                    onPressed: _confirmDeleteStudent,
                                    icon: Icon(LucideIcons.trash2, size: 14, color: AppColors.danger.base),
                                    label: Text('Delete', style: TextStyle(color: AppColors.danger.base, fontSize: 12.5)),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: AppColors.danger.base.withValues(alpha: 0.4)),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ),
                
                const SizedBox(height: AppSpacing.xl),
                
                // Tabs
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.brandDark,
                  unselectedLabelColor: AppColors.textMuted,
                  indicatorColor: AppColors.brand,
                  indicatorWeight: 3,
                  labelStyle: TextStyle(fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Fees'),
                    Tab(text: 'Documents'),
                    Tab(text: 'Results'),
                    Tab(text: 'Account'),
                  ],
                ),
                
                const SizedBox(height: AppSpacing.xl),
                
                // Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(courseName, batch),
                      StudentFeesTab(student: _student),
                      StudentDocumentsTab(
                        student: _student,
                        onUpdated: _refreshStudent,
                      ),
                      StudentResultsTab(student: _student),
                      StudentAccountTab(student: _student, onUpdated: _refreshStudent),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab(String courseName, Batch? batch) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    final personalCard = SectionCard(
      title: 'Personal Details',
      child: Column(
        children: [
          _buildDetailRow('Gender', _student.gender?.isNotEmpty == true ? _student.gender! : 'Male'),
          _buildDetailRow('Date of Birth', _student.dob?.isNotEmpty == true ? _student.dob! : 'Not Provided'),
          _buildDetailRow('Phone Number', _student.phone?.isNotEmpty == true ? _student.phone! : 'Not Provided'),
          _buildDetailRow('Email', _student.email?.isNotEmpty == true ? _student.email! : 'Not Provided'),
          _buildDetailRow('Address', _student.address?.isNotEmpty == true ? _student.address! : 'Not Provided'),
        ],
      ),
    );

    final academicCard = SectionCard(
      title: 'Academic Details',
      child: Column(
        children: [
          _buildDetailRow('Enrolled Course', courseName),
          _buildDetailRow('Batch', batch != null ? batch.batchName : 'No Batch Assigned'),
          _buildDetailRow('Current Semester', batch != null ? 'Semester ${batch.currentSemester}' : 'N/A'),
          _buildDetailRow('Academic Year', batch != null ? 'Year ${batch.currentYear}' : 'N/A'),
          _buildDetailRow('Admission No', _student.admissionNumber ?? 'N/A'),
          _buildDetailRow('University Reg No', _student.registrationNumber?.isNotEmpty == true ? _student.registrationNumber! : 'Pending'),
          _buildDetailRow('Admission Date', _student.admissionDate?.isNotEmpty == true ? _student.admissionDate! : 'Unknown'),
          _buildDetailRow('Status', _student.status.toUpperCase()),
        ],
      ),
    );

    return SingleChildScrollView(
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                personalCard,
                const SizedBox(height: AppSpacing.lg),
                academicCard,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: personalCard),
                const SizedBox(width: AppSpacing.xl),
                Expanded(child: academicCard),
              ],
            ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w500))),
          Expanded(flex: 3, child: Text(value, style: TextStyle(color: AppColors.textStrong))),
        ],
      ),
    );
  }

  void _showAddSkillCourseDialog() async {
    final courses = await ref.read(coursesProvider.future);
    final skillCourses = courses.where((c) => c.courseType == 'skill').toList();

    if (skillCourses.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No skill courses created yet. Create a course with type "Skill" first.')),
        );
      }
      return;
    }

    if (!mounted) return;

    int? selectedCourseId = skillCourses.first.id;
    int? selectedBatchId;
    final feeController = TextEditingController(text: skillCourses.first.totalFee.toStringAsFixed(0));
    List<Map<String, dynamic>> availableBatches = [];

    final client = ref.read(studentRepositoryProvider);
    final batchesRes = await ref.read(batchRepositoryProvider).getBatches(courseId: selectedCourseId);
    availableBatches = batchesRes.map((b) => {'id': b.id, 'name': b.batchName}).toList();
    if (availableBatches.isNotEmpty) {
      selectedBatchId = availableBatches.first['id'] as int;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(LucideIcons.sparkles, color: Colors.purple, size: 20),
                SizedBox(width: 8),
                Text('Enroll in Skill Course'),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select a skill certification course to add as the student\'s optional second course:'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    value: selectedCourseId,
                    decoration: const InputDecoration(labelText: 'Skill Course'),
                    items: skillCourses.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                    onChanged: (val) async {
                      if (val == null) return;
                      setDialogState(() {
                        selectedCourseId = val;
                        final match = skillCourses.where((c) => c.id == val).toList();
                        if (match.isNotEmpty) {
                          feeController.text = match.first.totalFee.toStringAsFixed(0);
                        }
                      });
                      final batchesRes = await ref.read(batchRepositoryProvider).getBatches(courseId: val);
                      setDialogState(() {
                        availableBatches = batchesRes.map((b) => {'id': b.id, 'name': b.batchName}).toList();
                        selectedBatchId = availableBatches.isNotEmpty ? availableBatches.first['id'] as int : null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (availableBatches.isNotEmpty) ...[
                    DropdownButtonFormField<int?>(
                      value: selectedBatchId,
                      decoration: const InputDecoration(labelText: 'Skill Course Batch'),
                      items: availableBatches.map((b) => DropdownMenuItem(value: b['id'] as int, child: Text(b['name'] as String))).toList(),
                      onChanged: (val) => setDialogState(() => selectedBatchId = val),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple.withOpacity(0.2)),
                      ),
                      child: const Row(
                        children: [
                          Icon(LucideIcons.info, size: 16, color: Colors.purple),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No batches found. A default batch will be created automatically upon enrollment.',
                              style: TextStyle(fontSize: 12, color: Colors.purple),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: feeController,
                    decoration: const InputDecoration(
                      labelText: 'Skill Course Fee (₹)',
                      prefixText: '₹ ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.purple),
                onPressed: () async {
                  if (selectedCourseId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a skill course first.')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    final feeAmount = double.tryParse(feeController.text.trim()) ?? 0.0;
                    final feePaise = (feeAmount * 100).toInt();

                    await client.addSkillCourse(
                      studentId: _student.id!,
                      courseId: selectedCourseId!,
                      batchId: selectedBatchId,
                      feePaise: feePaise > 0 ? feePaise : null,
                    );

                    await _refreshStudent();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Successfully added Skill Course enrollment!')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                    }
                  }
                },
                child: const Text('Enroll Student'),
              ),
            ],
          );
        },
      ),
    );
  }
}



