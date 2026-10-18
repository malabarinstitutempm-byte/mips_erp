import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../database_helper.dart';
import '../../core/models/university.dart';
import '../../core/models/academic_year.dart';

class MasterDataRepository {
  SupabaseClient get _supabase => SupabaseConfig.client;
  Future<Database> get _localDb async => await DatabaseHelper.instance.database;

  // ===========================================================================
  // Universities
  // ===========================================================================

  Future<List<University>> getUniversities() async {
    try {
      final res = await _supabase
          .from('universities')
          .select()
          .isFilter('deleted_at', null)
          .order('name');

      return (res as List).map((e) => University.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final db = await _localDb;
      final maps = await db.query('universities', orderBy: 'name');
      return maps.map((e) => University.fromMap(e)).toList();
    }
  }

  Future<int> addUniversity(University university) async {
    final payload = {'name': university.name.trim()};

    try {
      final res = await _supabase
          .from('universities')
          .insert(payload)
          .select('id')
          .single();

      final newId = res['id'] as int;

      try {
        final localDb = await _localDb;
        final map = university.toMap();
        map['id'] = newId;
        await localDb.insert('universities', map, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}

      return newId;
    } catch (_) {
      final db = await _localDb;
      return await db.insert('universities', university.toMap());
    }
  }

  Future<int> updateUniversity(University university) async {
    if (university.id == null) return 0;

    final payload = {
      'name': university.name.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await _supabase
          .from('universities')
          .update(payload)
          .eq('id', university.id!);

      try {
        final localDb = await _localDb;
        await localDb.update('universities', university.toMap(), where: 'id = ?', whereArgs: [university.id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final db = await _localDb;
      return await db.update(
        'universities',
        university.toMap(),
        where: 'id = ?',
        whereArgs: [university.id],
      );
    }
  }

  // ===========================================================================
  // Academic Years
  // ===========================================================================

  Future<List<AcademicYear>> getAcademicYears() async {
    try {
      final res = await _supabase
          .from('academic_years')
          .select()
          .isFilter('deleted_at', null)
          .order('year_name', ascending: false);

      return (res as List).map((e) => AcademicYear.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final db = await _localDb;
      final maps = await db.query('academic_years', orderBy: 'year_name DESC');
      return maps.map((e) => AcademicYear.fromMap(e)).toList();
    }
  }

  Future<int> addAcademicYear(AcademicYear year) async {
    try {
      if (year.isCurrent) {
        await _supabase
            .from('academic_years')
            .update({'is_current': false})
            .neq('id', 0);
      }

      final payload = {
        'year_name': year.yearName.trim(),
        'is_current': year.isCurrent,
      };

      final res = await _supabase
          .from('academic_years')
          .insert(payload)
          .select('id')
          .single();

      final newId = res['id'] as int;

      try {
        final localDb = await _localDb;
        final map = year.toMap();
        map['id'] = newId;
        await localDb.insert('academic_years', map, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}

      return newId;
    } catch (_) {
      final db = await _localDb;
      return await db.transaction((txn) async {
        if (year.isCurrent) {
          await txn.update('academic_years', {'is_current': 0});
        }
        return await txn.insert('academic_years', year.toMap());
      });
    }
  }

  Future<int> updateAcademicYear(AcademicYear year) async {
    if (year.id == null) return 0;

    try {
      if (year.isCurrent) {
        await _supabase
            .from('academic_years')
            .update({'is_current': false})
            .neq('id', year.id!);
      }

      final payload = {
        'year_name': year.yearName.trim(),
        'is_current': year.isCurrent,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _supabase
          .from('academic_years')
          .update(payload)
          .eq('id', year.id!);

      try {
        final localDb = await _localDb;
        await localDb.update('academic_years', year.toMap(), where: 'id = ?', whereArgs: [year.id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final db = await _localDb;
      return await db.transaction((txn) async {
        if (year.isCurrent) {
          await txn.update('academic_years', {'is_current': 0});
        }
        return await txn.update(
          'academic_years',
          year.toMap(),
          where: 'id = ?',
          whereArgs: [year.id],
        );
      });
    }
  }
}
