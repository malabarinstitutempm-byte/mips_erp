import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/course_chip.dart';
import 'course_provider.dart';
import 'add_course_dialog.dart';
import 'course_details_screen.dart';
import '../students/student_provider.dart';
import '../../core/models/course.dart';

class CoursesScreen extends ConsumerWidget {
  const CoursesScreen({super.key});

  void _confirmDeleteCourse(BuildContext context, WidgetRef ref, Course c) async {
    int studentCount = 0;
    if (c.id != null) {
      try {
        studentCount = await ref.read(studentRepositoryProvider).getStudentsCount(courseId: c.id);
      } catch (_) {
        studentCount = 0;
      }
    }

    if (!context.mounted) return;

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
              ? 'Course "${c.name}" currently has $studentCount active student(s) enrolled.\n\nDeleting this course will remove it from the active courses catalog. Are you sure you want to proceed?'
              : 'Are you sure you want to delete course "${c.name}"?\n\nThis will remove it from the active courses catalog.',
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
              if (c.id != null) {
                await ref.read(courseRepositoryProvider).deleteCourse(c.id!);
                ref.invalidate(coursesProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Course "${c.name}" deleted successfully.')),
                  );
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
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(coursesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Courses & Programs',
          subtitle: 'Manage curriculum, batches, and course parameters',
          actions: [
            IconButton(
              icon: const Icon(LucideIcons.refreshCw, size: 18),
              tooltip: 'Refresh courses',
              onPressed: () => ref.invalidate(coursesProvider),
            ),
            ElevatedButton.icon(
              onPressed: () => showDialog(context: context, builder: (context) => const AddCourseDialog()),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('Add Course'),
            ),
          ],
        ),
        Expanded(
          child: coursesAsync.when(
            data: (courses) {
              if (courses.isEmpty) {
                return SectionCard(
                  child: EmptyState(
                    title: 'No Courses Found',
                    message: 'Add your first course to begin enrollment.',
                    icon: LucideIcons.bookOpen,
                  ),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.all(AppSpacing.xs), // Account for shadow
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 420,
                  mainAxisExtent: 290,
                  crossAxisSpacing: AppSpacing.xl,
                  mainAxisSpacing: AppSpacing.xl,
                ),
                itemCount: courses.length,
                itemBuilder: (context, index) {
                  final c = courses[index];
                  
                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => CourseDetailsScreen(course: c)),
                      );
                    },
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.border),
                        boxShadow: const [
                          BoxShadow(color: Color(0x0A0F172A), offset: Offset(0, 1), blurRadius: 2)
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            constraints: const BoxConstraints(minHeight: 95),
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.courses.tint,
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppRadius.card), topRight: Radius.circular(AppRadius.card)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          CourseChip(courseName: c.code, courseCode: null),
                                          if (c.courseType == 'skill') ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.purple.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.purple.withOpacity(0.3)),
                                              ),
                                              child: const Text('SKILL', style: TextStyle(color: Colors.purple, fontSize: 9, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        c.name,
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          color: AppColors.courses.dark,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Edit Course',
                                  icon: Icon(LucideIcons.edit3, size: 16, color: AppColors.courses.dark),
                                  onPressed: () {
                                    showDialog(context: context, builder: (context) => AddCourseDialog(existingCourse: c));
                                  },
                                ),
                              ],
                            ),
                          ),
                          
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(LucideIcons.clock, size: 14, color: AppColors.textMuted),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text('Duration: ${c.duration}', style: TextStyle(color: AppColors.textBody, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Row(
                                  children: [
                                    Icon(LucideIcons.indianRupee, size: 14, color: AppColors.textMuted),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text('Total Fee: ₹${c.totalFee.toStringAsFixed(0)}', style: TextStyle(color: AppColors.textBody, fontSize: 13)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          const Spacer(),
                          const Divider(height: 1),
                          
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        showDialog(context: context, builder: (context) => AddCourseDialog(existingCourse: c));
                                      },
                                      icon: const Icon(LucideIcons.edit3, size: 14),
                                      label: const Text('Edit', style: TextStyle(fontSize: 12)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(LucideIcons.trash2, size: 15, color: AppColors.danger.base),
                                      tooltip: 'Delete Course',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _confirmDeleteCourse(context, ref, c),
                                    ),
                                  ],
                                ),
                                InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => CourseDetailsScreen(course: c)),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Row(
                                      children: [
                                        Text('Manage', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.brand, fontSize: 13)),
                                        SizedBox(width: 2),
                                        Icon(LucideIcons.chevronRight, size: 14, color: AppColors.brand),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => EmptyState(title: 'Error', message: e.toString(), icon: LucideIcons.alertCircle),
          ),
        ),
      ],
    );
  }
}
