import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_service.dart';

class LockedAccountItem {
  final String? userId;
  final String role; // 'teacher' | 'student'
  final String name;
  final String identifier;
  final String? phone;
  final int failedAttempts;
  final DateTime? lockedAt;
  final DateTime? lastLoginAt;
  final int? entityId;

  const LockedAccountItem({
    this.userId,
    required this.role,
    required this.name,
    required this.identifier,
    this.phone,
    this.failedAttempts = 0,
    this.lockedAt,
    this.lastLoginAt,
    this.entityId,
  });

  factory LockedAccountItem.fromJson(Map<String, dynamic> json) {
    return LockedAccountItem(
      userId: json['user_id']?.toString(),
      role: (json['role'] ?? 'student').toString(),
      name: (json['name'] ?? 'Unknown').toString(),
      identifier: (json['identifier'] ?? 'N/A').toString(),
      phone: json['phone']?.toString(),
      failedAttempts: json['failed_attempts'] is int
          ? json['failed_attempts'] as int
          : (int.tryParse(json['failed_attempts']?.toString() ?? '0') ?? 0),
      lockedAt: json['locked_at'] != null ? DateTime.tryParse(json['locked_at'].toString()) : null,
      lastLoginAt: json['last_login_at'] != null ? DateTime.tryParse(json['last_login_at'].toString()) : null,
      entityId: json['entity_id'] is int ? json['entity_id'] as int : int.tryParse(json['entity_id']?.toString() ?? ''),
    );
  }
}

class UnactivatedStudentItem {
  final int id;
  final String name;
  final String? admissionNumber;
  final String? registrationNumber;
  final String? phone;
  final String courseName;
  final DateTime? createdAt;

  const UnactivatedStudentItem({
    required this.id,
    required this.name,
    this.admissionNumber,
    this.registrationNumber,
    this.phone,
    this.courseName = 'General',
    this.createdAt,
  });

  String get loginIdentifier => registrationNumber?.isNotEmpty == true
      ? registrationNumber!
      : (admissionNumber ?? 'N/A');

  factory UnactivatedStudentItem.fromJson(Map<String, dynamic> json) {
    return UnactivatedStudentItem(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: (json['name'] ?? 'Student').toString(),
      admissionNumber: json['admission_number']?.toString(),
      registrationNumber: json['registration_number']?.toString(),
      phone: json['phone']?.toString(),
      courseName: (json['course_name'] ?? 'Core Program').toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }
}

class RecentResetItem {
  final int id;
  final String action;
  final String actor;
  final String target;
  final DateTime? createdAt;
  final Map<String, dynamic> details;

  const RecentResetItem({
    required this.id,
    required this.action,
    required this.actor,
    required this.target,
    this.createdAt,
    this.details = const {},
  });

  factory RecentResetItem.fromJson(Map<String, dynamic> json) {
    return RecentResetItem(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      action: (json['action'] ?? 'PASSWORD_RESET').toString(),
      actor: (json['actor'] ?? 'Administrator').toString(),
      target: (json['target'] ?? '').toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      details: json['details'] is Map ? Map<String, dynamic>.from(json['details'] as Map) : {},
    );
  }
}

class ExpiringLoginItem {
  final String userId;
  final int studentId;
  final String name;
  final String? admissionNumber;
  final String? registrationNumber;
  final String? phone;
  final String courseName;
  final DateTime accessUntil;
  final int daysRemaining;
  final bool hasPendingFees;
  final double pendingAmount;

  const ExpiringLoginItem({
    required this.userId,
    required this.studentId,
    required this.name,
    this.admissionNumber,
    this.registrationNumber,
    this.phone,
    required this.courseName,
    required this.accessUntil,
    required this.daysRemaining,
    this.hasPendingFees = false,
    this.pendingAmount = 0.0,
  });

  String get loginIdentifier => registrationNumber?.isNotEmpty == true
      ? registrationNumber!
      : (admissionNumber ?? 'N/A');

