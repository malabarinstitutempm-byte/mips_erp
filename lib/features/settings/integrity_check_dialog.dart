import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/database/database_helper.dart';
import '../../core/services/file_storage_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

class IntegrityCheckDialog extends StatefulWidget {
  const IntegrityCheckDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const IntegrityCheckDialog(),
    );
  }

  @override
  State<IntegrityCheckDialog> createState() => _IntegrityCheckDialogState();
}

class _IntegrityCheckDialogState extends State<IntegrityCheckDialog> {
  bool _isRunning = true;
  List<String> _missingFiles = [];
  List<String> _orphanFiles = [];

  @override
  void initState() {
    super.initState();
    _runCheck();
  }

  Future<void> _runCheck() async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      // 1. Get all file paths from DB
      final records = await db.query('student_records', columns: ['file_path']);
      final students = await db.query('students', columns: ['profile_photo_path', 'profile_photo_thumb_path']);
      
      final dbPaths = <String>{};
      
      for (var r in records) {
        dbPaths.add(r['file_path'] as String);
      }
      for (var s in students) {
        if (s['profile_photo_path'] != null) dbPaths.add(s['profile_photo_path'] as String);
        if (s['profile_photo_thumb_path'] != null) dbPaths.add(s['profile_photo_thumb_path'] as String);
      }

      // 2. Check which DB paths are missing on disk
      final missing = <String>[];
      final Map<String, String> normalizedDbPaths = {}; // normalized -> original relative
      
      for (var relPath in dbPaths) {
        final absPath = await FileStorageService.getAbsolutePath(relPath);
        if (!File(absPath).existsSync()) {
          missing.add(relPath);
        }
        // Store normalized relative path for orphan checking
        normalizedDbPaths[relPath.replaceAll('\\', '/')] = relPath;
      }

      // 3. Check for orphan files (files on disk not in DB)
      final orphan = <String>[];
      final rootDir = Directory(await FileStorageService.appDataRoot);
      final studentFilesDir = Directory('${rootDir.path}/student_files');
      
      if (studentFilesDir.existsSync()) {
        final diskFiles = studentFilesDir.listSync(recursive: true).whereType<File>();
        
        for (var file in diskFiles) {
          final diskRelPath = file.path.replaceFirst(rootDir.path, '').replaceFirst(Platform.pathSeparator, '').replaceAll('\\', '/');
          if (!normalizedDbPaths.containsKey(diskRelPath)) {
            orphan.add(diskRelPath);
          }
        }
      }

      if (mounted) {
        setState(() {
          _missingFiles = missing;
          _orphanFiles = orphan;
          _isRunning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _missingFiles = ['Error running check: $e'];
          _isRunning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radius14)),
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Storage Integrity Check', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                if (!_isRunning)
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            
            if (_isRunning)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: AppSpacing.md),
                      Text('Scanning filesystem and database...'),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSection(
                        'Missing Files',
                        'These files are referenced in the database but do not exist on disk.',
                        _missingFiles,
                        AppColors.danger,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _buildSection(
                        'Orphan Files',
                        'These files exist in student_files/ but are not linked to any database record.',
                        _orphanFiles,
                        AppColors.warning,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String subtitle, List<String> items, dynamic colorSet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorSet.dark)),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorSet.base,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(items.length.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
        const SizedBox(height: AppSpacing.md),
        
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.success.tint,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.success.base.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.checkCircle2, color: AppColors.success.base, size: 20),
                const SizedBox(width: AppSpacing.md),
                const Text('No issues found.', style: TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Text(items[index], style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                );
              },
            ),
          ),
      ],
    );
  }
}
