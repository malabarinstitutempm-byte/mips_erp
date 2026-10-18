// test/phase12_semester_promotion_test.dart
// Phase 12D Flutter Admin Automated Test Suite: Semester-based Promotion & Attendance Filter

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mips_erp/core/models/batch.dart';
import 'package:mips_erp/core/models/student.dart';
import 'package:mips_erp/core/repositories/interfaces/batch_repository_interface.dart';
import 'package:mips_erp/features/courses/course_provider.dart';
import 'package:mips_erp/features/batches/semester_promotion_dialog.dart';
import 'package:mips_erp/features/batches/semester_dates_dialog.dart';
import 'package:mips_erp/features/students/student_profile_screen.dart';
import 'package:mips_erp/features/students/students_screen.dart';
import 'package:mips_erp/features/students/student_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSemesterBatchRepository implements BatchRepository {
  final Map<String, dynamic> previewData;
  Map<String, dynamic>? lastPromoteCall;

  MockSemesterBatchRepository({required this.previewData});

  @override
  Future<List<Batch>> getBatches({
    int? courseId,
    bool includeDeleted = false,
    bool includeCompleted = false,
  }) async => [];

  @override
  Future<Batch?> getBatchById(int id) async => null;

  @override
  Future<Batch> createBatch(Batch batch) async => batch;

  @override
  Future<Batch> updateBatch(Batch batch) async => batch;

  @override
  Future<void> deleteBatch(int id) async {}

  @override
  Future<List<Map<String, dynamic>>> previewBatchCompletion(int batchId) async => [];

  @override
  Future<Map<String, dynamic>> completeBatch(
    int batchId, {
    DateTime? completedOn,
    List<int>? excludedStudentIds,
    DateTime? accessUntilOverride,
    bool closeLoginsNow = false,
  }) async => {'success': true};

  @override
  Future<Map<String, dynamic>> reopenBatch(int batchId, {required String reason}) async => {'success': true};

  @override
  Future<Map<String, dynamic>> previewSemesterPromotion(int batchId) async => previewData;

  @override
  Future<Map<String, dynamic>> promoteSemester(
    int batchId,
    DateTime closingEndDate,
    DateTime newStartDate,
  ) async {
    lastPromoteCall = {
      'batchId': batchId,
      'closingEndDate': closingEndDate,
      'newStartDate': newStartDate,
    };
    return {
      'success': true,
      'batch_name': 'Batch 2024-26',
      'old_semester': 2,
      'new_semester': 3,
      'old_year': 1,
      'new_year': 2,
      'promoted_count': 2,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getBatchSemesters(int batchId) async {
    return [
      {
        'semester_no': 1,
        'start_date': '2025-08-01',
        'end_date': '2025-12-31',
        'status': 'closed',
      },
      {
        'semester_no': 2,
        'start_date': '2026-01-05',
        'end_date': null,
        'status': 'active',
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> updateBatchSemesterDates(
    int batchId,
    int semesterNo,
    DateTime startDate,
    DateTime? endDate,
    String? reason,
  ) async {
    return {'success': true};
  }
}

void main() {
  group('Phase 12D - Semester-based Promotion & Derived Year Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    // =========================================================================
    // 1. Model Derived Year Formula: year = ceil(semester / 2)
    // =========================================================================
    test('1. Batch.currentYear is derived correctly from currentSemester', () {
      final b1 = Batch(id: 1, courseId: 1, batchName: 'B1', currentSemester: 1);
      final b2 = Batch(id: 2, courseId: 1, batchName: 'B2', currentSemester: 2);
      final b3 = Batch(id: 3, courseId: 1, batchName: 'B3', currentSemester: 3);
      final b4 = Batch(id: 4, courseId: 1, batchName: 'B4', currentSemester: 4);
      final b5 = Batch(id: 5, courseId: 1, batchName: 'B5', currentSemester: 5);
      final b6 = Batch(id: 6, courseId: 1, batchName: 'B6', currentSemester: 6);

      // Sem 1 & 2 -> Year 1
      expect(b1.currentYear, 1);
      expect(b2.currentYear, 1);

      // Sem 3 & 4 -> Year 2
      expect(b3.currentYear, 2);
      expect(b4.currentYear, 2);

      // Sem 5 & 6 -> Year 3
      expect(b5.currentYear, 3);
      expect(b6.currentYear, 3);
    });

    // =========================================================================
    // 2. SemesterPromotionDialog: Year Change & Amber Below-Minimum Warning
    // =========================================================================
    testWidgets('2. SemesterPromotionDialog shows Year change notice and below-minimum badge', (tester) async {
      final mockRepo = MockSemesterBatchRepository(
        previewData: {
          'current_semester': 2,
          'next_semester': 3,
          'current_year': 1,
          'next_year': 2,
          'year_will_change': true,
          'is_final_semester': false,
          'total_students': 2,
          'below_minimum_count': 1,
          'students': [
            {
              'student_id': 101,
              'name': 'Rahul Sharma',
              'admission_number': 'ADM01',
              'sessions_held': 60,
              'attendance_percentage': 88.33,
              'below_minimum': false,
            },
            {
              'student_id': 102,
              'name': 'Priya Das',
              'admission_number': 'ADM02',
              'sessions_held': 60,
              'attendance_percentage': 71.67,
              'below_minimum': true, // < 75% -> Below Minimum
            },
          ],
        },
      );

      final batchSem2 = Batch(
        id: 10,
        courseId: 1,
        batchName: 'Batch 2024-26',
        currentSemester: 2, // Sem 2 -> Year 1
        status: 'active',
      );

      await tester.binding.setSurfaceSize(const Size(1000, 800));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            batchRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SemesterPromotionDialog(
                batch: batchSem2,
                onPromoted: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check title and year advancement banner
      expect(find.text('Promote Batch to Semester 3'), findsOneWidget);
      expect(find.textContaining('This also moves the batch to Year 2'), findsOneWidget);

      // Check student preview rows
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Priya Das'), findsOneWidget);
      expect(find.text('88.3%'), findsOneWidget);
      expect(find.text('71.7%'), findsOneWidget);

      // Check below minimum badge in amber
      expect(find.text('Below 75%'), findsOneWidget);

      // Verify date pickers are present
      expect(find.text('Closing Semester End Date'), findsOneWidget);
      expect(find.text('Semester 3 Start Date'), findsOneWidget);
    });

    testWidgets('3. SemesterPromotionDialog displays same year notice for Sem 1 -> Sem 2', (tester) async {
      final mockRepo = MockSemesterBatchRepository(
        previewData: {
          'current_semester': 1,
          'next_semester': 2,
          'current_year': 1,
          'next_year': 1,
          'year_will_change': false,
          'is_final_semester': false,
          'total_students': 1,
          'below_minimum_count': 0,
          'students': [
            {
              'student_id': 101,
              'name': 'Rahul Sharma',
              'admission_number': 'ADM01',
              'sessions_held': 100,
              'attendance_percentage': 92.0,
              'below_minimum': false,
            },
          ],
        },
      );

      final batchSem1 = Batch(
        id: 10,
        courseId: 1,
        batchName: 'Batch 2024-26',
        currentSemester: 1, // Sem 1 -> Year 1
        status: 'active',
      );

      await tester.binding.setSurfaceSize(const Size(1000, 800));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            batchRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SemesterPromotionDialog(
                batch: batchSem1,
                onPromoted: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Promote Batch to Semester 2'), findsOneWidget);
      expect(find.textContaining('Currently Semester 1 (Year 1)'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('92.0%'), findsOneWidget);
    });

    // =========================================================================
    // 4. SemesterDatesDialog: View and Edit Semester Date Ranges
    // =========================================================================
    testWidgets('4. SemesterDatesDialog renders semester list with start/end dates', (tester) async {
      final mockRepo = MockSemesterBatchRepository(previewData: {});
      final batch = Batch(
        id: 10,
        courseId: 1,
        batchName: 'Batch 2024-26',
        currentSemester: 2,
        status: 'active',
      );

      await tester.binding.setSurfaceSize(const Size(1000, 800));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            batchRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SemesterDatesDialog(
                batch: batch,
                onUpdated: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Semester Dates Manager'), findsOneWidget);
      expect(find.text('Sem 1'), findsOneWidget);
      expect(find.text('Sem 2'), findsOneWidget);
      expect(find.text('CLOSED'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
    });

    // =========================================================================
    // 5. StudentProfileScreen: Displays Batch, Current Semester, and Academic Year
    // =========================================================================
    testWidgets('5. StudentProfileScreen renders Batch, Current Semester, and Academic Year', (tester) async {
      final student = Student(
        id: 1,
        name: 'Mohammed Hamiz',
        admissionNumber: '2023MLT042',
        registrationNumber: 'MIPS/2023/MLT/042',
        courseId: 1,
        batchId: 1,
        phone: '9847123456',
        gender: 'Male',
        dob: '2004-05-15',
        admissionDate: '2023-08-01',
        status: 'active',
      );

      final batch = Batch(
        id: 1,
        courseId: 1,
        batchName: 'Batch 2024-26 (A)',
        currentSemester: 1,
        status: 'active',
      );

      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allBatchesProvider.overrideWith((ref) => Future.value([batch])),
          ],
          child: MaterialApp(
            home: StudentProfileScreen(student: student),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check Academic Details rows
      expect(find.text('Batch'), findsOneWidget);
      expect(find.text('Batch 2024-26 (A)'), findsWidgets);
      expect(find.text('Current Semester'), findsOneWidget);
      expect(find.text('Semester 1'), findsOneWidget);
      expect(find.text('Academic Year'), findsOneWidget);
      expect(find.text('Year 1'), findsOneWidget);

      // Check Hero Card semester badge
      expect(find.text('Semester 1 (Year 1)'), findsOneWidget);
    });

    // =========================================================================
    // 6. StudentsScreen: Renders Academic Year filter and Batch / Semester column
    // =========================================================================
    testWidgets('6. StudentsScreen renders Academic Year filter and Batch / Semester column', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: StudentsScreen()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check table column header
      expect(find.text('Batch / Semester'), findsOneWidget);

      // Check Year filter dropdown
      expect(find.text('All Years'), findsOneWidget);
    });
  });
}
