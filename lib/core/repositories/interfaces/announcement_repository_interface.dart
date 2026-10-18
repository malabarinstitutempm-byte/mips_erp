// lib/core/repositories/interfaces/announcement_repository_interface.dart

import '../../../core/models/announcement.dart';

abstract class AnnouncementRepository {
  Future<Map<String, dynamic>> sendAnnouncement({
    required String category,
    required String title,
    required String body,
    required String audienceType,
    List<dynamic> audienceIds = const [],
    int minBalancePaise = 0,
    bool dryRun = false,
  });

  Future<Map<String, dynamic>> retractAnnouncement(int announcementId);

  Future<List<Announcement>> getAnnouncements();
}
