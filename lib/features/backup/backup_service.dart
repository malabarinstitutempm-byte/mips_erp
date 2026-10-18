import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../../core/services/supabase_service.dart';

class BackupInfo {
  final DateTime? lastBackupDate;
  final int sizeBytes;
  final String? filePath;
  final bool isOlderThan3Days;
  final String formattedSize;

  BackupInfo({
    required this.lastBackupDate,
    required this.sizeBytes,
    required this.filePath,
    required this.isOlderThan3Days,
    required this.formattedSize,
  });

  static BackupInfo none() => BackupInfo(
        lastBackupDate: null,
        sizeBytes: 0,
        filePath: null,
        isOlderThan3Days: true,
        formattedSize: '0 KB',
      );
}

class BackupService {
  static const String backupSubdir = 'MIPS_ERP_Database/Backups';

  /// Backward-compatible aliases for existing callers
  static Future<String> downloadCloudBackup([String? targetJsonPath]) =>
      exportCloudDatabaseBackup(targetZipPath: targetJsonPath);

  static Future<String?> createLocalDocumentsBackup([String? targetZipPath]) =>
      exportCloudDatabaseBackup(targetZipPath: targetZipPath);

  static Future<String?> createBackup([String? targetZipPath]) =>
      exportCloudDatabaseBackup(targetZipPath: targetZipPath);

  static DateTime? _lastWebBackupDate;
  static int _lastWebBackupSizeBytes = 0;
  static String? _lastWebBackupFileName;

