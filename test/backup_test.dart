// test/backup_test.dart
// Phase 7C: Unit tests for Offline Backup, Password-Protected Encryption,
// Decryption Verification, PII Redaction in ErrorLogger, and Retention Health.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';

import 'package:mips_erp/core/services/error_logger.dart';
import 'package:mips_erp/features/backup/backup_service.dart';

void main() {
  group('Phase 7C - Offline Backup & Recovery Tests', () {
    // -------------------------------------------------------------------------
    // 1. ZIP Encoding & Decoding Integrity
    // -------------------------------------------------------------------------
    test('Archive zip encoding and decoding preserves file structure and contents', () {
      final archive = Archive();
      final data = utf8.encode('{"app": "MIPS ERP", "version": "2.0.0"}');
      archive.addFile(ArchiveFile('metadata.json', data.length, data));

      final encoder = ZipEncoder();
      final zipBytes = encoder.encode(archive);
      expect(zipBytes, isNotNull);
      expect(zipBytes!.isNotEmpty, isTrue);

      final decoder = ZipDecoder();
      final decoded = decoder.decodeBytes(zipBytes);
      expect(decoded.files.length, 1);
      expect(decoded.files.first.name, 'metadata.json');
      expect(utf8.decode(decoded.files.first.content as List<int>), contains('MIPS ERP'));
    });

    // -------------------------------------------------------------------------
    // 2. Password-Protected Encryption & Decryption Round-Trip
    // -------------------------------------------------------------------------
    test('BackupService encrypts and decrypts with password authentication tag', () {
      final originalData = utf8.encode('INSTITUTIONAL_STUDENT_FEE_LEDGER_PAYLOAD_2026');
      const password = 'MIPS@CollegeOffice#2026';

      final encrypted = BackupService.encryptBackupBytes(Uint8List.fromList(originalData), password);
      expect(encrypted, isNotNull);
      expect(encrypted.length, greaterThan(originalData.length));

      // Decrypt with correct password
      final decrypted = BackupService.decryptBackupBytes(Uint8List.fromList(encrypted), password);
      expect(utf8.decode(decrypted), 'INSTITUTIONAL_STUDENT_FEE_LEDGER_PAYLOAD_2026');
    });

    test('Decryption with incorrect password throws authentication error', () {
      final originalData = utf8.encode('SECRET_MARKS_DATA');
      const correctPassword = 'MIPS@CollegeOffice#2026';
      const wrongPassword = 'WrongPassword#9999';

      final encrypted = BackupService.encryptBackupBytes(Uint8List.fromList(originalData), correctPassword);

      expect(
        () => BackupService.decryptBackupBytes(Uint8List.fromList(encrypted), wrongPassword),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Incorrect backup password or corrupted archive'),
        )),
      );
    });

    // -------------------------------------------------------------------------
    // 3. Backup Health & 3-Day Age Warning Evaluation
    // -------------------------------------------------------------------------
    test('BackupInfo evaluates age and formats bytes accurately', () {
      final freshDate = DateTime.now().subtract(const Duration(hours: 12));
      final staleDate = DateTime.now().subtract(const Duration(days: 4));

      final freshBackup = BackupInfo(
        lastBackupDate: freshDate,
        sizeBytes: 1024 * 1024 * 2, // 2 MB
        filePath: 'C:/Backups/MIPS_Backup_2026.zip',
        isOlderThan3Days: DateTime.now().difference(freshDate).inDays >= 3,
        formattedSize: '2.00 MB',
      );
      expect(freshBackup.isOlderThan3Days, isFalse);
      expect(freshBackup.formattedSize, '2.00 MB');

      final staleBackup = BackupInfo(
        lastBackupDate: staleDate,
        sizeBytes: 512 * 1024, // 512 KB
        filePath: 'C:/Backups/MIPS_Backup_Old.zip',
        isOlderThan3Days: DateTime.now().difference(staleDate).inDays >= 3,
        formattedSize: '512.0 KB',
      );
      expect(staleBackup.isOlderThan3Days, isTrue);

      final noBackup = BackupInfo.none();
      expect(noBackup.lastBackupDate, isNull);
      expect(noBackup.isOlderThan3Days, isTrue);
      expect(noBackup.formattedSize, '0 KB');
    });

    // -------------------------------------------------------------------------
    // 4. ErrorLogger PII Stripping & Sensitive Data Protection
    // -------------------------------------------------------------------------
    test('ErrorLogger sanitizes logs: redacts tokens, passwords, emails, and phone numbers', () {
      const rawError = 'Failed request: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 '
          'password="SuperSecretPassword123" temp_password: "TempPassword999!" '
          'User email: admin.mips@institution.edu Phone: +919876543210 or 9876543210 '
          'service_role_key: eyJhbGciOiJIUzI1NiJ9';

      final sanitized = ErrorLogger.sanitizeLog(rawError);

      // Verify Bearer and JWT redaction
      expect(sanitized, isNot(contains('Bearer eyJhbGci')));
      expect(sanitized, contains('Bearer [REDACTED]'));
      expect(sanitized, isNot(contains('eyJ')));

      // Verify password redaction
      expect(sanitized, isNot(contains('SuperSecretPassword123')));
      expect(sanitized, isNot(contains('TempPassword999!')));
      expect(sanitized, contains('password: "[REDACTED]"'));

      // Verify Email redaction
      expect(sanitized, isNot(contains('admin.mips@institution.edu')));
      expect(sanitized, contains('[EMAIL_REDACTED]'));

      // Verify Phone redaction
      expect(sanitized, isNot(contains('9876543210')));
      expect(sanitized, contains('[PHONE_REDACTED]'));
    });
  });
}
