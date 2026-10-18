import 'package:mips_erp/features/timetable/timetable_screen.dart';
// test/phase10_daily_timetable_test.dart
// Phase 10B Flutter Admin Automated Unit & Widget Test Suite

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mips_erp/core/models/daily_timetable.dart';
import 'package:mips_erp/core/models/batch.dart';
import 'package:mips_erp/features/dashboard/tomorrow_timetable_alert_card.dart';
import 'package:mips_erp/features/batches/batches_screen.dart';

void main() {
  group('Phase 10B - Daily Timetable Clash Helper & Service Tests', () {
    test('1. ClashHelper detects teacher clash on overlapping time slots', () {
      final entries = [
        const DailyTimetableEntry(
          id: 1,
          courseName: 'DMLT',
          year: '1st Year',
          teacherName: 'Prof. Suresh Kumar',
          subjectName: 'Clinical Biochemistry',
          classRoom: 'LH-1',
          startTime: '09:00 AM',
          endTime: '10:00 AM',
        ),
        const DailyTimetableEntry(
          id: 2,
          courseName: 'DRT',
          year: '1st Year',
          teacherName: 'Prof. Suresh Kumar',
          subjectName: 'Radiation Physics',
          classRoom: 'LH-2',
          startTime: '09:30 AM',
          endTime: '10:30 AM',
        ),
      ];

      final warnings = DailyTimetableClashHelper.detectClashes(entries);
      expect(warnings.length, 1);
      expect(warnings.first, contains('Teacher Clash'));
      expect(warnings.first, contains('Prof. Suresh Kumar'));
    });

    test('2. ClashHelper detects room conflict on overlapping time slots', () {
      final entries = [
        const DailyTimetableEntry(
          id: 1,
          courseName: 'DMLT',
          year: '1st Year',
          teacherName: 'Dr. Priya Nair',
          subjectName: 'Pathology',
          classRoom: 'LH-1',
          startTime: '10:00 AM',
          endTime: '11:00 AM',
        ),
        const DailyTimetableEntry(
          id: 2,
          courseName: 'DRT',
          year: '1st Year',
          teacherName: 'Dr. Aysha Mariyam',
          subjectName: 'Radiographic Anatomy',
          classRoom: 'LH-1',
          startTime: '10:30 AM',
          endTime: '11:30 AM',
        ),
      ];

      final warnings = DailyTimetableClashHelper.detectClashes(entries);
      expect(warnings.length, 1);
      expect(warnings.first, contains('Room Clash'));
      expect(warnings.first, contains('LH-1'));
    });

    test('3. ClashHelper detects cohort overlap when same course & year has overlapping classes', () {
      final entries = [
        const DailyTimetableEntry(
          id: 1,
          courseName: 'DMLT',
          year: '1st Year',
          teacherName: 'Prof. Suresh Kumar',
          subjectName: 'Biochemistry',
          classRoom: 'LH-1',
          startTime: '09:00 AM',
          endTime: '10:00 AM',
        ),
        const DailyTimetableEntry(
          id: 2,
          courseName: 'DMLT',
          year: '1st Year',
          teacherName: 'Dr. Priya Nair',
          subjectName: 'Hematology',
          classRoom: 'LH-2',
          startTime: '09:15 AM',
          endTime: '10:15 AM',
        ),
      ];

      final warnings = DailyTimetableClashHelper.detectClashes(entries);
      expect(warnings.length, 1);
      expect(warnings.first, contains('Cohort Conflict'));
      expect(warnings.first, contains('DMLT (1st Year)'));
    });

    test('4. ClashHelper returns zero warnings when slots do not overlap', () {
      final entries = [
        const DailyTimetableEntry(
          id: 1,
          courseName: 'DMLT',
          year: '1st Year',
          teacherName: 'Prof. Suresh Kumar',
          subjectName: 'Biochemistry',
          classRoom: 'LH-1',
          startTime: '09:00 AM',
          endTime: '10:00 AM',
        ),
        const DailyTimetableEntry(
          id: 2,
          courseName: 'DMLT',
          year: '1st Year',
          teacherName: 'Prof. Suresh Kumar',
          subjectName: 'Biochemistry Lab',
          classRoom: 'LH-1',
          startTime: '10:15 AM',
          endTime: '11:15 AM',
        ),
      ];

      final warnings = DailyTimetableClashHelper.detectClashes(entries);
      expect(warnings.isEmpty, true);
    });

    test('5. DailyTimetableService date helpers generate standard YYYY-MM-DD formats', () {
      final tomorrow = DailyTimetableService.getTomorrowDateString();
      final today = DailyTimetableService.getTodayDateString();
      final recentDates = DailyTimetableService.getRecentDates();

      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(tomorrow), true);
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(today), true);
      expect(recentDates.length, 7);
      for (final d in recentDates) {
        expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d), true);
      }
    });
  });

  group('Phase 10B - Dashboard & Batches Widget Tests', () {
    testWidgets('6. TomorrowTimetableAlertCard renders alert with Open Timetable button when unpublished', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tomorrowTimetableStatusProvider.overrideWith((ref) => Future.value(false)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: TomorrowTimetableAlertCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text("Tomorrow's timetable is not published yet"), findsOneWidget);
      expect(find.text('Open Timetable'), findsOneWidget);
    });

    testWidgets('7. TomorrowTimetableAlertCard hides completely when published', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tomorrowTimetableStatusProvider.overrideWith((ref) => Future.value(true)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: TomorrowTimetableAlertCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text("Tomorrow's timetable is not published yet"), findsNothing);
      expect(find.text('Open Timetable'), findsNothing);
    });

    testWidgets('8. BatchesScreen renders Semester / Year column and Promote Semester button', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: BatchesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header columns
      expect(find.text('Semester / Year'), findsOneWidget);
      expect(find.text('Actions'), findsOneWidget);

      // Check Promote button
      expect(find.text('Promote Semester'), findsWidgets);
    });

    testWidgets('9. TimetableScreen renders desktop table cleanly without error', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: TimetableScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('COURSE'), findsOneWidget);
      expect(find.text('TEACHER / FACULTY'), findsOneWidget);
    });

    testWidgets('10. TimetableScreen renders mobile cards at 360px without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: TimetableScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Timetable Scheduling'), findsOneWidget);
      expect(find.text('Add Row'), findsOneWidget);
      expect(find.text('Clinical Biochemistry'), findsOneWidget);
    });
  });
}
