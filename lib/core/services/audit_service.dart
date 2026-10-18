import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/audit_log.dart';

class AuditService {
  static Future<void> log(
    DatabaseExecutor db, {
    required String action,
    required String tableName,
    required String recordId,
    Map<String, dynamic>? oldValue,
    Map<String, dynamic>? newValue,
    int? userId, // Will use session user id when implemented
  }) async {
    final log = AuditLog(
      action: action,
      tableName: tableName,
      recordId: recordId,
      oldValue: oldValue != null ? jsonEncode(oldValue) : null,
      newValue: newValue != null ? jsonEncode(newValue) : null,
      userId: userId,
      createdAt: DateTime.now().toIso8601String(),
    );
    await db.insert('audit_log', log.toMap());
  }
}