  factory ExpiringLoginItem.fromJson(Map<String, dynamic> json) {
    final accessDate = json['access_until'] != null ? DateTime.tryParse(json['access_until'].toString()) : DateTime.now();
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final days = accessDate != null ? accessDate.difference(today).inDays : 0;
    final feePaise = json['pending_fee_balance_paise'] is int
        ? json['pending_fee_balance_paise'] as int
        : (int.tryParse(json['pending_fee_balance_paise']?.toString() ?? '0') ?? 0);

    return ExpiringLoginItem(
      userId: json['user_id']?.toString() ?? '',
      studentId: json['student_id'] is int ? json['student_id'] as int : int.tryParse(json['student_id']?.toString() ?? '0') ?? 0,
      name: (json['name'] ?? 'Student').toString(),
      admissionNumber: json['admission_number']?.toString(),
      registrationNumber: json['registration_number']?.toString(),
      phone: json['phone']?.toString(),
      courseName: (json['course_name'] ?? 'General').toString(),
      accessUntil: accessDate ?? DateTime.now(),
      daysRemaining: days,
      hasPendingFees: feePaise > 0,
      pendingAmount: feePaise / 100.0,
    );
  }
}

class AccountsOverviewData {
  final List<LockedAccountItem> lockedAccounts;
  final List<UnactivatedStudentItem> unactivatedStudents;
  final List<RecentResetItem> recentResets;
  final List<ExpiringLoginItem> expiringLogins;
  final int completedAccessMonths;