  /// Resolves the institutional backup directory: Documents/MIPS_ERP_Database/Backups/
  static Future<Directory> getBackupDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('Local filesystem directory is not available on web.');
    }
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(docsDir.path, backupSubdir));
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }
    return backupDir;
  }

  /// Automatically creates a daily backup on desktop launch (once per day maximum).
  static Future<String?> performDailyAutoBackupIfNeeded([String? password]) async {
    if (kIsWeb) return null;
    try {
      final info = await getLastBackupInfo();
      final now = DateTime.now();

      // If a backup already occurred today, skip auto-backup
      if (info.lastBackupDate != null) {
        final last = info.lastBackupDate!;
        if (last.year == now.year && last.month == now.month && last.day == now.day) {
          return null; // Already backed up today
        }
      }

      return await exportCloudDatabaseBackup(password: password);
    } catch (e) {
      // Auto-backup failure should not prevent app startup
      return null;
    }
  }

  /// Exports ALL cloud tables to a password-protected ZIP containing JSON and CSV files.
  /// Enforces retention: last 10 daily backups + 1 per month.
  static Future<String> exportCloudDatabaseBackup({String? password, String? targetZipPath}) async {
    SupabaseService.instance.assertCanWrite('export cloud database backup');

    final client = SupabaseService.instance.client;
    Map<String, dynamic>? dump;
    try {
      final res = await client.rpc('export_database_dump');
      if (res != null && res is Map) {
        dump = Map<String, dynamic>.from(res);
      }
    } catch (_) {
      // Stored procedure missing or not cached, fallback to direct query
      dump = null;
    }

    dump ??= await _fetchClientSideDump(client);

    final meta = Map<String, dynamic>.from(dump['meta'] ?? {});
    final tables = Map<String, dynamic>.from(dump['tables'] ?? {});

    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd_HHmmss').format(now);
    final monthStr = DateFormat('yyyy-MM').format(now);

    final archive = Archive();

    // 1. Add metadata & reconciliation files
    final metaBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(meta));
    archive.addFile(ArchiveFile('metadata.json', metaBytes.length, metaBytes));

    final reconciliation = meta['reconciliation'] ?? {};
    final recBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(reconciliation));
    archive.addFile(ArchiveFile('reconciliation.json', recBytes.length, recBytes));

    // 2. Add individual table dumps in both JSON and CSV
    final Map<String, String> checksums = {};

    for (final entry in tables.entries) {
      final tableName = entry.key;
      final rows = (entry.value as List?)?.cast<Map<String, dynamic>>() ?? [];

      // JSON file
      final jsonContent = utf8.encode(const JsonEncoder.withIndent('  ').convert(rows));
      archive.addFile(ArchiveFile('json/$tableName.json', jsonContent.length, jsonContent));
      checksums['json/$tableName.json'] = sha256.convert(jsonContent).toString();

      // CSV file
      final csvString = _convertRowsToCsv(rows);
      final csvContent = utf8.encode(csvString);
      archive.addFile(ArchiveFile('csv/$tableName.csv', csvContent.length, csvContent));
      checksums['csv/$tableName.csv'] = sha256.convert(csvContent).toString();
    }

    // 3. Manifest with SHA-256 Checksums
    final manifest = {
      'app': 'MIPS ERP',
      'version': '2.0.0',
      'backup_type': 'cloud_full_export',
      'created_at': now.toIso8601String(),
      'tables_exported': tables.keys.toList(),
      'checksums': checksums,
      'reconciliation': reconciliation,
    };
    final manifestBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest));
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    // 4. Encode ZIP
    final zipEncoder = ZipEncoder();
    final encodedZipBytes = zipEncoder.encode(archive);

    if (encodedZipBytes == null) {
      throw Exception('Failed to generate ZIP archive.');
    }

    // Apply password-protection envelope
    final effectivePassword = password ?? 'MIPS@CollegeOffice#2026';
    final securedBytes = encryptBackupBytes(Uint8List.fromList(encodedZipBytes), effectivePassword);
    final zipFileName = 'MIPS_Backup_$dateStr.zip';

    // 5. On Web, trigger browser download directly via Printing.sharePdf
    if (kIsWeb) {
      await Printing.sharePdf(
        bytes: Uint8List.fromList(securedBytes),
        filename: zipFileName,
      );
      _lastWebBackupDate = now;
      _lastWebBackupSizeBytes = securedBytes.length;
      _lastWebBackupFileName = zipFileName;
      return zipFileName;
    }

    final backupDir = await getBackupDirectory();
    final resolvedZipPath = targetZipPath ?? p.join(backupDir.path, zipFileName);
    final zipFile = File(resolvedZipPath);
    await zipFile.writeAsBytes(securedBytes);

    // 6. Update Monthly Marker if this is the first backup of the month
    final monthlyFile = File(p.join(backupDir.path, 'MIPS_Monthly_$monthStr.zip'));
    if (!monthlyFile.existsSync()) {
      await zipFile.copy(monthlyFile.path);
    }

    // 7. Record Last Backup Metadata
    final metaFile = File(p.join(backupDir.path, 'backup_meta.json'));
    await metaFile.writeAsString(jsonEncode({
      'last_backup_date': now.toIso8601String(),
      'file_path': resolvedZipPath,
      'size_bytes': zipFile.lengthSync(),
      'status': 'SUCCESS',
    }));

    // 8. Enforce Retention Policy: Keep last 10 daily backups
    await _applyRetentionPolicy(backupDir);

    return resolvedZipPath;
  }

  static Future<Map<String, dynamic>> _fetchClientSideDump(dynamic client) async {
    final Map<String, dynamic> tables = {};
    final candidateTables = [
      'students',
      'courses',
      'batches',
      'student_enrollments',
      'fees',
      'fee_payments',
      'attendance',
      'teachers',
      'audit_log',
      'profiles',
      'announcements',
      'timetable',
      'attendance_sessions',
      'document_records',
      'settings',
    ];

    for (final table in candidateTables) {
      try {
        final List<dynamic> rows = await client.from(table).select();
        tables[table] = rows.cast<Map<String, dynamic>>();
      } catch (_) {
        // Table may not exist or not accessible, safely skip
      }
    }

    final meta = {
      'institution': 'MALABAR INSTITUTE OF PARAMEDICAL SCIENCE',
      'export_type': 'client_fallback_dump',
      'created_at': DateTime.now().toIso8601String(),
      'tables_count': tables.length,
      'reconciliation': {
        'total_tables': tables.length,
        'records_per_table': tables.map((k, v) => MapEntry(k, (v as List).length)),
      },
    };

    return {
      'meta': meta,
      'tables': tables,
    };
  }

  /// Encrypts backup bytes with password-derived key and verification header
  static List<int> encryptBackupBytes(Uint8List plainBytes, String password) {
    // Derive key using SHA-256 of password
    final keyBytes = sha256.convert(utf8.encode(password)).bytes;
    final hmac = Hmac(sha256, keyBytes);
    final signature = hmac.convert(plainBytes).bytes;

    final header = utf8.encode('MIPS_ENCRYPTED_ZIP_V1\n');
    final combined = BytesBuilder();
    combined.add(header);
    combined.add(signature); // 32-byte authentication tag
    // XOR stream cipher with key stream
    final cipherText = Uint8List(plainBytes.length);
    for (int i = 0; i < plainBytes.length; i++) {
      cipherText[i] = plainBytes[i] ^ keyBytes[i % keyBytes.length];
    }
    combined.add(cipherText);

    return combined.toBytes();
  }

  /// Decrypts password-protected backup bytes
  static Uint8List decryptBackupBytes(Uint8List cipherData, String password) {
    final headerPrefix = utf8.encode('MIPS_ENCRYPTED_ZIP_V1\n');
    if (cipherData.length < headerPrefix.length + 32) {
      // Not encrypted with custom header, treat as raw zip bytes
      return cipherData;
    }

    final isCustomHeader = cipherData.sublist(0, headerPrefix.length).every((b) => headerPrefix.contains(b));
    if (!isCustomHeader) {
      return cipherData;
    }

    final keyBytes = sha256.convert(utf8.encode(password)).bytes;
    final expectedSignature = cipherData.sublist(headerPrefix.length, headerPrefix.length + 32);
    final cipherPayload = cipherData.sublist(headerPrefix.length + 32);

    final plainText = Uint8List(cipherPayload.length);
    for (int i = 0; i < cipherPayload.length; i++) {
      plainText[i] = cipherPayload[i] ^ keyBytes[i % keyBytes.length];
    }

    final hmac = Hmac(sha256, keyBytes);
    final calculatedSignature = hmac.convert(plainText).bytes;

    // Verify password authentication
    bool matches = true;
    for (int i = 0; i < 32; i++) {
      if (expectedSignature[i] != calculatedSignature[i]) {
        matches = false;
      }
    }

    if (!matches) {
      throw Exception('Incorrect backup password or corrupted archive.');
    }

    return plainText;
  }

  /// Converts a list of row maps into standard comma-separated values (CSV).
  static String _convertRowsToCsv(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '';

    final headers = rows.first.keys.toList();
    final buffer = StringBuffer();

    // Write header line
    buffer.writeln(headers.map(_escapeCsv).join(','));

    // Write row lines
    for (final row in rows) {
      final values = headers.map((h) => _escapeCsv(row[h]?.toString() ?? ''));
      buffer.writeln(values.join(','));
    }

    return buffer.toString();
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Retains the last 10 daily backups and 1 monthly backup per month.
  static Future<void> _applyRetentionPolicy(Directory backupDir) async {
    try {
      final files = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('MIPS_Backup_') && f.path.endsWith('.zip'))
          .toList();

      // Sort newest first
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      // If more than 10 daily backups, delete older ones
      if (files.length > 10) {
        for (int i = 10; i < files.length; i++) {
          try {
            files[i].deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Retrieves the last successful backup timestamp, size, and 3-day health check.
  static Future<BackupInfo> getLastBackupInfo() async {
    if (kIsWeb) {
      if (_lastWebBackupDate == null) {
        return BackupInfo.none();
      }
      final isOlder = DateTime.now().difference(_lastWebBackupDate!).inDays >= 3;
      return BackupInfo(
        lastBackupDate: _lastWebBackupDate,
        sizeBytes: _lastWebBackupSizeBytes,
        filePath: _lastWebBackupFileName ?? 'Web Archive',
        isOlderThan3Days: isOlder,
        formattedSize: _formatBytes(_lastWebBackupSizeBytes),
      );
    }

    try {
      final backupDir = await getBackupDirectory();
      final metaFile = File(p.join(backupDir.path, 'backup_meta.json'));

      if (metaFile.existsSync()) {
        final content = jsonDecode(await metaFile.readAsString());
        final dateStr = content['last_backup_date'];
        if (dateStr != null) {
          final date = DateTime.parse(dateStr);
          final size = content['size_bytes'] as int? ?? 0;
          final filePath = content['file_path'] as String?;
          final isOlder = DateTime.now().difference(date).inDays >= 3;

          return BackupInfo(
            lastBackupDate: date,
            sizeBytes: size,
            filePath: filePath,
            isOlderThan3Days: isOlder,
            formattedSize: _formatBytes(size),
          );
        }
      }

      // Fallback: Check files directly in backup directory
      final files = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.zip'))
          .toList();

      if (files.isEmpty) {
        return BackupInfo.none();
      }

      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final latest = files.first;
      final modDate = latest.lastModifiedSync();
      final size = latest.lengthSync();

      return BackupInfo(
        lastBackupDate: modDate,
        sizeBytes: size,
        filePath: latest.path,
        isOlderThan3Days: DateTime.now().difference(modDate).inDays >= 3,
        formattedSize: _formatBytes(size),
      );
    } catch (e) {
      return BackupInfo.none();
    }
  }

  /// Copies the latest backup ZIP to a designated external USB flash drive or folder.
  static Future<String> copyLatestBackupTo(String targetDirectoryPath) async {
    if (kIsWeb) {
      throw UnsupportedError('Copying backup directly to external drives is available on Windows Desktop.');
    }
    final info = await getLastBackupInfo();
    if (info.filePath == null || !File(info.filePath!).existsSync()) {
      throw Exception('No existing backup found to copy. Please run a backup first.');
    }

    final targetDir = Directory(targetDirectoryPath);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final sourceFile = File(info.filePath!);
    final fileName = p.basename(sourceFile.path);
    final destinationPath = p.join(targetDir.path, fileName);

    await sourceFile.copy(destinationPath);
    return destinationPath;
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
