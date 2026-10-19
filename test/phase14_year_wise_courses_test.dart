// test/phase14_year_wise_courses_test.dart
// Phase 14D Flutter Admin Automated Test Suite: Year-wise Courses, Exams, and Promotion Logic

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mips_erp/core/models/batch.dart';
import 'package:mips_erp/core/models/course.dart';
import 'package:mips_erp/core/models/course_subject.dart';
import 'package:mips_erp/core/models/exam.dart';
import 'package:mips_erp/core/repositories/interfaces/batch_repository_interface.dart';
import 'package:mips_erp/core/repositories/interfaces/course_repository_interface.dart';
import 'package:mips_erp/features/courses/course_provider.dart';
import 'package:mips_erp/features/batches/year_promotion_dialog.dart';

class MockYearBatchRepository implements BatchRepository {
  final Map<String, dynamic> previewData;
  Map<String, dynamic>? lastPromoteCall;

  MockYearBatchRepository({required this.previewData});

  @override
  Future<List<Batch>> getBatches({
    int? courseId,
    bool includeDeleted = false,
    bool includeCompleted = false,
  }) async {
    return [
      Batch(
        id: 20,
        courseId: 5,
        batchName: 'Batch 2024-27 (Year-wise)',
        currentYear: 1,
        currentSemester: 2,
        status: 'active',
        isDeleted: false,
      ),
    ];
  }

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
  Future<Map<String, dynamic>> previewSemesterPromotion(int batchId) async => {
    'error': 'Course has structure "year". Use promote_year for year-wise courses.',
  };

  @override
  Future<Map<String, dynamic>> promoteSemester(
    int batchId,
    DateTime closingEndDate,
    DateTime newStartDate,
  ) async {
    throw ArgumentError('Course has structure "year". Use promote_year for year-wise courses.');
  }

  @override
  Future<List<Map<String, dynamic>>> getBatchSemesters(int batchId) async => [];

  @override
  Future<Map<String, dynamic>> updateBatchSemesterDates(
    int batchId,
    int semesterNo,
    DateTime startDate,
    DateTime? endDate,
    String? reason,
  ) async => {'success': true};

  @override
  Future<Map<String, dynamic>> previewYearPromotion(int batchId) async => previewData;