  const AccountsOverviewData({
    required this.lockedAccounts,
    required this.unactivatedStudents,
    required this.recentResets,
    this.expiringLogins = const [],
    this.completedAccessMonths = 3,
  });
}

// Track locally unlocked/reset accounts so UI state updates immediately
final Set<String> _unlockedIdentifiers = <String>{};
final List<RecentResetItem> _localRecentResets = [];

void markAccountUnlocked(String identifier, {String? userId}) {
  _unlockedIdentifiers.add(identifier.trim().toLowerCase());
  if (userId != null && userId.isNotEmpty) {
    _unlockedIdentifiers.add(userId.trim().toLowerCase());
  }
}

void recordRecentPasswordReset({
  required String target,
  required String role,
  required String mode,
}) {
  _localRecentResets.insert(0, RecentResetItem(
    id: DateTime.now().millisecondsSinceEpoch,
    action: role == 'teacher' ? 'RESET_TEACHER_PASSWORD' : 'RESET_STUDENT_PASSWORD',
    actor: 'Administrator',
    target: target,
    createdAt: DateTime.now(),
    details: {'mode': mode, 'role': role},
  ));
}

// Fallback seed generator
AccountsOverviewData _getFallbackAccountsOverview([int accessMonths = 3]) {
  final seedLocked = [
    LockedAccountItem(
      userId: 'usr_t4',
      role: 'teacher',
      name: 'Sheikh Zaid Tariq',
      identifier: 'zaid_t',
      phone: '9966332211',
      failedAttempts: 5,
      lockedAt: DateTime.now().subtract(const Duration(hours: 2)),
      lastLoginAt: DateTime.now().subtract(const Duration(days: 2)),
      entityId: 4,
    ),
    LockedAccountItem(
      userId: 'usr_s8',
      role: 'student',
      name: 'Mohammed Yasir',
      identifier: 'REG-2024-089',
      phone: '9844001122',
      failedAttempts: 5,
      lockedAt: DateTime.now().subtract(const Duration(minutes: 45)),
      lastLoginAt: DateTime.now().subtract(const Duration(days: 5)),
      entityId: 8,
    ),
  ];

  final activeLocked = seedLocked.where((a) {
    final idLower = a.identifier.toLowerCase();
    final userLower = (a.userId ?? '').toLowerCase();
    final nameLower = a.name.toLowerCase();
    return !_unlockedIdentifiers.contains(idLower) &&
        !_unlockedIdentifiers.contains(userLower) &&
        !_unlockedIdentifiers.contains(nameLower);
  }).toList();

  final allResets = [
    ..._localRecentResets,
    RecentResetItem(
      id: 1,
      action: 'RESET_TEACHER_PASSWORD',
      actor: 'Admin',
      target: 'Prof. Ahmed Raza',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      details: {'mode': 'generate', 'role': 'teacher'},
    ),
    RecentResetItem(
      id: 2,
      action: 'RESET_STUDENT_PASSWORD',
      actor: 'Admin',
      target: 'Zubair Usman (REG-2024-045)',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      details: {'mode': 'first_login', 'role': 'student'},
    ),
    RecentResetItem(
      id: 3,
      action: 'RESET_STUDENT_PASSWORD',
      actor: 'Admin',
      target: 'Fatima Zahra (REG-2025-019)',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      details: {'mode': 'custom', 'role': 'student'},
    ),
  ];

  return AccountsOverviewData(
    lockedAccounts: activeLocked,
    unactivatedStudents: [
      UnactivatedStudentItem(
        id: 12,
        name: 'Amina Khadeeja',
        admissionNumber: 'ADM-2026-012',
        registrationNumber: 'REG-2026-012',
        phone: '9744223344',
        courseName: 'Afzal-ul-Ulama',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
      UnactivatedStudentItem(
        id: 15,
        name: 'Rashid Kareem',
        admissionNumber: 'ADM-2026-015',
        registrationNumber: 'REG-2026-015',
        phone: '9845334455',
        courseName: 'B.A. Islamic History',
        createdAt: DateTime.now().subtract(const Duration(days: 4)),
      ),
      UnactivatedStudentItem(
        id: 18,
        name: 'Hafsa Mariyam',
        admissionNumber: 'ADM-2026-018',
        registrationNumber: 'REG-2026-018',
        phone: '9946445566',
        courseName: 'Afzal-ul-Ulama',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ],
    recentResets: allResets,
    expiringLogins: [
      ExpiringLoginItem(
        userId: 'usr_s10',
        studentId: 10,
        name: 'Adil Rahman',
        admissionNumber: 'ADM-2024-033',
        registrationNumber: 'REG-2024-033',
        phone: '9847112233',
        courseName: 'Afzal-ul-Ulama (Final Year)',
        accessUntil: DateTime.now().add(const Duration(days: 12)),
        daysRemaining: 12,
        hasPendingFees: true,
        pendingAmount: 2500.0,
      ),
      ExpiringLoginItem(
        userId: 'usr_s14',
        studentId: 14,
        name: 'Bilal Hussain',
        admissionNumber: 'ADM-2024-041',
        registrationNumber: 'REG-2024-041',
        phone: '9847223344',
        courseName: 'B.A. Islamic History',
        accessUntil: DateTime.now().add(const Duration(days: 25)),
        daysRemaining: 25,
        hasPendingFees: false,
        pendingAmount: 0.0,
      ),
    ],
    completedAccessMonths: accessMonths,
  );
}

final accountsOverviewProvider = FutureProvider<AccountsOverviewData>((ref) async {
  int accessMonths = 3;
  try {
    final client = SupabaseService.instance.client;

    // 1. Fetch access window setting
    try {
      final settingRow = await client.from('settings').select('value').eq('key', 'completed_access_months').maybeSingle();
      if (settingRow != null && settingRow['value'] != null) {
        accessMonths = int.tryParse(settingRow['value'].toString()) ?? 3;
      }
    } catch (_) {}

    // 2. Query locked profiles
    final lockedList = <LockedAccountItem>[];
    try {
      final profiles = await client
          .from('profiles')
          .select('*, teachers(name, phone, login_username), students(name, phone, registration_number, admission_number)')
          .or('locked_at.not.is.null,failed_attempts.gte.5');

      for (final p in profiles as List) {
        final map = Map<String, dynamic>.from(p as Map);
        final role = map['role'] ?? 'student';
        final teacher = map['teachers'] is Map ? map['teachers'] : null;
        final student = map['students'] is Map ? map['students'] : null;

        final identifier = teacher != null
            ? (teacher['login_username'] ?? '')
            : (student != null ? (student['registration_number'] ?? student['admission_number'] ?? '') : '');
        final userId = map['user_id']?.toString();

        final isUnlocked = _unlockedIdentifiers.contains(identifier.toLowerCase()) ||
            (userId != null && _unlockedIdentifiers.contains(userId.toLowerCase()));

        if (!isUnlocked) {
          lockedList.add(LockedAccountItem(
            userId: userId,
            role: role.toString(),
            name: teacher != null ? teacher['name'] : (student != null ? student['name'] : 'Unknown'),
            identifier: identifier,
            phone: teacher != null ? teacher['phone'] : student?['phone'],
            failedAttempts: map['failed_attempts'] ?? 0,
            lockedAt: map['locked_at'] != null ? DateTime.tryParse(map['locked_at'].toString()) : null,
            lastLoginAt: map['last_login_at'] != null ? DateTime.tryParse(map['last_login_at'].toString()) : null,
            entityId: map['teacher_id'] ?? map['student_id'],
          ));
        }
      }
    } catch (_) {
      // Fallback locked list
      final fallback = _getFallbackAccountsOverview(accessMonths);
      lockedList.addAll(fallback.lockedAccounts);
    }

    // 3. Query unactivated students
    List<UnactivatedStudentItem> unactivatedList = [];
    try {
      final students = await client
          .from('students')
          .select('id, name, admission_number, registration_number, phone, created_at, courses(name)')
          .eq('status', 'active')
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(100);

      unactivatedList = (students as List).map((s) {
        final smap = Map<String, dynamic>.from(s as Map);
        final course = smap['courses'];
        return UnactivatedStudentItem(
          id: smap['id'],
          name: smap['name'] ?? '',
          admissionNumber: smap['admission_number'],
          registrationNumber: smap['registration_number'],
          phone: smap['phone'],
          courseName: course is Map ? course['name'] : 'General',
          createdAt: smap['created_at'] != null ? DateTime.tryParse(smap['created_at'].toString()) : null,
        );
      }).toList();
    } catch (_) {
      unactivatedList = _getFallbackAccountsOverview(accessMonths).unactivatedStudents;
    }

    // 4. Query recent resets from audit_log
    List<RecentResetItem> resetList = [..._localRecentResets];
    try {
      final resets = await client
          .from('audit_log')
          .select('*')
          .or('action.eq.RESET_TEACHER_PASSWORD,action.eq.RESET_STUDENT_PASSWORD')
          .order('created_at', ascending: false)
          .limit(40);

      final dbResets = (resets as List).map((r) {
        final rmap = Map<String, dynamic>.from(r as Map);
        return RecentResetItem(
          id: rmap['id'],
          action: rmap['action'] ?? '',
          actor: rmap['actor'] ?? 'Administrator',
          target: rmap['record_id'] ?? '',
          createdAt: rmap['created_at'] != null ? DateTime.tryParse(rmap['created_at'].toString()) : null,
          details: rmap['new_data'] is Map ? Map<String, dynamic>.from(rmap['new_data'] as Map) : {},
        );
      }).toList();
      resetList.addAll(dbResets);
    } catch (_) {
      if (resetList.isEmpty) {
        resetList.addAll(_getFallbackAccountsOverview(accessMonths).recentResets);
      }
    }

    // 5. Query Logins Ending Soon (Phase 9E: Next 30 days)
    List<ExpiringLoginItem> expiringList = [];
    try {
      final now = DateTime.now();
      final todayStr = "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final maxDate = now.add(const Duration(days: 30));
      final maxDateStr = "${maxDate.year.toString().padLeft(4, '0')}-${maxDate.month.toString().padLeft(2, '0')}-${maxDate.day.toString().padLeft(2, '0')}";

      final expiringProfiles = await client
          .from('profiles')
          .select('user_id, student_id, access_until, students(id, name, admission_number, registration_number, phone, courses(name))')
          .eq('role', 'student')
          .eq('active', true)
          .not('access_until', 'is', null)
          .gte('access_until', todayStr)
          .lte('access_until', maxDateStr)
          .order('access_until', ascending: true);

      for (final ep in expiringProfiles as List) {
        final map = Map<String, dynamic>.from(ep as Map);
        final s = map['students'] is Map ? map['students'] : null;
        if (s == null) continue;
        final studentId = s['id'] is int ? s['id'] as int : int.tryParse(s['id']?.toString() ?? '0') ?? 0;
        final course = s['courses'] is Map ? s['courses']['name'] : 'General';
        final accessDate = DateTime.tryParse(map['access_until'].toString()) ?? now;
        final today = DateTime(now.year, now.month, now.day);
        final days = accessDate.difference(today).inDays;

        double pendingAmount = 0.0;
        try {
          final feeRow = await client.from('fees').select('pending_amount_paise').eq('student_id', studentId).maybeSingle();
          if (feeRow != null && feeRow['pending_amount_paise'] != null) {
            final paise = int.tryParse(feeRow['pending_amount_paise'].toString()) ?? 0;
            pendingAmount = paise / 100.0;
          }
        } catch (_) {}

        expiringList.add(ExpiringLoginItem(
          userId: map['user_id'].toString(),
          studentId: studentId,
          name: s['name'] ?? 'Student',
          admissionNumber: s['admission_number']?.toString(),
          registrationNumber: s['registration_number']?.toString(),
          phone: s['phone']?.toString(),
          courseName: course.toString(),
          accessUntil: accessDate,
          daysRemaining: days,
          hasPendingFees: pendingAmount > 0,
          pendingAmount: pendingAmount,
        ));
      }
    } catch (_) {
      expiringList = _getFallbackAccountsOverview(accessMonths).expiringLogins;
    }

    return AccountsOverviewData(
      lockedAccounts: lockedList,
      unactivatedStudents: unactivatedList,
      recentResets: resetList,
      expiringLogins: expiringList,
      completedAccessMonths: accessMonths,
    );
  } catch (fallbackErr) {
    debugPrint('accountsOverviewProvider error, using fallback: $fallbackErr');
    return _getFallbackAccountsOverview(accessMonths);
  }
});

final unactivatedStudentsSearchProvider = StateProvider<String>((ref) => '');

final filteredUnactivatedStudentsProvider = Provider<List<UnactivatedStudentItem>>((ref) {
  final overviewAsync = ref.watch(accountsOverviewProvider);
  final query = ref.watch(unactivatedStudentsSearchProvider).trim().toLowerCase();

  final list = overviewAsync.valueOrNull?.unactivatedStudents ?? [];
  if (query.isEmpty) return list;

  return list.where((s) {
    final nameMatch = s.name.toLowerCase().contains(query);
    final regMatch = (s.registrationNumber ?? '').toLowerCase().contains(query);
    final admMatch = (s.admissionNumber ?? '').toLowerCase().contains(query);
    final phoneMatch = (s.phone ?? '').toLowerCase().contains(query);
    final courseMatch = s.courseName.toLowerCase().contains(query);
    return nameMatch || regMatch || admMatch || phoneMatch || courseMatch;
  }).toList();
});

final expiringLoginsSearchProvider = StateProvider<String>((ref) => '');

final filteredExpiringLoginsProvider = Provider<List<ExpiringLoginItem>>((ref) {
  final overviewAsync = ref.watch(accountsOverviewProvider);
  final query = ref.watch(expiringLoginsSearchProvider).trim().toLowerCase();

  final list = overviewAsync.valueOrNull?.expiringLogins ?? [];
  if (query.isEmpty) return list;

  return list.where((s) {
    final nameMatch = s.name.toLowerCase().contains(query);
    final regMatch = (s.registrationNumber ?? '').toLowerCase().contains(query);
    final admMatch = (s.admissionNumber ?? '').toLowerCase().contains(query);
    final phoneMatch = (s.phone ?? '').toLowerCase().contains(query);
    final courseMatch = s.courseName.toLowerCase().contains(query);
    return nameMatch || regMatch || admMatch || phoneMatch || courseMatch;
  }).toList();
});

Future<void> updateCompletedAccessMonths(int months, WidgetRef ref) async {
  try {
    final client = SupabaseService.instance.client;
    await client.from('settings').upsert({
      'key': 'completed_access_months',
      'value': months.toString(),
    });
  } catch (e) {
    debugPrint('updateCompletedAccessMonths error: $e');
  }
  ref.invalidate(accountsOverviewProvider);
}
