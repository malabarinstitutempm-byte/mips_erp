import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/progress_bar.dart';
import '../../shared/widgets/course_chip.dart';

import 'exam_provider.dart';
import 'add_exam_dialog.dart';
import 'mark_entry_screen.dart';
import 'grading_scheme_manager.dart';
import '../results/results_screen.dart';

class ExamsScreen extends ConsumerWidget {
  const ExamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final examsAsync = ref.watch(examDashboardProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Examinations',
          subtitle: 'Manage term exams, mark entries, and publish results',
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => Dialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(LucideIcons.award, color: AppColors.brand, size: 22),
                                    SizedBox(width: 10),
                                    Text('Grade Percentage Rules', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(LucideIcons.x, size: 20),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            const Expanded(
                              child: SingleChildScrollView(
                                child: GradingSchemeManagerView(isEmbeddedInDialog: true),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
              icon: const Icon(LucideIcons.award, size: 17),
              label: const Text('Grade Percentages'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () {
                showDialog(context: context, builder: (context) => const AddExamDialog());
              },
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('Create Exam'),
            ),
          ],
        ),
        
        Expanded(
          child: examsAsync.when(
            data: (exams) {
              if (exams.isEmpty) {
                return SectionCard(
                  child: EmptyState(
                    title: 'No Exams Yet',
                    message: 'Create a new exam to start managing marks.',
                    icon: LucideIcons.checkSquare,
                  ),
                );
              }

              return SingleChildScrollView(
                child: Wrap(
                  spacing: AppSpacing.xl,
                  runSpacing: AppSpacing.xl,
                  children: [
                    ...exams.map((exam) => _buildExamCard(context, ref, exam)),
                  ],
                ),
              );
            },
            loading: () => Wrap(
              spacing: AppSpacing.xl,
              children: List.generate(3, (i) => const SkeletonLoader(width: 350, height: 250, borderRadius: AppRadius.card)),
            ),
            error: (e, st) => EmptyState(title: 'Error', message: e.toString(), icon: LucideIcons.alertCircle),
          ),
        ),
      ],
    );
  }

  Widget _buildExamCard(BuildContext context, WidgetRef ref, Map<String, dynamic> exam) {
    final isPublished = exam['status'] == 'Published';
    final int subjectsCount = exam['subjects'] as int? ?? 0;
    final int studentsCount = exam['students'] as int? ?? 0;
    final int marksEntered = exam['marks_entered'] as int? ?? 0;
    
    final expectedMarks = subjectsCount * studentsCount;
    final double progress = expectedMarks > 0 ? (marksEntered / expectedMarks).clamp(0.0, 1.0) : 0.0;
    final String? syncStatus = exam['sync_status'] as String?;
    
    return Container(
      width: 400,
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
          // Header
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ResultsScreen(
                    examId: exam['id'] as int,
                    examName: exam['name'].toString(),
                  ),
                ),
              );
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CourseChip(courseName: exam['course']?.toString() ?? 'N/A', courseCode: exam['code']?.toString() ?? 'N/A'),
                            if (exam['period_display'] != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Text(
                                  exam['period_display'].toString(),
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          exam['name'].toString(),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.textStrong),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${exam['batch'] ?? 'Batch'} • ${exam['period_display'] ?? 'General'} • $subjectsCount Subjects • $studentsCount Students',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusBadge(text: exam['status'].toString(), status: isPublished ? BadgeStatus.success : BadgeStatus.draft),
                      PopupMenuButton<String>(
                        icon: const Icon(LucideIcons.moreVertical, size: 16, color: AppColors.textMuted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onSelected: (val) async {
                          if (val == 'delete') {
                            if (isPublished) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cannot delete a published exam. Please unpublish the exam first.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Exam'),
                                content: Text('Are you sure you want to delete "${exam['name']}"?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger.base, foregroundColor: Colors.white),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              try {
                                await ref.read(examRepositoryProvider).deleteExam(exam['id'] as int);
                                ref.invalidate(examDashboardProvider);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Exam deleted successfully')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed to delete exam: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              }
                            }
                          }
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(LucideIcons.trash2, size: 16, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete Exam', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const Divider(height: 1),
          
          // Progress
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Mark Entry Progress', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    Text('${(progress * 100).toInt()}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.exams.base)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ProgressBar(progress: progress, color: progress == 1.0 ? AppColors.success.base : AppColors.exams.base),
              ],
            ),
          ),
          
          if (syncStatus != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
              color: AppColors.reports.tint.withValues(alpha: 0.5),
              child: Row(
                children: [
                  const Icon(LucideIcons.globe, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(syncStatus, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                ],
              ),
            ),
          
          const Divider(height: 1),
          
          // Actions
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => MarkEntryScreen(examId: exam['id'] as int)));
                    },
                    icon: const Icon(LucideIcons.edit3, size: 16),
                    label: const Text('Enter Marks'),
                  ),
                ),
                Container(width: 1, height: 24, color: AppColors.border),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ResultsScreen(
                            examId: exam['id'] as int,
                            examName: exam['name'].toString(),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(LucideIcons.award, size: 16),
                    label: const Text('Results Board'),
                  ),
                ),
                if (isPublished) ...[
                  Container(width: 1, height: 24, color: AppColors.border),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Unpublish Exam'),
                            content: const Text(
                              'Are you sure you want to unpublish this exam? '
                              'Results will no longer be visible on the student portal, and mark entry will be unlocked.',
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(c, true),
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger.base, foregroundColor: Colors.white),
                                child: const Text('Unpublish'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          if (!context.mounted) return;
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const AlertDialog(
                              content: Row(
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(width: 20),
                                  Text('Unpublishing exam...'),
                                ],
                              ),
                            ),
                          );

                          try {
                            await ref.read(examRepositoryProvider).unpublishExam(exam['id'] as int);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Exam unpublished. Mark entry is now unlocked.')),
                              );
                              ref.invalidate(examDashboardProvider);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to unpublish exam: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(LucideIcons.eyeOff, size: 16),
                      label: const Text('Unpublish'),
                    ),
                  ),
                ] else ...[
                  Container(width: 1, height: 24, color: AppColors.border),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: progress < 1.0 ? null : () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Publish Results'),
                            content: const Text(
                              'This will calculate student percentages, grades, and ranks, publish the results to the student portal, '
                              'and notify active students. Continue?',
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Publish'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          if (!context.mounted) return;
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const AlertDialog(
                              content: Row(
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(width: 20),
                                  Text('Calculating results & publishing to portal...'),
                                ],
                              ),
                            ),
                          );

                          try {
                            final notifCount = await ref.read(examRepositoryProvider).publishExam(exam['id'] as int);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Exam published successfully! $notifCount students notified.'),
                                  backgroundColor: AppColors.success.base,
                                ),
                              );
                              ref.invalidate(examDashboardProvider);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to publish results: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(LucideIcons.uploadCloud, size: 16),
                      label: const Text('Publish'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
