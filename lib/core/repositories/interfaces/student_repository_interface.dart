import '../../models/student.dart';
import '../../models/student_record_type.dart';
import '../../models/student_record.dart';

abstract class StudentRepository {
  Future<List<Student>> getStudents({
    int? courseId,
    int? batchId,
    int? year,
    String? status,
    String? query,
    bool includeDeleted = false,
    int offset = 0,
    int limit = 50,
  });

  Future<int> getStudentsCount({
    int? courseId,
    int? batchId,
    int? year,
    String? status,
    String? query,
    bool includeDeleted = false,
  });

  Future<Student?> getStudentById(int id);

  Future<Student> createStudent(Student student);
  Future<dynamic> addStudent(Student student) => createStudent(student);

  Future<Student> updateStudent(Student student);

  Future<void> softDeleteStudent(int id, {required String reason});
  Future<void> deleteStudent(int id, [String? reason]) =>
      softDeleteStudent(id, reason: reason ?? 'Deleted by administrator');

  Future<void> restoreStudent(int id);

  Future<String> getNextAdmissionNumber();
  Future<String> generateNextAdmissionNumber() => getNextAdmissionNumber();

  Future<bool> isAdmissionNumberUnique(String admissionNumber, {int? excludeStudentId});

  // Local scanned documents operations (Rule 7: preserved in local SQLite)
  Future<int> addRecordType(StudentRecordType type);
  Future<int> updateRecordType(StudentRecordType type);
  Future<List<StudentRecordType>> getRecordTypes();
  Future<List<StudentRecord>> getStudentRecords(int studentId);
  Future<void> addStudentRecord(StudentRecord record, String actionDetails);
  Future<void> deleteStudentRecord(String recordId, int studentId);

  // Excel Bulk Import & Undo Operations (Sub-phase 3B)
  Future<Map<String, dynamic>> importStudents(List<Map<String, dynamic>> students, {String? importBatchId});
  Future<Map<String, dynamic>> undoImport(String importBatchId);
  Future<String?> getLastImportBatchId();

  // Phase 4 Skill Course additions
  Future<Map<String, dynamic>> addSkillCourse({
    required int studentId,
    required int courseId,
    int? batchId,
    int? feePaise,
  });
  Future<List<Map<String, dynamic>>> getStudentEnrollments(int studentId);
  Future<void> withdrawSkillCourse({
    required int enrollmentId,
    required String reason,
  });

  // Phase 9: Student Completion & Reopen
  Future<Map<String, dynamic>> completeStudent(
    int studentId, {
    int? enrollmentId,
    DateTime? completedOn,
  });

  Future<Map<String, dynamic>> reopenStudent(
    int studentId, {
    int? enrollmentId,
    required String reason,
  });
}
