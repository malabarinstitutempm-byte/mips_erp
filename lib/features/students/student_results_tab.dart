import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/student.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/section_card.dart';

final studentResultsProvider = FutureProvider.family<List<Map<String, dynamic>>, int>((ref, studentId) async {
  try {
    final client = SupabaseService.instance.client;

    // 1. Get results with exam details
    final results = await client
        .from('results')
        .select('id, exam_id, total_marks, percentage, grade, status, rank, exams(id, name, exam_date, status)')
        .eq('student_id', studentId)
        .isFilter('deleted_at', null)
        .order('id', ascending: false);

    final List<Map<String, dynamic>> finalData = [];

    for (final r in results as List) {
      final exam = r['exams'] as Map<String, dynamic>?;
      final examId = r['exam_id'] as int;

      // 2. Get marks for this student and exam
      final marks = await client
          .from('marks')
          .select('id, marks_obtained, is_absent, exam_subjects(name, code, max_marks, pass_marks)')
          .eq('student_id', studentId)
          .eq('exam_id', examId)
          .isFilter('deleted_at', null);

      final marksList = (marks as List).map((m) {
        final sub = m['exam_subjects'] as Map<String, dynamic>?;
        final marksObt = m['marks_obtained'];
        final isAbsent = m['is_absent'] == true;
        final passMarks = (sub?['pass_marks'] as num?)?.toDouble() ?? 40.0;
        final isPass = !isAbsent && marksObt != null && ((marksObt as num).toDouble() >= passMarks);

        return {
          'marks_obtained': isAbsent ? 'Absent' : (marksObt?.toString() ?? '-'),
          'status': isAbsent ? 'Absent' : (isPass ? 'PASS' : 'FAIL'),
          'is_pass': isPass,
          'subject_name': sub?['name']?.toString() ?? 'N/A',
          'max_marks': sub?['max_marks'] ?? 100,
          'pass_marks': passMarks,
        };
      }).toList();

      finalData.add({
        'result': {
          'exam_name': exam?['name']?.toString() ?? 'Exam #$examId',
          'exam_date': exam?['exam_date']?.toString() ?? 'N/A',
          'total_marks': r['total_marks'] ?? 0.0,
          'percentage': (r['percentage'] as num?)?.toDouble() ?? 0.0,
          'grade': r['grade']?.toString() ?? 'N/A',
          'status': r['status']?.toString() ?? 'DRAFT',
          'rank': r['rank'],
        },
        'marks': marksList,
      });
    }

    return finalData;
  } catch (_) {
    return [];
  }
});

class StudentResultsTab extends ConsumerWidget {
  final Student student;

  const StudentResultsTab({super.key, required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (student.id == null) return const Center(child: Text('Student ID is null'));

    final resultsAsync = ref.watch(studentResultsProvider(student.id!));

    return resultsAsync.when(
      data: (data) {
        if (data.isEmpty) {
          return const Center(
            child: Text('No academic results found for this student.', style: TextStyle(color: AppColors.textMuted)),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: data.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xl),
          itemBuilder: (context, index) {
            final item = data[index];
            final r = item['result'];
            final marks = item['marks'] as List;

            final totalMarks = r['total_marks'];
            final percentage = (r['percentage'] as num?)?.toDouble() ?? 0.0;
            final grade = r['grade'] ?? 'N/A';
            final status = r['status'] ?? 'DRAFT';

            final isPass = status.toString().toUpperCase() == 'PASS';
            final statusColor = isPass ? AppColors.success.base : AppColors.danger.base;

            return SectionCard(
              title: r['exam_name'],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Exam Date: ${r['exam_date'] ?? 'N/A'}', style: const TextStyle(color: AppColors.textMuted)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: DataTable(
                      headingRowColor: const WidgetStatePropertyAll(Color(0xFFF8FAFC)),
                      columns: const [
                        DataColumn(label: Text('Subject')),
                        DataColumn(label: Text('Max Marks')),
                        DataColumn(label: Text('Pass Marks')),
                        DataColumn(label: Text('Obtained')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: marks.map((m) {
                        final subStatus = m['status']?.toString() ?? 'N/A';
                        final subPass = m['is_pass'] == true;
                        return DataRow(
                          cells: [
                            DataCell(Text(m['subject_name'].toString())),
                            DataCell(Text(m['max_marks'].toString())),
                            DataCell(Text(m['pass_marks'].toString())),
                            DataCell(Text(m['marks_obtained']?.toString() ?? '-')),
                            DataCell(Text(
                              subStatus,
                              style: TextStyle(
                                color: subPass ? AppColors.success.base : AppColors.danger.base,
                                fontWeight: FontWeight.w600,
                              ),
                            )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (r['rank'] != null) ...[
                        _StatBadge('Rank', '#${r['rank']}'),
                        const SizedBox(width: AppSpacing.md),
                      ],
                      _StatBadge('Total Marks', '$totalMarks'),
                      const SizedBox(width: AppSpacing.md),
                      _StatBadge('Percentage', '${percentage.toStringAsFixed(2)}%'),
                      const SizedBox(width: AppSpacing.md),
                      _StatBadge('Grade', grade, isGrade: true),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final bool isGrade;

  const _StatBadge(this.label, this.value, {this.isGrade = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          Text(
            value,
            style: TextStyle(
              fontSize: isGrade ? 18 : 16,
              fontWeight: FontWeight.bold,
              color: isGrade ? AppColors.brand : AppColors.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}
