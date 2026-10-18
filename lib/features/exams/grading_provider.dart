import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../core/models/grading_scheme.dart';

class GradingSchemePreset {
  final String name;
  final String description;
  final List<GradingScheme> schemes;

  const GradingSchemePreset({
    required this.name,
    required this.description,
    required this.schemes,
  });
}

class GradingPresets {
  static final List<GradingSchemePreset> all = [
    GradingSchemePreset(
      name: 'Standard 7-Tier (A+ to F)',
      description: 'Standard 10% step scale commonly used in colleges and universities.',
      schemes: [
        GradingScheme(id: 1, minPercent: 90.0, maxPercent: 100.0, grade: 'A+', isPass: true),
        GradingScheme(id: 2, minPercent: 80.0, maxPercent: 89.99, grade: 'A', isPass: true),
        GradingScheme(id: 3, minPercent: 70.0, maxPercent: 79.99, grade: 'B+', isPass: true),
        GradingScheme(id: 4, minPercent: 60.0, maxPercent: 69.99, grade: 'B', isPass: true),
        GradingScheme(id: 5, minPercent: 50.0, maxPercent: 59.99, grade: 'C+', isPass: true),
        GradingScheme(id: 6, minPercent: 40.0, maxPercent: 49.99, grade: 'C', isPass: true),
        GradingScheme(id: 7, minPercent: 0.0, maxPercent: 39.99, grade: 'F', isPass: false),
      ],
    ),
    GradingSchemePreset(
      name: 'CBSE / KUHS 9-Tier (A1 to E2)',
      description: '9-point grading scale based on Kerala State & CBSE examination norms.',
      schemes: [
        GradingScheme(id: 1, minPercent: 91.0, maxPercent: 100.0, grade: 'A1', isPass: true),
        GradingScheme(id: 2, minPercent: 81.0, maxPercent: 90.99, grade: 'A2', isPass: true),
        GradingScheme(id: 3, minPercent: 71.0, maxPercent: 80.99, grade: 'B1', isPass: true),
        GradingScheme(id: 4, minPercent: 61.0, maxPercent: 70.99, grade: 'B2', isPass: true),
        GradingScheme(id: 5, minPercent: 51.0, maxPercent: 60.99, grade: 'C1', isPass: true),
        GradingScheme(id: 6, minPercent: 41.0, maxPercent: 50.99, grade: 'C2', isPass: true),
        GradingScheme(id: 7, minPercent: 33.0, maxPercent: 40.99, grade: 'D', isPass: true),
        GradingScheme(id: 8, minPercent: 21.0, maxPercent: 32.99, grade: 'E1', isPass: false),
        GradingScheme(id: 9, minPercent: 0.0, maxPercent: 20.99, grade: 'E2', isPass: false),
      ],
    ),
    GradingSchemePreset(
      name: 'Simple 5-Tier (A to F)',
      description: 'Straightforward 5-grade system suitable for certificate & diploma courses.',
      schemes: [
        GradingScheme(id: 1, minPercent: 80.0, maxPercent: 100.0, grade: 'A', isPass: true),
        GradingScheme(id: 2, minPercent: 65.0, maxPercent: 79.99, grade: 'B', isPass: true),
        GradingScheme(id: 3, minPercent: 50.0, maxPercent: 64.99, grade: 'C', isPass: true),
        GradingScheme(id: 4, minPercent: 35.0, maxPercent: 49.99, grade: 'D', isPass: true),
        GradingScheme(id: 5, minPercent: 0.0, maxPercent: 34.99, grade: 'F', isPass: false),
      ],
    ),
    GradingSchemePreset(
      name: 'Degree Class Honors',
      description: 'Categorization into Distinction, First Class, Second Class, and Pass.',
      schemes: [
        GradingScheme(id: 1, minPercent: 75.0, maxPercent: 100.0, grade: 'Distinction', isPass: true),
        GradingScheme(id: 2, minPercent: 60.0, maxPercent: 74.99, grade: 'First Class', isPass: true),
        GradingScheme(id: 3, minPercent: 50.0, maxPercent: 59.99, grade: 'Second Class', isPass: true),
        GradingScheme(id: 4, minPercent: 40.0, maxPercent: 49.99, grade: 'Pass Class', isPass: true),
        GradingScheme(id: 5, minPercent: 0.0, maxPercent: 39.99, grade: 'Failed', isPass: false),
      ],
    ),
  ];
}

class GradingSchemeRepository {
  SupabaseClient get _client => SupabaseService.instance.client;
  static List<GradingScheme> _cachedSchemes = List<GradingScheme>.from(GradingPresets.all.first.schemes);

