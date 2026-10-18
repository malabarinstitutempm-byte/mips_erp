// lib/features/dashboard/tomorrow_timetable_alert_card.dart
// Phase 10B: Alert card for unpublished tomorrow's timetable after 17:00 IST

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/daily_timetable.dart';
import '../../core/theme/app_tokens.dart';
import '../layout/app_shell.dart';

final tomorrowTimetableStatusProvider = FutureProvider.autoDispose<bool>((ref) async {
  return await DailyTimetableService.instance.isTomorrowPublished();
});

class TomorrowTimetableAlertCard extends ConsumerWidget {
  const TomorrowTimetableAlertCard({super.key});

  /// Computes whether current Indian Standard Time (Asia/Kolkata, UTC+05:30) is at or past 17:00 (5:00 PM)
  static bool isPastCutoff() {
    final utcNow = DateTime.now().toUtc();
    final istNow = utcNow.add(const Duration(hours: 5, minutes: 30));
    return istNow.hour >= 17;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPublishedAsync = ref.watch(tomorrowTimetableStatusProvider);

    return isPublishedAsync.when(
      data: (isPublished) {
        // If tomorrow's timetable is already published, no alert is needed
        if (isPublished) {
          return const SizedBox.shrink();
        }

        final pastCutoff = isPastCutoff();

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2), // Light alert red/rose background
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: const Color(0xFFF87171), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: const Icon(LucideIcons.alertTriangle, color: Colors.white, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "Tomorrow's timetable is not published yet",
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                        if (pastCutoff) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Past 17:00 IST',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Students and faculty require tomorrow’s class schedule. Please review and publish the timetable.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7F1D1D),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                ),
                onPressed: () {
                  // Navigate to Timetable screen (index 10)
                  ref.read(navigationProvider.notifier).state = 10;
                },
                icon: const Icon(LucideIcons.calendar, size: 16),
                label: const Text('Open Timetable', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
