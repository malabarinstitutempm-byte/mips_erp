import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mips_erp/features/auth/login_screen.dart';
import 'package:mips_erp/features/dashboard/dashboard_screen.dart';
import 'package:mips_erp/features/students/students_screen.dart';
import 'package:mips_erp/features/courses/courses_screen.dart';
import 'package:mips_erp/features/fees/fees_screen.dart';
import 'package:mips_erp/features/documents/documents_screen.dart';
import 'package:mips_erp/features/exams/exams_screen.dart';
import 'package:mips_erp/features/reports/reports_screen.dart';
import 'package:mips_erp/features/settings/settings_screen.dart';
import 'package:mips_erp/features/attendance/attendance_screen.dart';
import 'package:mips_erp/features/announcements/announcements_screen.dart';
import 'package:mips_erp/features/timetable/timetable_screen.dart';
import 'package:mips_erp/features/teachers/teachers_screen.dart';
import 'package:mips_erp/features/accounts/accounts_screen.dart';
import 'package:mips_erp/features/batches/batches_screen.dart';
import 'package:mips_erp/core/theme/app_theme.dart';

void main() {
  const mobileViewport = Size(360, 640);

  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('>>> ERROR DETAILS: ${details.toString()}');
  };

  Widget createTestWidget(Widget screen, {double textScale = 1.0}) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: mobileViewport,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: screen,
          ),
        ),
      ),
    );
  }

  group('Flutter Admin Screens Responsiveness Tests (360px & textScale 1.3)', () {
    final screens = <String, Widget>{
      'LoginScreen': const LoginScreen(),
      'DashboardScreen': const DashboardScreen(),
      'StudentsScreen': const StudentsScreen(),
      'CoursesScreen': const CoursesScreen(),
      'FeesScreen': const FeesScreen(),
      'DocumentsScreen': const DocumentsScreen(),
      'ExamsScreen': const ExamsScreen(),
      'ReportsScreen': const ReportsScreen(),
      'SettingsScreen': const SettingsScreen(),
      'AttendanceScreen': const AttendanceScreen(),
      'AnnouncementsScreen': const AnnouncementsScreen(),
      'TimetableScreen': const TimetableScreen(),
      'TeachersScreen': const TeachersScreen(),
      'AccountsScreen': const AccountsScreen(),
      'BatchesScreen': const BatchesScreen(),
    };

    for (final entry in screens.entries) {
      testWidgets('${entry.key} renders at 360px without overflow', (tester) async {
        tester.view.physicalSize = mobileViewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestWidget(entry.value, textScale: 1.0));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        // Flutter test framework automatically fails on any unhandled RenderFlex overflow
        final ex = tester.takeException();
        if (ex != null) {
          debugPrint('>>> EXCEPTION: $ex');
          if (ex is FlutterError) {
            for (final d in ex.diagnostics) {
              debugPrint('>>> DIAG: ${d.name} -> ${d.toDescription()}');
            }
          }
        }
        expect(ex, isNull);
      });

      testWidgets('${entry.key} renders at 360px with TextScale 1.3 without overflow', (tester) async {
        tester.view.physicalSize = mobileViewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final oldOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          debugPrint('>>> OVERFLOW OCCURRED: ${details.toDiagnosticsNode().toStringDeep()}');
          oldOnError?.call(details);
        };

        await tester.pumpWidget(createTestWidget(entry.value, textScale: 1.3));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        final ex = tester.takeException();
        if (ex != null) {
          debugPrint('>>> EXCEPTION: $ex');
          if (ex is FlutterError) {
            for (final d in ex.diagnostics) {
              debugPrint('>>> DIAG: ${d.name} -> ${d.toDescription()}');
            }
          }
        }
        expect(ex, isNull);
      });
    }
  });
}
