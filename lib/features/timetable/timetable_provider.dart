// lib/features/timetable/timetable_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/timetable.dart';
import '../../core/repositories/interfaces/timetable_repository_interface.dart';
import '../../core/repositories/supabase/supabase_timetable_repository.dart';

final timetableRepositoryProvider = Provider<TimetableRepository>(
  (ref) => SupabaseTimetableRepository(),
);

// Selected batch ID for timetable viewing
final selectedTimetableBatchIdProvider = StateProvider<int?>((ref) => null);

// List of timetables for currently selected batch
final timetablesForBatchProvider = FutureProvider<List<Timetable>>((ref) async {
  final batchId = ref.watch(selectedTimetableBatchIdProvider);
  if (batchId == null) return [];
  final repo = ref.watch(timetableRepositoryProvider);
  return await repo.getTimetables(batchId);
});

// Currently selected timetable ID
final selectedTimetableIdProvider = StateProvider<int?>((ref) => null);

// Entries for currently selected timetable
final timetableEntriesProvider = FutureProvider<List<TimetableEntry>>((ref) async {
  final ttId = ref.watch(selectedTimetableIdProvider);
  if (ttId == null) return [];
  final repo = ref.watch(timetableRepositoryProvider);
  return await repo.getTimetableEntries(ttId);
});