  Future<List<GradingScheme>> getAll() async {
    try {
      final data = await _client
          .from('grading_schemes')
          .select('*')
          .order('min_percent', ascending: false);
      if ((data as List).isEmpty) {
        await resetToDefaults();
        final fresh = await _client
            .from('grading_schemes')
            .select('*')
            .order('min_percent', ascending: false);
        final list = (fresh as List).map((m) => GradingScheme.fromMap(Map<String, dynamic>.from(m))).toList();
        if (list.isNotEmpty) _cachedSchemes = List.from(list);
        return List.from(_cachedSchemes);
      }
      final list = (data as List).map((m) => GradingScheme.fromMap(Map<String, dynamic>.from(m))).toList();
      _cachedSchemes = List.from(list);
      return list;
    } catch (_) {
      // In case Supabase table doesn't exist in schema cache (PGRST205) or connection issue:
      // Return cached/preset schemes with IDs assigned
      return List<GradingScheme>.from(_cachedSchemes);
    }
  }

  Future<void> save(GradingScheme scheme) async {
    try {
      SupabaseService.instance.assertCanWrite('save grading scheme');
      final map = scheme.toMap();
      if (scheme.id != null) {
        await _client
            .from('grading_schemes')
            .update(map)
            .eq('id', scheme.id!);
      } else {
        map.remove('id');
        await _client.from('grading_schemes').insert(map);
      }
    } catch (_) {}

    // Update local cache
    if (scheme.id != null) {
      final idx = _cachedSchemes.indexWhere((s) => s.id == scheme.id);
      if (idx != -1) {
        _cachedSchemes[idx] = scheme;
      } else {
        _cachedSchemes.add(scheme);
      }
    } else {
      final nextId = (_cachedSchemes.map((s) => s.id ?? 0).fold(0, (max, v) => v > max ? v : max)) + 1;
      _cachedSchemes.add(scheme.copyWith(id: nextId));
    }
  }

  Future<void> delete(int id) async {
    try {
      SupabaseService.instance.assertCanWrite('delete grading scheme');
      await _client.from('grading_schemes').delete().eq('id', id);
    } catch (_) {}
    _cachedSchemes.removeWhere((s) => s.id == id);
  }

  Future<void> replaceAll(List<GradingScheme> schemes) async {
    _cachedSchemes = schemes.asMap().entries.map((entry) {
      final s = entry.value;
      return s.copyWith(id: s.id ?? (entry.key + 1));
    }).toList();
    try {
      SupabaseService.instance.assertCanWrite('replace grading schemes');
      await _client.from('grading_schemes').delete().gte('id', 0);
      final rows = schemes.map((s) => s.toMap()..remove('id')).toList();
      if (rows.isNotEmpty) {
        await _client.from('grading_schemes').insert(rows);
      }
    } catch (_) {}
  }

  Future<void> resetToDefaults() async {
    final defaultPreset = GradingPresets.all.first;
    await replaceAll(defaultPreset.schemes);
  }

  static ({String grade, bool isPass}) evaluate({
    required double percentage,
    required List<GradingScheme> schemes,
    bool hasFailedSubject = false,
  }) {
    if (hasFailedSubject) {
      final failTier = schemes.where((s) => !s.isPass).firstOrNull;
      return (grade: failTier?.grade ?? 'F', isPass: false);
    }

    final sorted = List<GradingScheme>.from(schemes)
      ..sort((a, b) => b.minPercent.compareTo(a.minPercent));

    for (final s in sorted) {
      if (percentage >= s.minPercent && percentage <= (s.maxPercent + 0.05)) {
        return (grade: s.grade, isPass: s.isPass);
      }
    }

    final lastTier = sorted.isNotEmpty ? sorted.last : null;
    return (grade: lastTier?.grade ?? 'F', isPass: lastTier?.isPass ?? false);
  }
}

class GradingSchemesNotifier extends StateNotifier<AsyncValue<List<GradingScheme>>> {
  final GradingSchemeRepository _repository = GradingSchemeRepository();

  GradingSchemesNotifier() : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final list = await _repository.getAll();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveScheme(GradingScheme scheme) async {
    await _repository.save(scheme);
    await load();
  }

  Future<void> deleteScheme(int id) async {
    await _repository.delete(id);
    await load();
  }

  Future<void> applyPreset(GradingSchemePreset preset) async {
    await _repository.replaceAll(preset.schemes);
    await load();
  }

  Future<void> resetToDefaults() async {
    await _repository.resetToDefaults();
    await load();
  }
}

final gradingSchemesProvider =
    StateNotifierProvider<GradingSchemesNotifier, AsyncValue<List<GradingScheme>>>(
  (ref) => GradingSchemesNotifier(),
);
