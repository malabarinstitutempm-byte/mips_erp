import 'package:flutter_test/flutter_test.dart';
import 'package:mips_erp/core/services/admin_user_service.dart';
import 'package:mips_erp/features/exams/grading_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Administrator Users & Credentials Tests', () {
    test('AdminUserService loads default administrators cleanly', () async {
      final admins = await AdminUserService.instance.getAdmins();
      expect(admins, isNotEmpty);
      expect(admins.any((a) => a.username == 'admin'), isTrue);
    });

    test('AdminUserService creates new admin with direct permanent password on same screen', () async {
      final newAdmin = await AdminUserService.instance.createAdmin(
        fullName: 'Prof. Abdul Rahman',
        username: 'prof_rahman',
        password: 'Rahman#Password2026',
        email: 'rahman@mipsedu.in',
        role: 'Super Administrator',
      );

      expect(newAdmin.username, equals('prof_rahman'));
      expect(newAdmin.fullName, equals('Prof. Abdul Rahman'));
      expect(newAdmin.password, equals('Rahman#Password2026'));

      // Verify direct authentication works with created password
      final authResult = await AdminUserService.instance.authenticate('prof_rahman', 'Rahman#Password2026');
      expect(authResult, isNotNull);
      expect(authResult!.fullName, equals('Prof. Abdul Rahman'));

      // Verify incorrect password fails
      final failedAuth = await AdminUserService.instance.authenticate('prof_rahman', 'wrong_pass');
      expect(failedAuth, isNull);
    });

    test('AdminUserService updates password directly on-screen', () async {
      final admins = await AdminUserService.instance.getAdmins();
      final target = admins.firstWhere((a) => a.username == 'prof_rahman');

      await AdminUserService.instance.updatePassword(target.id, 'NewUpdatedPass#999');

      final authUpdated = await AdminUserService.instance.authenticate('prof_rahman', 'NewUpdatedPass#999');
      expect(authUpdated, isNotNull);

      final oldAuth = await AdminUserService.instance.authenticate('prof_rahman', 'Rahman#Password2026');
      expect(oldAuth, isNull);
    });

    test('AdminUserService deletes admin and protects sole active admin', () async {
      final admins = await AdminUserService.instance.getAdmins();
      final target = admins.firstWhere((a) => a.username == 'prof_rahman');

      final deleted = await AdminUserService.instance.deleteAdmin(target.id);
      expect(deleted, isTrue);

      final afterDelete = await AdminUserService.instance.authenticate('prof_rahman', 'NewUpdatedPass#999');
      expect(afterDelete, isNull);
    });
  });

  group('Grading Scheme Resilient Fallback Tests', () {
    test('GradingSchemeRepository returns default scheme tiers with IDs when offline or table missing', () async {
      final repo = GradingSchemeRepository();
      final schemes = await repo.getAll();

      expect(schemes, isNotEmpty);
      expect(schemes.any((s) => s.grade == 'A+'), isTrue);
      expect(schemes.any((s) => s.grade == 'F'), isTrue);
      for (final s in schemes) {
        expect(s.id, isNotNull);
      }
    });

    test('GradingSchemeRepository evaluate accurately maps marks', () {
      final defaultSchemes = GradingPresets.all.first.schemes;

      final resA = GradingSchemeRepository.evaluate(percentage: 92.5, schemes: defaultSchemes);
      expect(resA.grade, equals('A+'));
      expect(resA.isPass, isTrue);

      final resF = GradingSchemeRepository.evaluate(percentage: 32.0, schemes: defaultSchemes);
      expect(resF.grade, equals('F'));
      expect(resF.isPass, isFalse);
    });
  });
}
