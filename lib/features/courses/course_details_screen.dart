import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/course.dart';
import '../../core/models/course_subject.dart';
import '../../core/models/student.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_data_table.dart';
import '../../shared/widgets/course_chip.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/status_badge.dart';
import '../students/add_student_screen.dart';
import '../students/student_profile_screen.dart';
import '../students/student_provider.dart';
import 'add_course_dialog.dart';
import 'course_provider.dart';

class CourseDetailsScreen extends ConsumerStatefulWidget {
  final Course course;

  const CourseDetailsScreen({super.key, required this.course});

  @override
  ConsumerState<CourseDetailsScreen> createState() => _CourseDetailsScreenState();
}

class _CourseDetailsScreenState extends ConsumerState<CourseDetailsScreen> {
  late Course _course;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _course = widget.course;
  }

  void _refreshCourse() async {
    final courses = await ref.read(courseRepositoryProvider).getCourses();
    final updated = courses.where((c) => c.id == _course.id).toList();
    if (updated.isNotEmpty && mounted) {
      setState(() {
        _course = updated.first;
      });
    }
  }

  void _confirmDeleteCourse() async {
    int studentCount = 0;
    if (_course.id != null) {
      try {
        studentCount = await ref.read(studentRepositoryProvider).getStudentsCount(courseId: _course.id);
      } catch (_) {
        studentCount = 0;
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: AppColors.danger.base, size: 22),
            const SizedBox(width: 10),
            const Text('Delete Course?'),
          ],
        ),
        content: Text(
          studentCount > 0
              ? 'Course "${_course.name}" currently has $studentCount active student(s) enrolled.\n\nDeleting this course will remove it from the active courses catalog. Are you sure you want to proceed?'
              : 'Are you sure you want to delete course "${_course.name}"?\n\nThis will remove it from the active courses catalog.',
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
              if (_course.id != null) {
                await ref.read(courseRepositoryProvider).deleteCourse(_course.id!);
                ref.invalidate(coursesProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Course "${_course.name}" deleted successfully.')),
                  );
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Delete Course'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final studentsAsync = _course.id != null
        ? ref.watch(courseStudentsProvider(_course.id!))
        : const AsyncValue.data(<Student>[]);
    final subjectsAsync = _course.id != null
        ? ref.watch(courseSubjectsProvider(_course.id!))
        : const AsyncValue.data(<CourseSubject>[]);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_course.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        actions: isMobile
            ? [
                IconButton(
                  tooltip: 'Edit Course',
                  icon: const Icon(LucideIcons.edit3, size: 18),
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (context) => AddCourseDialog(existingCourse: _course),
                    );
                    if (_course.id != null) {
                      ref.invalidate(courseSubjectsProvider(_course.id!));
                    }
                    _refreshCourse();
                  },
                ),
                IconButton(
                  tooltip: 'Delete Course',
                  icon: Icon(LucideIcons.trash2, size: 18, color: AppColors.danger.base),
                  onPressed: _confirmDeleteCourse,
                ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await AddStudentPanel.show(context, courseId: _course.id);
                      if (_course.id != null) {
                        ref.invalidate(courseStudentsProvider(_course.id!));
                        ref.invalidate(studentsProvider);
                      }
                    },
                    icon: const Icon(LucideIcons.userPlus, size: 15),
                    label: const Text('Admit', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                  ),
                ),
              ]
            : [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await showDialog(
                        context: context,
                        builder: (context) => AddCourseDialog(existingCourse: _course),
                      );
                      if (_course.id != null) {
                        ref.invalidate(courseSubjectsProvider(_course.id!));
                      }
                      _refreshCourse();
                    },
                    icon: const Icon(LucideIcons.edit3, size: 16),
                    label: const Text('Edit Course'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: OutlinedButton.icon(
                    onPressed: _confirmDeleteCourse,
                    icon: Icon(LucideIcons.trash2, size: 15, color: AppColors.danger.base),
                    label: Text('Delete Course', style: TextStyle(color: AppColors.danger.base, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.danger.base.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xl),
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await AddStudentPanel.show(context, courseId: _course.id);
                      if (_course.id != null) {
                        ref.invalidate(courseStudentsProvider(_course.id!));
                        ref.invalidate(studentsProvider);
                      }
                    },
                    icon: const Icon(LucideIcons.userPlus, size: 16),
                    label: const Text('Admit Student'),
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
                // Hero Header Card
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: Container(
                    padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.courses.tint,
                                borderRadius: BorderRadius.circular(AppRadius.card),
                                border: Border.all(color: AppColors.courses.base.withOpacity(0.3)),
                              ),
                              child: Icon(LucideIcons.bookOpen, color: AppColors.courses.dark, size: 30),
                            ),
                            const SizedBox(width: AppSpacing.xl),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CourseChip(courseName: _course.code, courseCode: null),
                                      const SizedBox(width: AppSpacing.md),
                                      StatusBadge(text: _course.status.toUpperCase(), status: BadgeStatus.success),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    _course.name,
                                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textStrong,
                                        ),
                                  ),
                                  if (_course.description != null && _course.description!.isNotEmpty) ...[
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      _course.description!,
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        const Divider(height: 1),
                        const SizedBox(height: AppSpacing.lg),
                        // Quick Metric Stats (Responsive)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final admittedStudentsText = studentsAsync.maybeWhen(
                              data: (students) => '${students.length} Students',
                              orElse: () => '...',
                            );
                            final subjectsText = subjectsAsync.maybeWhen(
                              data: (subs) => '${subs.length} Subjects',
                              orElse: () => '...',
                            );

                            final metricItems = [
                              (
                                icon: LucideIcons.clock,
                                label: 'Duration',
                                value: _course.duration?.isNotEmpty == true ? _course.duration! : 'Not specified',
                              ),
                              (
                                icon: LucideIcons.indianRupee,
                                label: 'Total Fee',
                                value: '₹${_course.totalFee.toStringAsFixed(0)}',
                              ),
                              (
                                icon: LucideIcons.users,
                                label: 'Admitted Students',
                                value: admittedStudentsText,
                              ),
                              (
                                icon: LucideIcons.layers,
                                label: 'Program Code',
                                value: _course.code,
                              ),
                              (
                                icon: LucideIcons.bookOpen,
                                label: 'Subjects',
                                value: subjectsText,
                              ),
                            ];

                            if (constraints.maxWidth < 750) {
                              // Mobile / Tablet Clean 2-Column Responsive Cards
                              return Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: metricItems.map((m) {
                                  final cardWidth = (constraints.maxWidth - 10) / 2;
                                  return SizedBox(
                                    width: cardWidth > 140 ? cardWidth : constraints.maxWidth,
                                    child: _buildMetricCard(icon: m.icon, label: m.label, value: m.value),
                                  );
                                }).toList(),
                              );
                            }

                            // Desktop Horizontal Row with Dividers
                            return Row(
                              children: [
                                for (int i = 0; i < metricItems.length; i++) ...[
                                  if (i > 0) _buildDivider(),
                                  _buildMetricItem(
                                    icon: metricItems[i].icon,
                                    label: metricItems[i].label,
                                    value: metricItems[i].value,
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        subjectsAsync.maybeWhen(
                          data: (subs) {
                            if (subs.isEmpty) return const SizedBox();

                            if (_course.isSingle) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: AppSpacing.lg),
                                  const Divider(height: 1),
                                  const SizedBox(height: AppSpacing.md),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Curriculum Subjects: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textMuted)),
                                      Expanded(
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: subs.map((s) => Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: AppColors.surface,
                                              border: Border.all(color: AppColors.border),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${s.subjectName} (Max: ${s.maxMarks.toInt()}, Pass: ${s.passMarks.toInt()})',
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textStrong),
                                            ),
                                          )).toList(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }

                            final periods = <int?, List<CourseSubject>>{};
                            for (final s in subs) {
                              periods.putIfAbsent(s.periodNo, () => []).add(s);
                            }
                            final sortedKeys = periods.keys.toList()
                              ..sort((a, b) => (a ?? 9999).compareTo(b ?? 9999));

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: AppSpacing.lg),
                                const Divider(height: 1),
                                const SizedBox(height: AppSpacing.md),
                                for (final p in sortedKeys) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: p == null ? const Color(0xFFFEF2F2) : AppColors.brandDark.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: p == null ? const Color(0xFFFCA5A5) : AppColors.border),
                                          ),
                                          child: Text(
                                            p == null ? 'Unassigned:' : '${_course.periodName(p)}:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              color: p == null ? const Color(0xFFDC2626) : AppColors.brandDark,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: periods[p]!.map((s) => Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.surface,
                                                border: Border.all(color: AppColors.border),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '${s.subjectName} (${s.maxMarks.toInt()}/${s.passMarks.toInt()})',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textStrong),
                                              ),
                                            )).toList(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                          orElse: () => const SizedBox(),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // Admitted Students Section
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        // Toolbar
                        Padding(
                          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
                          child: isMobile
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Admitted Students',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        studentsAsync.maybeWhen(
                                          data: (students) => Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.brandDark.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              '${students.length}',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.brandDark),
                                            ),
                                          ),
                                          orElse: () => const SizedBox.shrink(),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    SearchField(
                                      hint: 'Search by name, admission no...',
                                      onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    studentsAsync.maybeWhen(
                                      data: (students) => Row(
                                        children: [
                                          const Text(
                                            'Admitted Students',
                                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.brandDark.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              '${students.length}',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.brandDark),
                                            ),
                                          ),
                                        ],
                                      ),
                                      orElse: () => const Text(
                                        'Admitted Students',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                                      ),
                                    ),
                                    const Spacer(),
                                    SizedBox(
                                      width: 340,
                                      child: SearchField(
                                        hint: 'Search by name, admission no, or phone...',
                                        onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                                      ),
                                    ),
                                  ],
                                ),
                        ),

                        const Divider(height: 1),

                        // Students Table
                        Expanded(
                          child: studentsAsync.when(
                            data: (students) {
                              final filtered = students.where((s) {
                                if (_searchQuery.isEmpty) return true;
                                final nameMatch = s.name.toLowerCase().contains(_searchQuery);
                                final admMatch = (s.admissionNumber ?? '').toLowerCase().contains(_searchQuery);
                                final regMatch = (s.registrationNumber ?? '').toLowerCase().contains(_searchQuery);
                                final phoneMatch = (s.phone ?? '').toLowerCase().contains(_searchQuery);
                                return nameMatch || admMatch || regMatch || phoneMatch;
                              }).toList();

                              if (filtered.isEmpty) {
                                return EmptyState(
                                  title: _searchQuery.isEmpty ? 'No Students Admitted Yet' : 'No Students Found',
                                  message: _searchQuery.isEmpty
                                      ? 'There are currently no students admitted to ${_course.name}.'
                                      : 'No students match "$_searchQuery" in this course.',
                                  icon: LucideIcons.users,
                                  action: _searchQuery.isEmpty
                                      ? ElevatedButton.icon(
                                          onPressed: () async {
                                            await AddStudentPanel.show(context, courseId: _course.id);
                                            if (_course.id != null) {
                                              ref.invalidate(courseStudentsProvider(_course.id!));
                                              ref.invalidate(studentsProvider);
                                            }
                                          },
                                          icon: const Icon(LucideIcons.userPlus, size: 16),
                                          label: const Text('Admit First Student'),
                                        )
                                      : null,
                                );
                              }

                              return AppDataTable<Student>(
                                columns: const ['Adm. No', 'Student', 'University Reg No', 'DOB', 'Status', 'Actions'],
                                flexes: const [2, 4, 3, 2, 2, 2],
                                data: filtered,
                                cardBuilder: (context, s) {
                                  return InkWell(
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => StudentProfileScreen(student: s)),
                                      );
                                      if (_course.id != null) {
                                        ref.invalidate(courseStudentsProvider(_course.id!));
                                        ref.invalidate(studentsProvider);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(AppRadius.card),
                                    child: Container(
                                      padding: const EdgeInsets.all(AppSpacing.md),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(AppRadius.card),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              AppAvatar(name: s.name, radius: 18),
                                              const SizedBox(width: AppSpacing.md),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      s.name,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textStrong),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      s.admissionNumber != null ? 'Adm: ${s.admissionNumber}' : 'No Adm No',
                                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              StatusBadge(text: s.status.toUpperCase(), status: BadgeStatus.success),
                                            ],
                                          ),
                                          if (s.phone != null && s.phone!.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(LucideIcons.phone, size: 14, color: AppColors.textMuted),
                                                const SizedBox(width: 6),
                                                Text(s.phone!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                                const Spacer(),
                                                const Text('View Profile →', style: TextStyle(fontSize: 12, color: AppColors.brandDark, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                rowBuilder: (context, s) {
                                  return InkWell(
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => StudentProfileScreen(student: s)),
                                      );
                                      if (_course.id != null) {
                                        ref.invalidate(courseStudentsProvider(_course.id!));
                                        ref.invalidate(studentsProvider);
                                      }
                                    },
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            s.admissionNumber ?? 'N/A',
                                            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textStrong),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 4,
                                          child: Row(
                                            children: [
                                              AppAvatar(name: s.name, radius: 18),
                                              const SizedBox(width: AppSpacing.md),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      s.name,
                                                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textStrong),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    Text(
                                                      s.phone ?? 'No phone',
                                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            s.registrationNumber?.isNotEmpty == true ? s.registrationNumber! : 'Pending',
                                            style: const TextStyle(color: AppColors.textBody),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            s.dob?.isNotEmpty == true ? s.dob! : 'Not Provided',
                                            style: TextStyle(
                                              color: s.dob?.isNotEmpty == true ? AppColors.textBody : AppColors.textMuted,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: StatusBadge(text: s.status.toUpperCase(), status: BadgeStatus.success),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton(
                                              onPressed: () async {
                                                await Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (_) => StudentProfileScreen(student: s)),
                                                );
                                                if (_course.id != null) {
                                                  ref.invalidate(courseStudentsProvider(_course.id!));
                                                  ref.invalidate(studentsProvider);
                                                }
                                              },
                                              child: const Text('View Profile'),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                            loading: () => const Center(child: CircularProgressIndicator()),
                            error: (e, _) => Center(child: Text('Error loading students: $e')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, size: 18, color: AppColors.brandDark),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: AppColors.textStrong, fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({required IconData icon, required String label, required String value}) {
    return Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, size: 18, color: AppColors.brandDark),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: AppColors.textStrong, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 32,
      width: 1,
      color: AppColors.border,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    );
  }
}
