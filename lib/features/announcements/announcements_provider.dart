// lib/features/announcements/announcements_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/announcement.dart';
import '../../core/repositories/interfaces/announcement_repository_interface.dart';
import '../../core/repositories/supabase/supabase_announcement_repository.dart';

final announcementRepositoryProvider = Provider<AnnouncementRepository>(
  (ref) => SupabaseAnnouncementRepository(),
);

final announcementsListProvider = FutureProvider<List<Announcement>>((ref) async {
  final repo = ref.watch(announcementRepositoryProvider);
  return await repo.getAnnouncements();
});
