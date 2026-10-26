// lib/core/repositories/supabase/supabase_announcement_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/announcement.dart';
import '../../services/supabase_service.dart';
import '../interfaces/announcement_repository_interface.dart';

class SupabaseAnnouncementRepository implements AnnouncementRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  // Clean announcements store (no mock/dummy data)
  static final List<Announcement> _fallbackAnnouncements = [];

  @override
  Future<Map<String, dynamic>> sendAnnouncement({
    required String category,
    required String title,
    required String body,
    required String audienceType,
    List<dynamic> audienceIds = const [],
    int minBalancePaise = 0,
    bool dryRun = false,
  }) async {
    final payload = {
      'category': category,
      'title': title,
      'body': body,
      'audience_type': audienceType,
      'audience_ids': audienceIds,
      'min_balance_paise': minBalancePaise,
      'dry_run': dryRun,
    };

    if (!dryRun) {
      SupabaseService.instance.assertCanWrite('send announcement');
    }

    final res = await _client.rpc('send_announcement', params: {'p_payload': payload});
    if (res is Map && res.isNotEmpty) {
      return Map<String, dynamic>.from(res);
    }
    throw StateError('Empty response from send_announcement RPC.');
  }

  @override
  Future<Map<String, dynamic>> retractAnnouncement(int announcementId) async {
    SupabaseService.instance.assertCanWrite('retract announcement');
    final res = await _client.rpc('retract_announcement', params: {
      'p_announcement_id': announcementId,
    });
    return Map<String, dynamic>.from(res is Map ? res : {});
  }

  @override
  Future<List<Announcement>> getAnnouncements() async {
    try {
      final data = await _client
          .from('announcements')
          .select('*')
          .order('created_at', ascending: false);

      final list = <Announcement>[];
      for (final row in (data as List)) {
        final annId = row['id'] as int;

        // Count read receipts
        int readCount = 0;
        try {
          final readRes = await _client
              .from('notifications')
              .select('id')
              .eq('announcement_id', annId)
              .not('read_at', 'is', null);
          readCount = (readRes as List).length;
        } catch (_) {}

        final rowMap = Map<String, dynamic>.from(row);
        rowMap['read_count'] = readCount;
        list.add(Announcement.fromMap(rowMap));
      }
      return list;
    } catch (_) {
      return [];
    }
  }
}
