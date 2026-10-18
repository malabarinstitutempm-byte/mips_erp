import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/services/supabase_service.dart';
import 'core/services/inactivity_service.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/auth_provider.dart';
import 'features/layout/app_shell.dart';
import 'shared/widgets/error_screen.dart';

class MipsErpApp extends ConsumerWidget {
  const MipsErpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    return MaterialApp(
      title: 'MIPS Student Management System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: (context, child) {
        // Override the default "Red Screen of Death"
        ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
          return ErrorScreen(
            title: 'Critical UI Error',
            message: 'A layout or rendering issue occurred on this screen.',
            technicalDetails: errorDetails.exceptionAsString(),
          );
        };

        if (child == null) return const SizedBox.shrink();

        // Global offline banner and 30-minute inactivity watcher
        return InactivityWatcher(
          child: OfflineBanner(
            child: child,
          ),
        );
      },
      home: authState.isAuthenticated ? const AppShell() : const LoginScreen(),
    );
  }
}
