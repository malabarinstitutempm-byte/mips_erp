import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mips_erp/core/models/student.dart';
import 'package:mips_erp/core/repositories/supabase/supabase_student_repository.dart';
import 'package:mips_erp/core/repositories/supabase/supabase_batch_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Student & Batch Persistence Tests (Browser Refresh / Offline)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('1. Created student persists across repository reload / browser refresh', () async {
      final repo = SupabaseStudentRepository();

      // Create a new student
      final newStudent = Student(
        name: 'Zayan Ahmed',
        admissionNumber: '2026MLT999',
        registrationNumber: 'MIPS/2026/MLT/999',
        courseId: 1,
        batchId: 1,
        phone: '9847999888',
        gender: 'Male',
        dob: '2005-01-01',
        admissionDate: '2026-08-01',
        status: 'active',
      );

      final created = await repo.createStudent(newStudent);
      expect(created.name, 'Zayan Ahmed');
      expect(created.admissionNumber, '2026MLT999');

      // Verify the student is currently in getStudents
      final listBeforeRefresh = await repo.getStudents();
      expect(listBeforeRefresh.any((s) => s.admissionNumber == '2026MLT999'), isTrue);

      // SIMULATE BROWSER REFRESH (F5):
      // The SharedPreferences data remains in the browser's localStorage.
      // We simulate a fresh session with a new repository instance and fresh static load.
      final freshRepo = SupabaseStudentRepository();
      final listAfterRefresh = await freshRepo.getStudents();

      expect(listAfterRefresh.any((s) => s.name == 'Zayan Ahmed' && s.admissionNumber == '2026MLT999'), isTrue);
      
      // Verify getStudentById finds the persisted student
      final fetched = await freshRepo.getStudentById(created.id!);
      expect(fetched, isNotNull);
      expect(fetched!.name, 'Zayan Ahmed');
    });

    test('2. Promoted batch semester persists across repository reload / browser refresh', () async {
      final batchRepo = SupabaseBatchRepository();

      // Batch 1 starts in Semester 1
      final batchesInitial = await batchRepo.getBatches();
      final batch1 = batchesInitial.firstWhere((b) => b.id == 1);
      final initialSem = batch1.currentSemester;

      // Promote batch 1 to next semester
      final result = await batchRepo.promoteSemester(
        1,
        DateTime(2026, 12, 15),
        DateTime(2027, 1, 5),
      );
      expect(result['success'], isTrue);
      expect(result['promoted_to_semester'], initialSem + 1);

      // Verify immediate state
      final batch1Updated = await batchRepo.getBatchById(1);
      expect(batch1Updated!.currentSemester, initialSem + 1);

      // SIMULATE BROWSER REFRESH (F5):
      final freshBatchRepo = SupabaseBatchRepository();
      final batchesAfterRefresh = await freshBatchRepo.getBatches();
      final batch1AfterRefresh = batchesAfterRefresh.firstWhere((b) => b.id == 1);

      expect(batch1AfterRefresh.currentSemester, initialSem + 1);
    });

    test('3. Updated student details persist across reload', () async {
      final repo = SupabaseStudentRepository();

      // Update student 1 name
      final student1 = await repo.getStudentById(1);
      expect(student1, isNotNull);

      final updated = Student(
        id: 1,
        name: 'Mohammed Hamiz Updated',
        admissionNumber: student1!.admissionNumber,
        registrationNumber: student1.registrationNumber,
        courseId: student1.courseId,
        batchId: student1.batchId,
        gender: student1.gender,
        phone: '9998887776',
        dob: student1.dob,
        admissionDate: student1.admissionDate,
        status: 'active',
      );

      await repo.updateStudent(updated);

      // Fresh repository check
      final freshRepo = SupabaseStudentRepository();
      final fetched = await freshRepo.getStudentById(1);
      expect(fetched!.name, 'Mohammed Hamiz Updated');
      expect(fetched.phone, '9998887776');
    });
  });
}
