class Teacher {
  final int id;
  final String name;
  final String? phone;
  final String loginUsername;
  final String status; // 'active' | 'inactive'
  final DateTime? deactivatedAt;
  final String? deactivatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Linked Profile info
  final String? userId;
  final bool profileActive;
  final DateTime? lockedAt;
  final int failedAttempts;
  final DateTime? lastLoginAt;

  // Session Statistics
  final int sessionsMarkedCount;

  const Teacher({
    required this.id,
    required this.name,
    this.phone,
    required this.loginUsername,
    this.status = 'active',
    this.deactivatedAt,
    this.deactivatedBy,
    this.createdAt,
    this.updatedAt,
    this.userId,
    this.profileActive = true,
    this.lockedAt,
    this.failedAttempts = 0,
    this.lastLoginAt,
    this.sessionsMarkedCount = 0,
  });

  bool get isLocked => lockedAt != null;

  String get effectiveStatus {
    if (isLocked) return 'Locked';
    if (status == 'inactive' || !profileActive) return 'Inactive';
    return 'Active';
  }

  factory Teacher.fromJson(Map<String, dynamic> json) {
    // Resolve profile if joined
    Map<String, dynamic>? profile;
    if (json['profiles'] != null) {
      if (json['profiles'] is List && (json['profiles'] as List).isNotEmpty) {
        profile = Map<String, dynamic>.from(json['profiles'][0] as Map);
      } else if (json['profiles'] is Map) {
        profile = Map<String, dynamic>.from(json['profiles'] as Map);
      }
    }

    return Teacher(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: (json['name'] ?? '').toString(),
      phone: json['phone']?.toString(),
      loginUsername: (json['login_username'] ?? '').toString(),
      status: (json['status'] ?? 'active').toString().toLowerCase(),
      deactivatedAt: json['deactivated_at'] != null ? DateTime.tryParse(json['deactivated_at'].toString()) : null,
      deactivatedBy: json['deactivated_by']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      userId: profile?['user_id']?.toString() ?? json['user_id']?.toString(),
      profileActive: profile?['active'] == null ? (json['status'] == 'active') : (profile!['active'] == true),
      lockedAt: profile?['locked_at'] != null ? DateTime.tryParse(profile!['locked_at'].toString()) : null,
      failedAttempts: profile?['failed_attempts'] is int
          ? profile!['failed_attempts'] as int
          : (int.tryParse(profile?['failed_attempts']?.toString() ?? '0') ?? 0),
      lastLoginAt: profile?['last_login_at'] != null
          ? DateTime.tryParse(profile!['last_login_at'].toString())
          : (json['last_login_at'] != null ? DateTime.tryParse(json['last_login_at'].toString()) : null),
      sessionsMarkedCount: json['sessions_marked_count'] is int
          ? json['sessions_marked_count'] as int
          : (int.tryParse(json['sessions_marked_count']?.toString() ?? '0') ?? 0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'login_username': loginUsername,
      'status': status,
      'deactivated_at': deactivatedAt?.toIso8601String(),
      'deactivated_by': deactivatedBy,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'user_id': userId,
      'profile_active': profileActive,
      'locked_at': lockedAt?.toIso8601String(),
      'failed_attempts': failedAttempts,
      'last_login_at': lastLoginAt?.toIso8601String(),
      'sessions_marked_count': sessionsMarkedCount,
    };
  }

  Teacher copyWith({
    int? id,
    String? name,
    String? phone,
    String? loginUsername,
    String? status,
    DateTime? deactivatedAt,
    String? deactivatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? userId,
    bool? profileActive,
    DateTime? lockedAt,
    int? failedAttempts,
    DateTime? lastLoginAt,
    int? sessionsMarkedCount,
  }) {
    return Teacher(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      loginUsername: loginUsername ?? this.loginUsername,
      status: status ?? this.status,
      deactivatedAt: deactivatedAt ?? this.deactivatedAt,
      deactivatedBy: deactivatedBy ?? this.deactivatedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      userId: userId ?? this.userId,
      profileActive: profileActive ?? this.profileActive,
      lockedAt: lockedAt ?? this.lockedAt,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      sessionsMarkedCount: sessionsMarkedCount ?? this.sessionsMarkedCount,
    );
  }
}
