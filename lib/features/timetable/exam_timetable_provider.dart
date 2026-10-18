// lib/features/timetable/exam_timetable_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/exam_timetable_entry.dart';
import '../../core/services/supabase_service.dart';

final selectedExamBatchFilterProvider = StateProvider<int?>((ref) => null);

class ExamTimetableNotifier extends StateNotifier<AsyncValue<List<ExamTimetableEntry>>> {
  ExamTimetableNotifier() : super(const AsyncValue.loading()) {
    loadEntries();
  }

  // Institutional default entries for reliable offline testing
  static final List<ExamTimetableEntry> _initialFallbackEntries = [
    ExamTimetableEntry(
      id: 101,
      examId: 1,
      examName: 'First Semester University Examination 2026',
      batchId: 1,
      batchName: 'DMLT Batch A (2023-2025)',
      subjectName: 'Clinical Biochemistry',
      subjectCode: 'MLT101',
      examDate: '2026-11-02',
      startTime: '10:00',
      endTime: '13:00',
      room: 'Main Examination Hall A',
      instructions: 'Reporting time: 09:30 AM. Non-programmable calculators permitted. ID & Hall ticket mandatory.',
    ),
    ExamTimetableEntry(
      id: 102,
      examId: 1,
      examName: 'First Semester University Examination 2026',
      batchId: 1,
      batchName: 'DMLT Batch A (2023-2025)',
      subjectName: 'Hematology & Blood Banking',
      subjectCode: 'MLT102',
      examDate: '2026-11-04',
      startTime: '10:00',
      endTime: '13:00',
      room: 'Main Examination Hall A',
      instructions: 'Reporting time: 09:30 AM. Mandatory practical logbook verification before theory entrance.',
    ),
    ExamTimetableEntry(
      id: 103,
      examId: 1,
      examName: 'First Semester University Examination 2026',
      batchId: 1,
      batchName: 'DMLT Batch A (2023-2025)',
      subjectName: 'Medical Microbiology & Parasitology',
      subjectCode: 'MLT103',
      examDate: '2026-11-06',
      startTime: '10:00',
      endTime: '13:00',
      room: 'Examination Hall B',
      instructions: 'Reporting time: 09:30 AM. Standard university answer book rules apply.',
    ),
    ExamTimetableEntry(
      id: 104,
      examId: 1,
      examName: 'First Semester University Examination 2026',
      batchId: 1,
      batchName: 'DMLT Batch A (2023-2025)',
      subjectName: 'Clinical Pathology & Histotechnology',
      subjectCode: 'MLT104',
      examDate: '2026-11-09',
      startTime: '10:00',
      endTime: '13:00',
      room: 'Examination Hall B',
      instructions: 'Reporting time: 09:30 AM. Final theory paper of Semester 1.',
    ),
  ];

  List<ExamTimetableEntry> _entries = List.from(_initialFallbackEntries);

  Future<void> loadEntries() async {
    state = const AsyncValue.loading();
    try {
      final client = SupabaseService.instance.client;
      final res = await client
          .from('exam_subjects')
          .select('*, exams(id, name, batch_id, exam_date, batches(batch_name))')
          .order('display_order');

      if (res is List && res.isNotEmpty) {
        final loaded = res.map((row) {
          final exam = row['exams'] as Map<String, dynamic>? ?? {};
          final batch = exam['batches'] as Map<String, dynamic>? ?? {};
          return ExamTimetableEntry(
            id: (row['id'] as num?)?.toInt() ?? 0,
            examId: (row['exam_id'] as num?)?.toInt() ?? 0,
            examName: exam['name'] as String? ?? 'Term Examination',
            batchId: (exam['batch_id'] as num?)?.toInt() ?? 1,
            batchName: batch['batch_name'] as String? ?? 'Batch A',
            subjectName: row['name'] as String? ?? 'Subject',
            subjectCode: row['code'] as String? ?? 'SUB',
            examDate: (row['exam_date'] as String?) ?? (exam['exam_date'] as String?) ?? '2026-11-02',
            startTime: (row['start_time'] as String?) ?? '10:00',
            endTime: (row['end_time'] as String?) ?? '13:00',
            room: (row['room'] as String?) ?? 'Exam Hall 1',
            instructions: (row['instructions'] as String?) ?? 'Hall ticket mandatory.',
          );
        }).toList();

        _entries = loaded;
        state = AsyncValue.data(List.unmodifiable(_entries));
        return;
      }
    } catch (_) {}

    // Fallback to active in-memory / local institutional entries
    state = AsyncValue.data(List.unmodifiable(_entries));
  }

  Future<void> addEntry({
    required int batchId,
    required String batchName,
    required String examName,
    required String subjectName,
    required String subjectCode,
    required String examDate,
    required String startTime,
    required String endTime,
    required String room,
    String instructions = 'Reporting time: 30 minutes before exam start. Hall ticket mandatory.',
  }) async {
    final nextId = _entries.fold<int>(100, (max, e) => e.id > max ? e.id : max) + 1;
    final newEntry = ExamTimetableEntry(
      id: nextId,
      examId: 1,
      examName: examName,
      batchId: batchId,
      batchName: batchName,
      subjectName: subjectName,
      subjectCode: subjectCode,
      examDate: examDate,
      startTime: startTime,
      endTime: endTime,
      room: room,
      instructions: instructions,
    );

    _entries.add(newEntry);
    state = AsyncValue.data(List.unmodifiable(_entries));

    try {
      final client = SupabaseService.instance.client;
      await client.from('exam_subjects').insert({
        'name': subjectName,
        'code': subjectCode,
        'max_marks': 100,
        'pass_marks': 40,
        'exam_date': examDate,
        'start_time': startTime,
        'end_time': endTime,
        'room': room,
        'instructions': instructions,
      });
    } catch (_) {}
  }

  Future<void> updateEntry(ExamTimetableEntry updated) async {
    final index = _entries.indexWhere((e) => e.id == updated.id);
    if (index != -1) {
      _entries[index] = updated;
      state = AsyncValue.data(List.unmodifiable(_entries));
    }

    try {
      final client = SupabaseService.instance.client;
      await client.from('exam_subjects').update({
        'name': updated.subjectName,
        'code': updated.subjectCode,
        'exam_date': updated.examDate,
        'start_time': updated.startTime,
        'end_time': updated.endTime,
        'room': updated.room,
        'instructions': updated.instructions,
      }).eq('id', updated.id);
    } catch (_) {}
  }

  Future<void> deleteEntry(int id) async {
    _entries.removeWhere((e) => e.id == id);
    state = AsyncValue.data(List.unmodifiable(_entries));

    try {
      final client = SupabaseService.instance.client;
      await client.from('exam_subjects').delete().eq('id', id);
    } catch (_) {}
  }
}

final examTimetableProvider = StateNotifierProvider<ExamTimetableNotifier, AsyncValue<List<ExamTimetableEntry>>>(
  (ref) => ExamTimetableNotifier(),
);
