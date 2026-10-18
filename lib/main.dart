import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/services/file_storage_service.dart';
import 'core/services/error_logger.dart';
import 'features/backup/backup_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'app.dart';
import 'core/services/supabase_service.dart';
import 'core/database/database_helper.dart';
import 'core/repositories/supabase/supabase_student_repository.dart';
import 'core/repositories/supabase/supabase_batch_repository.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    if (!kIsWeb) {
      if (Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
    }

    // Capture unhandled Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      ErrorLogger.logError(details.exception, details.stack);
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        child: Container(
          padding: const EdgeInsets.all(32),
          color: Colors.white,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              const Text('An unexpected error occurred.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(details.exceptionAsString(), style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              const Text('Details have been logged.', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    };

    // Initialize Supabase Cloud client & connectivity monitor
    try {
      await SupabaseService.instance.initialize();
    } catch (e, st) {
      ErrorLogger.logError(e, st);
    }

    if (!kIsWeb) {
      // Initialize FFI for desktop SQFlite (local student scanned documents)
      try {
        await DatabaseHelper.instance.database;
      } catch (_) {}

      // Clean temporary files from previous sessions
      try {
        await FileStorageService.cleanTemp();
      } catch (_) {}

      // Daily automated cloud backup on startup (once per day maximum)
      try {
        await BackupService.performDailyAutoBackupIfNeeded();
      } catch (e) {
        // Auto-backup failure
      }
    }

    // Preload persisted student and batch data into memory before UI renders
    try {
      await SupabaseBatchRepository.ensureLoaded();
      await SupabaseStudentRepository.ensureLoaded();
    } catch (_) {}

    runApp(
      const ProviderScope(
        child: LifecycleWatcherApp(),
      ),
    );
  }, (error, stack) {
    ErrorLogger.logError(error, stack);
  });
}

class LifecycleWatcherApp extends StatefulWidget {
  const LifecycleWatcherApp({super.key});

  @override
  State<LifecycleWatcherApp> createState() => _LifecycleWatcherAppState();
}

class _LifecycleWatcherAppState extends State<LifecycleWatcherApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && (state == AppLifecycleState.detached || state == AppLifecycleState.paused)) {
      // Trigger backup on desktop app minimize/close
      try {
        getApplicationDocumentsDirectory().then((docs) {
          final pth = p.join(docs.path, 'MIPS_ERP_Database', 'Backups', 'mips_auto_backup_.zip');
          BackupService.createBackup(pth);
        });
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return const MipsErpApp();
  }
}