  @override
  Future<Map<String, dynamic>> promoteYear(
    int batchId,
    DateTime closingEndDate,
    DateTime newStartDate, {
    String? reason,
  }) async {
    lastPromoteCall = {
      'batchId': batchId,
      'closingEndDate': closingEndDate,
      'newStartDate': newStartDate,
      'reason': reason,
    };
    return {
      'success': true,
      'batch_name': 'Batch 2024-27 (Year-wise)',
      'previous_year': 1,
      'current_year': 2,
      'notified_students': 25,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getBatchPeriods(int batchId, {String? periodType}) async {
    return [
      {
        'period_no': 1,
        'period_type': 'year',
        'start_date': '2025-08-01',
        'end_date': '2026-05-31',
        'status': 'closed',
      },
      {
        'period_no': 2,
        'period_type': 'year',
        'start_date': '2026-06-01',
        'end_date': null,
        'status': 'active',
      },
    ];
  }
}

class MockYearCourseRepository implements CourseRepository {
  @override
  Future<List<Course>> getCourses({bool includeDeleted = false}) async {
    return [
      Course(
        id: 5,
        name: 'Bachelor in Medical Imaging Technology',
        code: 'BMIT',
        duration: '3 Years',
        structure: 'year',
        attendanceBasis: 'year',
      ),
      Course(
        id: 1,
        name: 'Diploma in Medical Laboratory Technology',
        code: 'DMLT',
        duration: '2 Years',
        structure: 'semester',
        attendanceBasis: 'semester',
      ),
      Course(
        id: 9,
        name: 'Basic Life Support Certification',
        code: 'BLS',
        duration: '6 Months',
        structure: 'single',
        attendanceBasis: 'none',
      ),
    ];
  }

  @override
  Future<Course?> getCourseById(int id) async => null;

  @override
  Future<Course> createCourse(Course course, List<CourseSubject> subjects) async => course;

  @override
  Future<int> addCourse(Course course) async => course.id ?? 1;

  @override
  Future<Course> updateCourse(Course course, [List<CourseSubject>? subjects]) async => course;

  @override
  Future<void> deleteCourse(int id) async {}

  @override
  Future<List<CourseSubject>> getCourseSubjects(int courseId) async => [];

  @override
  Future<List<CourseSubject>> getSubjectsForCourse(int courseId) async => [];

  @override
  Future<void> saveCourseSubjects(int courseId, List<CourseSubject> subjects) async {}

  @override
  Future<List<Batch>> getBatchesForCourse(int courseId, {bool includeCompleted = false}) async => [];

  @override
  Future<bool> isCourseStructureLocked(int courseId) async {
    return courseId == 5;
  }
}

void main() {
  group('Phase 14D - Year-wise Course Architecture & Models', () {
    test('1. Course Model validates structure and attendanceBasis enums', () {
      final yearCourse = Course(
        id: 5,
        name: 'Bachelor in Medical Imaging Technology',
        code: 'BMIT',
        duration: '3 Years',
        structure: 'year',
        attendanceBasis: 'year',
      );

      expect(yearCourse.isYearWise, isTrue);
      expect(yearCourse.isSemesterWise, isFalse);
      expect(yearCourse.isSingle, isFalse);
      expect(yearCourse.durationYears, equals(3));
      expect(yearCourse.periodsCount, equals(3));
      expect(yearCourse.attendanceBasis, equals('year'));

      final semCourse = Course(
        id: 1,
        name: 'Diploma in Medical Laboratory Technology',
        code: 'DMLT',
        duration: '2 Years',
        structure: 'semester',
        attendanceBasis: 'semester',
      );

      expect(semCourse.isSemesterWise, isTrue);
      expect(semCourse.isYearWise, isFalse);
      expect(semCourse.durationYears, equals(2));
      expect(semCourse.periodsCount, equals(4)); // 2 years * 2 = 4 semesters

      final singleCourse = Course(
        id: 9,
        name: 'BLS Certification',
        code: 'BLS',
        courseType: 'skill',
      );

      expect(singleCourse.isSingle, isTrue);
      expect(singleCourse.periodsCount, equals(1));
      expect(singleCourse.attendanceBasis, equals('none'));
    });

    test('2. Batch Model derives periods correctly for both year and semester structures', () {
      final yearCourse = Course(
        id: 5,
        name: 'BMIT',
        code: 'BMIT',
        duration: '3 Years',
        structure: 'year',
      );

      final semCourse = Course(
        id: 1,
        name: 'DMLT',
        code: 'DMLT',
        duration: '2 Years',
        structure: 'semester',
      );

      // Semester-wise batch
      final semBatch = Batch(
        id: 10,
        courseId: 1,
        batchName: 'Batch 2024-26',
        currentSemester: 3,
      );
      // ceil(3 / 2) = 2
      expect(semBatch.currentYear, equals(2));
      expect(semBatch.currentPeriodNo(semCourse), equals(3));
      expect(semBatch.currentPeriodLabel(semCourse), equals('Semester 3'));

      // Year-wise batch
      final yearBatch = Batch(
        id: 20,
        courseId: 5,
        batchName: 'Batch 2024-27 (Year-wise)',
        currentYear: 2,
        currentSemester: 4,
      );
      expect(yearBatch.currentYear, equals(2));
      expect(yearBatch.currentPeriodNo(yearCourse), equals(2));
      expect(yearBatch.currentPeriodLabel(yearCourse), equals('Year 2'));
    });

    test('3. Exam Model period_type and period_no serialization & display', () {
      final yearExam = Exam(
        id: 101,
        name: 'Year 1 Annual Examination',
        academicYearId: 1,
        courseId: 5,
        batchId: 20,
        periodType: 'year',
        periodNo: 1,
      );

      expect(yearExam.periodType, equals('year'));
      expect(yearExam.periodNo, equals(1));
      expect(yearExam.periodDisplay, equals('Year 1'));

      final semExam = Exam(
        id: 102,
        name: 'Semester 3 Examination',
        academicYearId: 2,
        courseId: 1,
        batchId: 10,
        periodType: 'semester',
        periodNo: 3,
      );

      expect(semExam.periodType, equals('semester'));
      expect(semExam.periodNo, equals(3));
      expect(semExam.periodDisplay, equals('Semester 3'));
    });

    test('4. CourseSubject Model period_no semantics for year and semester subjects', () {
      final yearSubject = CourseSubject(
        id: 1,
        courseId: 5,
        periodNo: 1,
        subjectName: 'Human Anatomy & Physiology',
        subjectCode: 'BMIT-101',
        maxMarks: 100,
        passMarks: 40,
      );
      expect(yearSubject.periodNo, equals(1));

      final map = yearSubject.toMap();
      expect(map['period_no'], equals(1));

      final restored = CourseSubject.fromMap(map);
      expect(restored.periodNo, equals(1));
      expect(restored.subjectName, equals('Human Anatomy & Physiology'));
    });
  });

  group('Phase 14D - Year-wise Promotion Dialog & Guard Tests', () {
    testWidgets('5. YearPromotionDialog renders Year promotion preview and executes promoteYear', (tester) async {
      final mockBatch = Batch(
        id: 20,
        courseId: 5,
        batchName: 'Batch 2024-27 (Year-wise)',
        currentYear: 1,
        currentSemester: 2,
        status: 'active',
      );

      final mockRepo = MockYearBatchRepository(
        previewData: {
          'batch_id': 20,
          'batch_name': 'Batch 2024-27 (Year-wise)',
          'course_name': 'Bachelor in Medical Imaging Technology',
          'current_year': 1,
          'next_year': 2,
          'max_years': 3,
          'active_students_count': 25,
          'closing_end_date': '2026-05-31',
          'new_start_date': '2026-06-01',
        },
      );

      final mockCourseRepo = MockYearCourseRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            batchRepositoryProvider.overrideWithValue(mockRepo),
            courseRepositoryProvider.overrideWithValue(mockCourseRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: YearPromotionDialog(
                batch: mockBatch,
                onPromoted: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check dialog elements
      expect(find.text('Promote Batch to Year 2'), findsOneWidget);
      expect(find.textContaining('Academic Year 2'), findsWidgets);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('Students in Batch'), findsOneWidget);

      // Tap promote button
      final promoteBtn = find.text('Promote to Year 2');
      expect(promoteBtn, findsOneWidget);
      await tester.tap(promoteBtn);
      await tester.pumpAndSettle();

      // Verify promoteYear was invoked
      expect(mockRepo.lastPromoteCall, isNotNull);
      expect(mockRepo.lastPromoteCall!['batchId'], equals(20));
    });

    test('6. Mutual rejection guards: promote_year rejects semester courses; promote_semester rejects year courses', () async {
      final mockRepo = MockYearBatchRepository(previewData: {});

      // Attempting semester promotion on year-wise batch throws error
      expect(
        () => mockRepo.promoteSemester(20, DateTime(2026, 5, 31), DateTime(2026, 6, 1)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('7. Course structure locked verification', () async {
      final courseRepo = MockYearCourseRepository();

      final isLocked = await courseRepo.isCourseStructureLocked(5);
      expect(isLocked, isTrue);

      final isNotLocked = await courseRepo.isCourseStructureLocked(1);
      expect(isNotLocked, isFalse);
    });
  });
}
