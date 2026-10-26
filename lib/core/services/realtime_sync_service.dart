import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../../features/courses/course_provider.dart';
import '../../features/batches/batches_screen.dart';
import '../../features/students/student_provider.dart';
import '../../features/teachers/teacher_provider.dart';
import '../../features/fees/fees_provider.dart';
import '../../features/exams/exam_provider.dart';
import '../../features/announcements/announcements_provider.dart';
import '../../features/timetable/timetable_provider.dart';

final realtimeSyncServiceProvider = Provider<RealtimeSyncService>((ref) {
  final service = RealtimeSyncService(ref);
  service.initialize();
  ref.onDispose(() => service.dispose());
  return service;
});

class RealtimeSyncService {
  final Ref _ref;
  RealtimeChannel? _eventsChannel;
  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  RealtimeSyncService(this._ref);

  void initialize() {
    final client = SupabaseService.instance.client;

    _eventsChannel = client.channel('public:app_events')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'app_events',
        callback: (payload) {
          final newRecord = payload.newRecord;
          _handleAppEvent(newRecord);
        },
      )
      ..subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('[RealtimeSyncService] Subscribed to public:app_events');
        } else if (error != null) {
          debugPrint('[RealtimeSyncService] Subscription error: $error');
        }
      });
  }

  void _handleAppEvent(Map<String, dynamic> record) {
    final topic = record['topic']?.toString() ?? '';
    final domain = record['domain']?.toString() ?? '';
    final action = record['action']?.toString() ?? '';
    final actorName = record['actor_name']?.toString() ?? 'System';
    final metadata = record['metadata'] as Map<String, dynamic>? ?? {};

    debugPrint('[RealtimeSyncService] Received event: domain=$domain, action=$action, topic=$topic by $actorName');

    // Only process events targeting admins or global
    if (topic != 'admins' && topic != 'global') {
      return;
    }

    switch (domain) {
      case 'course':
        _ref.invalidate(coursesProvider);
        _showNotification('Course ${metadata['name'] ?? ''} was ${action}d by $actorName');
        break;

      case 'batch':
        _ref.invalidate(batchesListProvider);
        _ref.invalidate(allBatchesProvider);
        _ref.invalidate(batchesMapProvider);
        _showNotification('Batch ${metadata['name'] ?? ''} updated by $actorName');
        break;

      case 'student':
        _ref.invalidate(studentsProvider);
        _ref.invalidate(allBatchesProvider);
        _showNotification('Student record updated by $actorName');
        break;

      case 'teacher':
        _ref.invalidate(teachersListProvider);
        _showNotification('Staff record updated by $actorName');
        break;

      case 'payment':
        _ref.invalidate(pendingFeesProvider);
        _ref.invalidate(recentPaymentsProvider);
        _ref.invalidate(feeMetricsProvider);
        _showNotification('Payment recorded by $actorName');
        break;

      case 'attendance':
        final slot = metadata['slot'] ?? '';
        final date = metadata['date'] ?? '';
        _showNotification('Attendance for $date ($slot) marked by $actorName');
        break;

      case 'exam':
        _ref.invalidate(examsProvider);
        _showNotification('Exam ${metadata['name'] ?? ''} updated by $actorName');
        break;

      case 'announcement':
        _ref.invalidate(announcementsListProvider);
        _showNotification('Announcement posted by $actorName');
        break;

      case 'timetable':
        _ref.invalidate(timetablesForBatchProvider);
        _ref.invalidate(timetableEntriesProvider);
        _showNotification('Timetable updated by $actorName');
        break;
    }
  }

  void _showNotification(String message) {
    debugPrint('[RealtimeSyncService] Toast: $message');
  }

  void dispose() {
    _eventsChannel?.unsubscribe();
    _eventsChannel = null;
  }
}
