import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ErrorLogger {
  static Future<File> get _logFile async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'MIPS_ERP_Database', 'Logs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, 'error_log.txt'));
  }

  /// Sanitizes error messages to remove sensitive PII (emails, passwords, tokens, phones)
  static String sanitizeLog(dynamic input) {
    if (input == null) return '';
    String str = input.toString();

    // Redact auth tokens & bearer keys
    str = str.replaceAll(RegExp(r'Bearer\s+[a-zA-Z0-9._-]+', caseSensitive: false), 'Bearer [REDACTED]');
    str = str.replaceAll(RegExp(r'eyJ[a-zA-Z0-9._-]+'), '[JWT_TOKEN_REDACTED]');

    // Redact passwords & keys
    str = str.replaceAllMapped(
      RegExp(r'(password|temp_password|service_role_key|secret)["\s:=]+[^\s,;"}]+', caseSensitive: false),
      (match) => '${match[1]}: "[REDACTED]"',
    );

    // Redact emails
    str = str.replaceAll(RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'), '[EMAIL_REDACTED]');

    // Redact 10-digit Indian mobile numbers
    str = str.replaceAll(RegExp(r'(?:\+91|0)?[6-9]\d{9}'), '[PHONE_REDACTED]');

    return str;
  }

  static Future<void> logError(dynamic error, dynamic stackTrace) async {
    final sanitizedError = sanitizeLog(error);
    final sanitizedStack = sanitizeLog(stackTrace);

    if (kIsWeb) {
      if (kDebugMode) {
        debugPrint('Web Error: $sanitizedError\n$sanitizedStack');
      }
      return;
    }
    try {
      final file = await _logFile;
      final timestamp = DateTime.now().toIso8601String();
      final logEntry = '[$timestamp]\nERROR: $sanitizedError\nSTACKTRACE:\n$sanitizedStack\n----------------------------------------\n';
      
      await file.writeAsString(logEntry, mode: FileMode.append);
      
      if (kDebugMode) {
        print('Error logged safely (PII redacted): $sanitizedError');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to write error to log file: $e');
      }
    }
  }
}
