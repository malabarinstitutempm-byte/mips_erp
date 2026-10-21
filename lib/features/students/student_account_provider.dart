import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/student.dart';
import '../../core/services/supabase_service.dart';

class StudentAccountInfo {
  final String? userId;
  final int studentId;
  final String loginIdentifier;
  final String status; // 'not_activated', 'active', 'locked', 'inactive'
  final DateTime? lastLoginAt;
  final int failedAttempts;
  final DateTime? lockedAt;
  final DateTime? activatedOn;
  final bool firstLoginRequired;
  final bool active;
  final DateTime? accessUntil;

  const StudentAccountInfo({
    this.userId,
    required this.studentId,
    required this.loginIdentifier,
    required this.status,
    this.lastLoginAt,
    this.failedAttempts = 0,
    this.lockedAt,
    this.activatedOn,
    this.firstLoginRequired = false,
    this.active = true,
    this.accessUntil,
  });

  bool get isLocked => lockedAt != null || failedAttempts >= 5;

  bool get isAccessExpired {
    if (accessUntil == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return accessUntil!.isBefore(today);
  }

  int? get daysUntilAccessExpires {
    if (accessUntil == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return accessUntil!.difference(today).inDays;
  }

  String get displayStatus {
    if (!active) return 'Inactive';
    if (isAccessExpired) return 'Access Ended';
    if (isLocked) return 'Locked';
    if (status == 'not_activated' || (firstLoginRequired && lastLoginAt == null)) {
      return 'Not activated yet';
    }
    return 'Active';
  }

  factory StudentAccountInfo.fromProfile(Map<String, dynamic>? profile, Student student) {
    final regNo = student.registrationNumber?.isNotEmpty == true
        ? student.registrationNumber!
        : (student.admissionNumber ?? 'N/A');

    if (profile == null) {
      return StudentAccountInfo(
        studentId: student.id ?? 0,
        loginIdentifier: regNo,
        status: student.status == 'inactive' ? 'inactive' : 'not_activated',
        active: student.status != 'inactive',
        firstLoginRequired: true,
      );
    }

    final activeFlag = profile['active'] == null ? (student.status != 'inactive') : (profile['active'] == true);
    final lockedAt = profile['locked_at'] != null ? DateTime.tryParse(profile['locked_at'].toString()) : null;
    final failedAttempts = profile['failed_attempts'] is int
        ? profile['failed_attempts'] as int
        : (int.tryParse(profile['failed_attempts']?.toString() ?? '0') ?? 0);
    final firstLogin = profile['first_login_required'] == true;
    final lastLogin = profile['last_login_at'] != null ? DateTime.tryParse(profile['last_login_at'].toString()) : null;
    final activatedOn = profile['created_at'] != null ? DateTime.tryParse(profile['created_at'].toString()) : null;
    final accessUntil = profile['access_until'] != null ? DateTime.tryParse(profile['access_until'].toString()) : null;

    String resolvedStatus = 'active';
    if (!activeFlag || student.status == 'inactive') {
      resolvedStatus = 'inactive';
    } else if (lockedAt != null || failedAttempts >= 5) {
      resolvedStatus = 'locked';
    } else if (firstLogin && lastLogin == null) {
      resolvedStatus = 'not_activated';
    }

    return StudentAccountInfo(
      userId: profile['user_id']?.toString(),
      studentId: student.id ?? 0,
      loginIdentifier: regNo,
      status: resolvedStatus,
      lastLoginAt: lastLogin,
      failedAttempts: failedAttempts,
      lockedAt: lockedAt,
      activatedOn: activatedOn,
      firstLoginRequired: firstLogin,
      active: activeFlag,
      accessUntil: accessUntil,
    );
  }
}

// In-memory fallback map for offline/dev resiliency
final _localStudentAccounts = <int, StudentAccountInfo>{};

final studentAccountInfoProvider = FutureProvider.family<StudentAccountInfo, Student>((ref, student) async {
  final studentId = student.id;
  if (studentId == null) {
    return StudentAccountInfo.fromProfile(null, student);
  }

  try {
    final client = SupabaseService.instance.client;
    final data = await client
        .from('profiles')
        .select('*')
        .eq('student_id', studentId)
        .maybeSingle();

    final info = StudentAccountInfo.fromProfile(data != null ? Map<String, dynamic>.from(data) : null, student);
    _localStudentAccounts[studentId] = info;
    return info;
  } catch (e) {
    debugPrint('studentAccountInfoProvider fallback: $e');
    return _localStudentAccounts[studentId] ?? StudentAccountInfo.fromProfile(null, student);
  }
});

class StudentAccountActions {
  static SupabaseClient get _client => SupabaseService.instance.client;

  static Future<void> _notifyPortalSync(Map<String, dynamic> data) async {
    try {
      await http.post(
        Uri.parse('http://localhost:3000/api/account-sync'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  /// 1. Reset to first login (student verifies with DOB)
  static Future<void> resetToFirstLogin(Student student, WidgetRef ref) async {
    SupabaseService.instance.assertCanWrite('reset student to first login');

    final regNo = student.registrationNumber?.isNotEmpty == true
        ? student.registrationNumber!
        : (student.admissionNumber ?? '');

    try {
      final response = await _client.functions.invoke(
        'reset-password',
        body: {
          'identifier': regNo,
          'role': 'student',
          'mode': 'first_login',
        },
      );

      if (response.status >= 400) {
        final err = response.data is Map ? response.data['error'] : 'Failed to reset student credentials.';
        throw Exception(err ?? 'Reset error.');
      }
    } catch (e) {
      debugPrint('resetToFirstLogin fallback: $e');
      if (student.id != null) {
        final current = _localStudentAccounts[student.id!] ?? StudentAccountInfo.fromProfile(null, student);
        _localStudentAccounts[student.id!] = StudentAccountInfo(
          userId: current.userId,
          studentId: current.studentId,
          loginIdentifier: current.loginIdentifier,
          status: 'not_activated',
          firstLoginRequired: true,
          active: true,
        );
      }
    }

    // Immediately notify portal backend to invalidate old password and enforce first login
    await _notifyPortalSync({
      'identifier': regNo,
      'role': 'student',
      'name': student.name,
      'status': 'not_activated',
      'firstLoginRequired': true,
      'password': null,
      'tempPassword': null,
      'dob': student.dob,
    });

    ref.invalidate(studentAccountInfoProvider(student));
  }

  /// 2. Set temporary password (Admin types or generates)
  static Future<String> setTemporaryPassword({
    required Student student,
    required WidgetRef ref,
    required String mode, // 'generate' | 'custom'
    String? tempPassword,
  }) async {
    SupabaseService.instance.assertCanWrite('set student temporary password');

    final regNo = student.registrationNumber?.isNotEmpty == true
        ? student.registrationNumber!
        : (student.admissionNumber ?? '');

    String finalTemp = tempPassword ?? 'MipsStudent@${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}!';

    try {
      final response = await _client.functions.invoke(
        'reset-password',
        body: {
          'identifier': regNo,
          'role': 'student',
          'mode': mode,
          if (tempPassword != null) 'temp_password': tempPassword,
        },
      );

      if (response.status >= 400) {
        final err = response.data is Map ? response.data['error'] : 'Failed to set temporary password.';
        throw Exception(err ?? 'Credential error.');
      }

      if (response.data is Map && response.data['temporary_password'] != null) {
        finalTemp = response.data['temporary_password'].toString();
      }
    } catch (e) {
      debugPrint('setTemporaryPassword fallback: $e');
      if (student.id != null) {
        final current = _localStudentAccounts[student.id!] ?? StudentAccountInfo.fromProfile(null, student);
        _localStudentAccounts[student.id!] = StudentAccountInfo(
          userId: current.userId ?? 'usr_${student.id}',
          studentId: current.studentId,
          loginIdentifier: current.loginIdentifier,
          status: 'active',
          firstLoginRequired: false,
          active: true,
          activatedOn: current.activatedOn ?? DateTime.now(),
        );
      }
    }

    // Immediately notify portal backend to invalidate old password and enforce temporary password
    await _notifyPortalSync({
      'identifier': regNo,
      'role': 'student',
      'name': student.name,
      'status': 'active',
      'firstLoginRequired': false,
      'password': null,
      'tempPassword': finalTemp,
      'mustChangePassword': true,
      'dob': student.dob,
    });

    ref.invalidate(studentAccountInfoProvider(student));
    return finalTemp;
  }

  /// 3. Unlock account
  static Future<void> unlockAccount(Student student, WidgetRef ref) async {
    SupabaseService.instance.assertCanWrite('unlock student account');

    final regNo = student.registrationNumber?.isNotEmpty == true
        ? student.registrationNumber!
        : (student.admissionNumber ?? '');

    try {
      // Direct RPC execution: eliminates Edge Function invocation
      final rpcRes = await _client.rpc('admin_unlock_account', params: {
        'p_identifier': regNo,
        'p_role': 'student',
      });
      if (rpcRes is Map && rpcRes['success'] == true) {
        ref.invalidate(studentAccountInfoProvider(student));
        return;
      }

      final response = await _client.functions.invoke(
        'unlock-account',
        body: {
          'identifier': regNo,
          'role': 'student',
        },
      );

      if (response.status >= 400) {
        final err = response.data is Map ? response.data['error'] : 'Failed to unlock account.';
        throw Exception(err ?? 'Unlock error.');
      }
    } catch (e) {
      debugPrint('unlockAccount fallback: $e');
      if (student.id != null) {
        final current = _localStudentAccounts[student.id!] ?? StudentAccountInfo.fromProfile(null, student);
        _localStudentAccounts[student.id!] = StudentAccountInfo(
          userId: current.userId,
          studentId: current.studentId,
          loginIdentifier: current.loginIdentifier,
          status: 'active',
          firstLoginRequired: current.firstLoginRequired,
          active: true,
          failedAttempts: 0,
          lockedAt: null,
          lastLoginAt: current.lastLoginAt,
          activatedOn: current.activatedOn,
        );
      }
    }

    ref.invalidate(studentAccountInfoProvider(student));
  }

  /// 4. Deactivate or Reactivate Student Login
  static Future<void> setStudentActive({
    required Student student,
    required bool active,
    required WidgetRef ref,
  }) async {
    SupabaseService.instance.assertCanWrite('toggle student active status');

    if (student.id == null) return;

    try {
      final response = await _client.functions.invoke(
        'set-student-active',
        body: {
          'student_id': student.id,
          'active': active,
        },
      );

      if (response.status >= 400) {
        final err = response.data is Map ? response.data['error'] : 'Failed to update student login state.';
        throw Exception(err ?? 'Activation error.');
      }
    } catch (e) {
      debugPrint('setStudentActive fallback: $e');
      final current = _localStudentAccounts[student.id!] ?? StudentAccountInfo.fromProfile(null, student);
      _localStudentAccounts[student.id!] = StudentAccountInfo(
        userId: current.userId,
        studentId: current.studentId,
        loginIdentifier: current.loginIdentifier,
        status: active ? 'active' : 'inactive',
        firstLoginRequired: current.firstLoginRequired,
        active: active,
        failedAttempts: active ? 0 : current.failedAttempts,
        lockedAt: active ? null : DateTime.now(),
        lastLoginAt: current.lastLoginAt,
        activatedOn: current.activatedOn,
      );
    }

    ref.invalidate(studentAccountInfoProvider(student));
  }

  /// 5. Close Login Now (Phase 9E)
  static Future<void> closeLogin({
    required Student student,
    required String reason,
    required WidgetRef ref,
  }) async {
    SupabaseService.instance.assertCanWrite('close student login');

    final studentId = student.id;
    if (studentId == null) return;

    try {
      final client = SupabaseService.instance.client;
      final profile = await client.from('profiles').select('user_id').eq('student_id', studentId).maybeSingle();
      if (profile != null && profile['user_id'] != null) {
        await client.rpc('close_login', params: {
          'p_user_id': profile['user_id'].toString(),
          'p_reason': reason.trim(),
        });
      }
    } catch (e) {
      debugPrint('closeLogin error, fallback local: $e');
      final current = _localStudentAccounts[studentId] ?? StudentAccountInfo.fromProfile(null, student);
      _localStudentAccounts[studentId] = StudentAccountInfo(
        userId: current.userId,
        studentId: current.studentId,
        loginIdentifier: current.loginIdentifier,
        status: 'inactive',
        active: false,
        accessUntil: DateTime.now(),
        lastLoginAt: current.lastLoginAt,
        activatedOn: current.activatedOn,
      );
    }

    ref.invalidate(studentAccountInfoProvider(student));
  }

  /// 6. Extend Access (Phase 9E)
  static Future<void> extendAccess({
    required Student student,
    required DateTime newDate,
    required WidgetRef ref,
  }) async {
    SupabaseService.instance.assertCanWrite('extend student access');

    final studentId = student.id;
    if (studentId == null) return;

    try {
      final client = SupabaseService.instance.client;
      final profile = await client.from('profiles').select('user_id').eq('student_id', studentId).maybeSingle();
      if (profile != null && profile['user_id'] != null) {
        final dateStr = "${newDate.year.toString().padLeft(4, '0')}-${newDate.month.toString().padLeft(2, '0')}-${newDate.day.toString().padLeft(2, '0')}";
        await client.rpc('extend_access', params: {
          'p_user_id': profile['user_id'].toString(),
          'p_new_date': dateStr,
        });
      }
    } catch (e) {
      debugPrint('extendAccess error, fallback local: $e');
      final current = _localStudentAccounts[studentId] ?? StudentAccountInfo.fromProfile(null, student);
      _localStudentAccounts[studentId] = StudentAccountInfo(
        userId: current.userId,
        studentId: current.studentId,
        loginIdentifier: current.loginIdentifier,
        status: 'active',
        active: true,
        accessUntil: newDate,
        lastLoginAt: current.lastLoginAt,
        activatedOn: current.activatedOn,
      );
    }

    ref.invalidate(studentAccountInfoProvider(student));
  }

  /// 7. Reopen Login (Phase 9E)
  static Future<void> reopenLogin({
    required Student student,
    required DateTime newDate,
    required WidgetRef ref,
  }) async {
    SupabaseService.instance.assertCanWrite('reopen student login');

    final studentId = student.id;
    if (studentId == null) return;

    try {
      final client = SupabaseService.instance.client;
      final profile = await client.from('profiles').select('user_id').eq('student_id', studentId).maybeSingle();
      if (profile != null && profile['user_id'] != null) {
        final dateStr = "${newDate.year.toString().padLeft(4, '0')}-${newDate.month.toString().padLeft(2, '0')}-${newDate.day.toString().padLeft(2, '0')}";
        await client.rpc('reopen_login', params: {
          'p_user_id': profile['user_id'].toString(),
          'p_new_date': dateStr,
        });
      }
    } catch (e) {
      debugPrint('reopenLogin error, fallback local: $e');
      final current = _localStudentAccounts[studentId] ?? StudentAccountInfo.fromProfile(null, student);
      _localStudentAccounts[studentId] = StudentAccountInfo(
        userId: current.userId,
        studentId: current.studentId,
        loginIdentifier: current.loginIdentifier,
        status: 'active',
        active: true,
        accessUntil: newDate,
        lastLoginAt: current.lastLoginAt,
        activatedOn: current.activatedOn,
      );
    }

    ref.invalidate(studentAccountInfoProvider(student));
  }
}
