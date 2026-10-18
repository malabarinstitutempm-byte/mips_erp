import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/batch.dart';
import '../../services/supabase_service.dart';
import '../interfaces/batch_repository_interface.dart';

class SupabaseBatchRepository implements BatchRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  static List<Batch> get fallbackBatches => _fallbackBatches;

  static final List<Batch> _fallbackBatches = [
    Batch(id: 1, courseId: 1, batchName: 'Batch 2024-26 (A)', startYear: 2024, endYear: 2026, currentSemester: 1),
    Batch(id: 2, courseId: 1, batchName: 'Batch 2025-27 (B)', startYear: 2025, endYear: 2027, currentSemester: 1),
    Batch(id: 3, courseId: 2, batchName: 'Batch 2024-26', startYear: 2024, endYear: 2026, currentSemester: 2),
    Batch(id: 4, courseId: 3, batchName: 'Batch 2024-26', startYear: 2024, endYear: 2026, currentSemester: 3),
    Batch(id: 5, courseId: 4, batchName: 'Batch 2023-26', startYear: 2023, endYear: 2026, currentSemester: 4),
    Batch(id: 6, courseId: 5, batchName: 'Skill Batch 2025-A', startYear: 2025, endYear: 2025, currentSemester: 1),
    Batch(id: 7, courseId: 6, batchName: 'Skill Batch 2025-B', startYear: 2025, endYear: 2026, currentSemester: 1),
    Batch(id: 8, courseId: 7, batchName: 'Skill Batch 2025-C', startYear: 2025, endYear: 2026, currentSemester: 1),
  ];

  static final Map<int, List<Map<String, dynamic>>> _fallbackSemesters = {
    1: [
      {'id': 1, 'batch_id': 1, 'semester_no': 1, 'start_date': '2024-06-01', 'end_date': null, 'status': 'active'},
    ],
    2: [
      {'id': 2, 'batch_id': 2, 'semester_no': 1, 'start_date': '2025-06-01', 'end_date': null, 'status': 'active'},
    ],
    3: [
      {'id': 3, 'batch_id': 3, 'semester_no': 1, 'start_date': '2024-06-01', 'end_date': '2024-12-15', 'status': 'closed'},
      {'id': 4, 'batch_id': 3, 'semester_no': 2, 'start_date': '2025-01-05', 'end_date': null, 'status': 'active'},
    ],
  };

  static const String _batchesStorageKey = 'mips_persisted_fallback_batches_v1';
  static const String _semestersStorageKey = 'mips_persisted_fallback_semesters_v1';
  static bool _fallbackLoaded = false;

  static Future<void> ensureLoaded() => _ensureFallbackLoaded();

  static Future<void> _ensureFallbackLoaded() async {
    if (_fallbackLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(milliseconds: 200));
      final bJson = prefs.getString(_batchesStorageKey);
      if (bJson != null && bJson.isNotEmpty) {
        final List decoded = jsonDecode(bJson);
        final loaded = decoded.map((e) => Batch.fromMap(Map<String, dynamic>.from(e))).toList();
        if (loaded.isNotEmpty) {
          _fallbackBatches.clear();
          _fallbackBatches.addAll(loaded);
        }
      }
      final sJson = prefs.getString(_semestersStorageKey);
      if (sJson != null && sJson.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(sJson);
        _fallbackSemesters.clear();
        decoded.forEach((key, val) {
          final bId = int.tryParse(key);
          if (bId != null && val is List) {
            _fallbackSemesters[bId] = val.map((item) => Map<String, dynamic>.from(item as Map)).toList();
          }
        });
      }
      _fallbackLoaded = true;
    } catch (e) {
      debugPrint('Error loading persisted fallback batches: $e');
      _fallbackLoaded = true;
    }
  }

  static Future<void> _persistFallbackBatches() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(milliseconds: 200));
      final jsonList = _fallbackBatches.map((b) => b.toMap()).toList();
      await prefs.setString(_batchesStorageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving persisted batches: $e');
    }
  }

  static Future<void> _persistFallbackSemesters() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(milliseconds: 200));
      final mapToStore = _fallbackSemesters.map((k, v) => MapEntry(k.toString(), v));
      await prefs.setString(_semestersStorageKey, jsonEncode(mapToStore));
    } catch (e) {
      debugPrint('Error saving persisted semesters: $e');
    }
  }

  @override
  Future<List<Batch>> getBatches({
    int? courseId,
    bool includeDeleted = false,
    bool includeCompleted = false,
  }) async {
    await _ensureFallbackLoaded();
    try {
      var req = _client.from('batches').select('*');

      if (!includeDeleted) {
        req = req.isFilter('deleted_at', null);
      }
      if (!includeCompleted) {
        req = req.eq('status', 'active');
      }
      if (courseId != null) {
        req = req.eq('course_id', courseId);
      }

      final data = await req.order('id', ascending: false);
      final list = (data as List).map((row) => Batch.fromMap(Map<String, dynamic>.from(row))).toList();
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('SupabaseBatchRepository.getBatches fallback used: $e');
    }

    var result = _fallbackBatches.where((b) {
      if (!includeDeleted && b.isDeleted) return false;
      if (!includeCompleted && b.status == 'completed') return false;
      if (courseId != null && b.courseId != courseId) return false;
      return true;
    }).toList();

    // If a custom or new course has no batches yet, generate a default active batch
    if (result.isEmpty && courseId != null) {
      final defaultBatch = Batch(
        id: 100 + courseId,
        courseId: courseId,
        batchName: 'Batch ${DateTime.now().year}-${(DateTime.now().year + 2).toString().substring(2)}',
        startYear: DateTime.now().year,
        endYear: DateTime.now().year + 2,
        currentSemester: 1,
      );
      _fallbackBatches.add(defaultBatch);
      await _persistFallbackBatches();
      result = [defaultBatch];
    }

    return result;
  }

  @override
  Future<Batch?> getBatchById(int id) async {
    await _ensureFallbackLoaded();
    try {
      final data = await _client
          .from('batches')
          .select('*')
          .eq('id', id)
          .maybeSingle();

      if (data != null) {
        return Batch.fromMap(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      debugPrint('SupabaseBatchRepository.getBatchById fallback used for id $id: $e');
    }

    final match = _fallbackBatches.where((b) => b.id == id).toList();
    return match.isNotEmpty ? match.first : null;
  }

  @override
  Future<Batch> createBatch(Batch batch) async {
    await _ensureFallbackLoaded();
    try {
      SupabaseService.instance.assertCanWrite('create batch');

      final payload = batch.toMap();
      payload.remove('id');
      payload.remove('is_deleted');
      payload.remove('created_at');
      payload.remove('updated_at');

      final data = await _client
          .from('batches')
          .insert(payload)
          .select()
          .single();

      final res = Batch.fromMap(Map<String, dynamic>.from(data));
      _fallbackBatches.removeWhere((b) => b.id == res.id);
      _fallbackBatches.insert(0, res);
      await _persistFallbackBatches();
      return res;
    } catch (e) {
      debugPrint('SupabaseBatchRepository.createBatch fallback used: $e');
      int maxId = 8;
      for (final b in _fallbackBatches) {
        if (b.id != null && b.id! > maxId) {
          maxId = b.id!;
        }
      }
      final newId = maxId + 1;
      final localBatch = Batch(
        id: newId,
        courseId: batch.courseId,
        batchName: batch.batchName,
        startDate: batch.startDate,
        endDate: batch.endDate,
        startYear: batch.startYear,
        endYear: batch.endYear,
        currentSemester: batch.currentSemester,
        isDeleted: false,
      );
      _fallbackBatches.add(localBatch);
      await _persistFallbackBatches();
      return localBatch;
    }
  }

  @override
  Future<Batch> updateBatch(Batch batch) async {
    await _ensureFallbackLoaded();
    try {
      SupabaseService.instance.assertCanWrite('update batch');

      if (batch.id == null) {
        throw ArgumentError('Batch ID is required for update.');
      }

      final payload = batch.toMap();
      payload.remove('id');
      payload.remove('is_deleted');
      payload.remove('created_at');
      payload['updated_at'] = DateTime.now().toIso8601String();

      final data = await _client
          .from('batches')
          .update(payload)
          .eq('id', batch.id!)
          .select()
          .single();

      final res = Batch.fromMap(Map<String, dynamic>.from(data));
      final index = _fallbackBatches.indexWhere((b) => b.id == batch.id);
      if (index != -1) {
        _fallbackBatches[index] = res;
      }
      await _persistFallbackBatches();
      return res;
    } catch (e) {
      debugPrint('SupabaseBatchRepository.updateBatch fallback used: $e');
      final index = _fallbackBatches.indexWhere((b) => b.id == batch.id);
      if (index != -1) {
        _fallbackBatches[index] = batch;
      }
      await _persistFallbackBatches();
      return batch;
    }
  }

  @override
  Future<void> deleteBatch(int id) async {
    await _ensureFallbackLoaded();
    try {
      SupabaseService.instance.assertCanWrite('delete batch');

      await _client
          .from('batches')
          .update({'deleted_at': DateTime.now().toIso8601String()})
          .eq('id', id);
    } catch (e) {
      debugPrint('SupabaseBatchRepository.deleteBatch fallback used: $e');
      _fallbackBatches.removeWhere((b) => b.id == id);
    }
    await _persistFallbackBatches();
  }

  @override
  Future<List<Map<String, dynamic>>> previewBatchCompletion(int batchId) async {
    try {
      final res = await _client.rpc('preview_batch_completion', params: {'p_batch_id': batchId});
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('SupabaseBatchRepository.previewBatchCompletion fallback: $e');
    }

    return [
      {
        'student_id': 101,
        'student_name': 'Mohammed Fasil K',
        'admission_number': '2023MLT042',
        'registration_number': 'REG-2023-042',
        'sessions_held': 140,
        'attended_sessions': 128,
        'attendance_percentage': 91.43,
        'status_band': 'ok',
        'has_attendance_shortage': false,
        'total_fee': 50000.0,
        'paid_amount': 50000.0,
        'balance': 0.0,
        'has_fee_dues': false,
        'has_other_active_enrollments': false,
        'eligible_for_completion': true,
      },
      {
        'student_id': 102,
        'student_name': 'Aysha Nihala',
        'admission_number': '2023MLT043',
        'registration_number': 'REG-2023-043',
        'sessions_held': 140,
        'attended_sessions': 98,
        'attendance_percentage': 70.0,
        'status_band': 'shortage',
        'has_attendance_shortage': true,
        'total_fee': 50000.0,
        'paid_amount': 45000.0,
        'balance': 5000.0,
        'has_fee_dues': true,
        'has_other_active_enrollments': false,
        'eligible_for_completion': false,
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> completeBatch(
    int batchId, {
    DateTime? completedOn,
    List<int>? excludedStudentIds,
    DateTime? accessUntilOverride,
    bool closeLoginsNow = false,
  }) async {
    await _ensureFallbackLoaded();
    final dateStr = (completedOn ?? DateTime.now()).toIso8601String().split('T')[0];
    final accessStr = accessUntilOverride?.toIso8601String().split('T')[0];

    try {
      final res = await _client.rpc('complete_batch', params: {
        'p_batch_id': batchId,
        'p_completed_on': dateStr,
        'p_excluded_student_ids': excludedStudentIds ?? [],
        'p_access_until': accessStr,
        'p_close_logins_now': closeLoginsNow,
      });

      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('SupabaseBatchRepository.completeBatch fallback: $e');
    }

    final idx = _fallbackBatches.indexWhere((b) => b.id == batchId);
    if (idx != -1) {
      final b = _fallbackBatches[idx];
      _fallbackBatches[idx] = Batch(
        id: b.id,
        courseId: b.courseId,
        batchName: b.batchName,
        startDate: b.startDate,
        endDate: b.endDate,
        startYear: b.startYear,
        endYear: b.endYear,
        currentSemester: b.currentSemester,
        status: 'completed',
        completedOn: dateStr,
      );
      await _persistFallbackBatches();
    }

    return {
      'success': true,
      'batch_id': batchId,
      'completed_on': dateStr,
      'completed_students_count': 2 - (excludedStudentIds?.length ?? 0),
      'excluded_students_count': excludedStudentIds?.length ?? 0,
    };
  }

  @override
  Future<Map<String, dynamic>> reopenBatch(int batchId, {required String reason}) async {
    await _ensureFallbackLoaded();
    try {
      final res = await _client.rpc('reopen_batch', params: {
        'p_batch_id': batchId,
        'p_reason': reason,
      });
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('SupabaseBatchRepository.reopenBatch fallback: $e');
    }

    final idx = _fallbackBatches.indexWhere((b) => b.id == batchId);
    if (idx != -1) {
      final b = _fallbackBatches[idx];
      _fallbackBatches[idx] = Batch(
        id: b.id,
        courseId: b.courseId,
        batchName: b.batchName,
        startDate: b.startDate,
        endDate: b.endDate,
        startYear: b.startYear,
        endYear: b.endYear,
        currentSemester: b.currentSemester,
        status: 'active',
        completedOn: null,
      );
      await _persistFallbackBatches();
    }

    return {
      'success': true,
      'batch_id': batchId,
      'reason': reason,
      'reopened_students_count': 2,
    };
  }

  // ===========================================================================
  // Phase 12B: Semester Promotion & Semester Dates Management
  // ===========================================================================

  @override
  Future<Map<String, dynamic>> previewSemesterPromotion(int batchId) async {
    try {
      final res = await _client.rpc('preview_semester_promotion', params: {'p_batch_id': batchId});
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('SupabaseBatchRepository.previewSemesterPromotion fallback: $e');
    }

    final b = await getBatchById(batchId);
    final curSem = b?.currentSemester ?? 1;
    final curYr = (curSem + 1) ~/ 2;
    final nextSem = curSem + 1;
    final nextYr = (nextSem + 1) ~/ 2;

    return {
      'batch_id': batchId,
      'batch_name': b?.batchName ?? 'Batch',
      'course_name': 'Diploma in Medical Laboratory Technology [DMLT]',
      'current_semester': curSem,
      'current_year': curYr,
      'next_semester': nextSem,
      'next_year': nextYr,
      'year_will_change': nextYr > curYr,
      'course_duration_years': 2,
      'max_semesters': 4,
      'is_final_semester': curSem >= 4,
      'total_students': 2,
      'below_minimum_count': 1,
      'students': [
        {
          'student_id': 101,
          'name': 'Mohammed Fasil K',
          'admission_number': '2023MLT042',
          'registration_number': 'REG-2023-042',
          'sessions_held': 120,
          'attended_count': 110,
          'attendance_percentage': 91.67,
          'status_band': 'ok',
          'below_minimum': false,
        },
        {
          'student_id': 102,
          'name': 'Aysha Nihala',
          'admission_number': '2023MLT043',
          'registration_number': 'REG-2023-043',
          'sessions_held': 120,
          'attended_count': 84,
          'attendance_percentage': 70.0,
          'status_band': 'shortage',
          'below_minimum': true,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> promoteSemester(
    int batchId,
    DateTime closingEndDate,
    DateTime newStartDate,
  ) async {
    await _ensureFallbackLoaded();
    final closeStr = closingEndDate.toIso8601String().split('T')[0];
    final startStr = newStartDate.toIso8601String().split('T')[0];

    try {
      final res = await _client.rpc('promote_semester', params: {
        'p_batch_id': batchId,
        'p_closing_end_date': closeStr,
        'p_new_start_date': startStr,
      });

      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('SupabaseBatchRepository.promoteSemester fallback: $e');
    }

    final idx = _fallbackBatches.indexWhere((b) => b.id == batchId);
    int nextSem = 2;
    int nextYr = 1;
    if (idx != -1) {
      final b = _fallbackBatches[idx];
      nextSem = b.currentSemester + 1;
      nextYr = (nextSem + 1) ~/ 2;
      _fallbackBatches[idx] = b.copyWith(currentSemester: nextSem);

      final semList = _fallbackSemesters.putIfAbsent(batchId, () => []);
      for (int i = 0; i < semList.length; i++) {
        if (semList[i]['semester_no'] == b.currentSemester) {
          semList[i] = {
            ...semList[i],
            'end_date': closeStr,
            'status': 'closed',
          };
        }
      }
      semList.add({
        'id': DateTime.now().millisecondsSinceEpoch % 100000,
        'batch_id': batchId,
        'semester_no': nextSem,
        'start_date': startStr,
        'end_date': null,
        'status': 'active',
      });
      await _persistFallbackBatches();
      await _persistFallbackSemesters();
    }

    return {
      'success': true,
      'batch_id': batchId,
      'promoted_to_semester': nextSem,
      'promoted_to_year': nextYr,
      'students_notified': 2,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getBatchSemesters(int batchId) async {
    await _ensureFallbackLoaded();
    try {
      final data = await _client
          .from('batch_semesters')
          .select('*')
          .eq('batch_id', batchId)
          .order('semester_no', ascending: true);

      if (data is List && data.isNotEmpty) {
        return (data as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
      }
    } catch (e) {
      debugPrint('SupabaseBatchRepository.getBatchSemesters fallback: $e');
    }

    if (_fallbackSemesters.containsKey(batchId)) {
      return List<Map<String, dynamic>>.from(_fallbackSemesters[batchId]!);
    }

    final b = await getBatchById(batchId);
    final curSem = b?.currentSemester ?? 1;
    final list = <Map<String, dynamic>>[];
    for (int i = 1; i <= curSem; i++) {
      list.add({
        'id': batchId * 10 + i,
        'batch_id': batchId,
        'semester_no': i,
        'start_date': '2024-0${i + 5}-01',
        'end_date': i == curSem ? null : '2024-1${i + 1}-30',
        'status': i == curSem ? 'active' : 'closed',
      });
    }
    _fallbackSemesters[batchId] = list;
    await _persistFallbackSemesters();
    return list;
  }

  @override
  Future<Map<String, dynamic>> updateBatchSemesterDates(
    int batchId,
    int semesterNo,
    DateTime startDate,
    DateTime? endDate,
    String? reason,
  ) async {
    await _ensureFallbackLoaded();
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate?.toIso8601String().split('T')[0];

    try {
      final res = await _client.rpc('admin_update_batch_semester_dates', params: {
        'p_batch_id': batchId,
        'p_semester_no': semesterNo,
        'p_start_date': startStr,
        'p_end_date': endStr,
        'p_reason': reason ?? 'Admin date adjustment',
      });

      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('SupabaseBatchRepository.updateBatchSemesterDates fallback: $e');
    }

    final semList = _fallbackSemesters[batchId];
    if (semList != null) {
      final idx = semList.indexWhere((s) => s['semester_no'] == semesterNo);
      if (idx != -1) {
        semList[idx] = {
          ...semList[idx],
          'start_date': startStr,
          'end_date': endStr,
        };
        await _persistFallbackSemesters();
      }
    }

    return {'success': true, 'affected_sessions': 0};
  }
}
