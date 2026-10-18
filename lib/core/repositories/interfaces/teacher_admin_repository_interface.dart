import '../../models/teacher.dart';

abstract class TeacherAdminRepository {
  Future<List<Teacher>> getTeachers();

  Future<Teacher?> getTeacherById(int teacherId);

  Future<Map<String, dynamic>> createTeacher({
    required String name,
    required String username,
    String? phone,
    String? tempPassword,
  });

  Future<void> updateTeacher({
    required int teacherId,
    String? name,
    String? phone,
    String? username,
  });

  Future<Map<String, dynamic>> setTeacherActive({
    required int teacherId,
    required bool active,
    int? reassignTo,
  });

  Future<Map<String, dynamic>> resetTeacherPassword({
    required String userId,
    String mode = 'generate',
    String? tempPassword,
    String? username,
  });

  Future<void> resetTeacherToFirstLogin(Teacher teacher);

  Future<void> unlockAccount(String userId);

  Future<List<Map<String, dynamic>>> getTeacherSessions(int teacherId);

  Future<List<Map<String, dynamic>>> getTeacherAuditHistory(int teacherId, {String? userId});
}
