import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/database/database_helper.dart';

class SettingsRepository {
  Future<Database> get _db async => await DatabaseHelper.instance.database;

  Future<Map<String, String>> getAllSettings() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query('settings');
    return {for (var item in maps) item['key'] as String: item['value'] as String? ?? ''};
  }

  Future<String?> getSetting(String key) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] as String?;
    }
    return null;
  }

  Future<void> saveSetting(String key, String value) async {
    final db = await _db;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveAllSettings(Map<String, String> settings) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final entry in settings.entries) {
        await txn.insert(
          'settings',
          {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}
