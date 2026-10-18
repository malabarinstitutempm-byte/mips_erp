// lib/features/dashboard/today_attendance_board.dart
// Phase 8B: Today's Attendance Board for Admin Dashboard (Desktop & Web)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/section_card.dart';
import '../attendance/attendance_provider.dart';
import '../layout/app_shell.dart';

class TodayAttendanceBoard extends ConsumerWidget {
  const TodayAttendanceBoard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(todayAttendanceSlotStatusProvider);

    return SectionCard(
      title: "Today's Attendance Board",
      trailing: IconButton(
        icon: const Icon(LucideIcons.refreshCw, size: 16, color: AppColors.textMuted),
        tooltip: 'Refresh Status',
        onPressed: () => ref.invalidate(todayAttendanceSlotStatusProvider),
      ),
      child: statusAsync.when(
        data: (slots) {
          if (slots.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No active primary course batches found for today.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            );
          }

          // Group by batch
          final Map<int, Map<String, dynamic>> batchMap = {};
          for (final row in slots) {
            final bId = row['batch_id'] as int;
            if (!batchMap.containsKey(bId)) {
              batchMap[bId] = {
                'batch_id': bId,
                'batch_name': row['batch_name'] ?? 'Batch',
                'course_name': row['course_name'] ?? 'Course',
                'slots': <String, Map<String, dynamic>>{},
              };
            }
            final slotType = (row['slot'] ?? '').toString().toLowerCase();
            (batchMap[bId]!['slots'] as Map<String, Map<String, dynamic>>)[slotType] = row;
          }

          final batches = batchMap.values.toList();

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: batches.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
            itemBuilder: (context, i) {
              final b = batches[i];
              final slotsData = b['slots'] as Map<String, Map<String, dynamic>>;
              final morning = slotsData['morning'];
              final evening = slotsData['evening'];

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 650;

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.brandTint,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(LucideIcons.layers, size: 16, color: AppColors.brandDark),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      b['batch_name'] as String,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    Text(
                                      b['course_name'] as String,
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _buildSlotCell(context, ref, 'Morning', morning)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildSlotCell(context, ref, 'Evening', evening)),
                            ],
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.brandTint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(LucideIcons.layers, size: 18, color: AppColors.brandDark),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      b['batch_name'] as String,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    Text(
                                      b['course_name'] as String,
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: _buildSlotCell(context, ref, 'Morning', morning),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: _buildSlotCell(context, ref, 'Evening', evening),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'Failed to load attendance board: $e',
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlotCell(
    BuildContext context,
    WidgetRef ref,
    String slotLabel,
    Map<String, dynamic>? slotData,
  ) {
    final state = (slotData?['state'] ?? 'not_marked').toString().toLowerCase();
    final markedBy = slotData?['marked_by']?.toString();
    final markedAtRaw = slotData?['marked_at']?.toString();
    final noClassReason = slotData?['no_class_reason']?.toString();
    final sessionId = slotData?['session_id'] as int?;

    Color badgeBg;
    Color badgeText;
    IconData badgeIcon;
    String statusText;

    if (state == 'submitted') {
      badgeBg = const Color(0xFFE3F6EC);
      badgeText = const Color(0xFF0B5D3B);
      badgeIcon = LucideIcons.checkCircle2;
      statusText = 'Submitted';
    } else if (state == 'no_class') {
      badgeBg = const Color(0xFFE2E8F0);
      badgeText = const Color(0xFF475569);
      badgeIcon = LucideIcons.ban;
      statusText = 'No Class';
    } else {
      badgeBg = const Color(0xFFFFF3D6);
      badgeText = const Color(0xFF7A4B00);
      badgeIcon = LucideIcons.clock;
      statusText = 'Not Marked';
    }

    String formattedTime = '';
    if (markedAtRaw != null && markedAtRaw.isNotEmpty) {
      try {
        final dt = DateTime.parse(markedAtRaw).toLocal();
        final hh = dt.hour.toString().padLeft(2, '0');
        final mm = dt.minute.toString().padLeft(2, '0');
        formattedTime = '$hh:$mm';
      } catch (_) {
        formattedTime = '';
      }
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                slotLabel,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textStrong),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 11, color: badgeText),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(color: badgeText, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (state == 'submitted') ...[
            Text(
              'By $markedBy${formattedTime.isNotEmpty ? ' at $formattedTime' : ''}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ] else if (state == 'no_class') ...[
            Text(
              noClassReason != null && noClassReason.isNotEmpty ? noClassReason : 'Confirmed no session',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ] else ...[
            const Text(
              'Pending faculty submission',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (state == 'submitted' || state == 'no_class')
                InkWell(
                  onTap: () {
                    // Navigate to Attendance screen for correction
                    ref.read(navigationProvider.notifier).state = 8;
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(LucideIcons.edit3, size: 12, color: AppColors.brand),
                      SizedBox(width: 4),
                      Text(
                        'Correct',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brand),
                      ),
                    ],
                  ),
                )
              else
                InkWell(
                  onTap: () {
                    // Navigate to Attendance tab
                    ref.read(navigationProvider.notifier).state = 8;
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(LucideIcons.plusCircle, size: 12, color: AppColors.brand),
                      SizedBox(width: 4),
                      Text(
                        'Mark / No Class',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brand),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
