class AuditLog {
  final int? id;
  final String action;
  final String tableName;
  final String recordId;
  final String? oldValue;
  final String? newValue;
  final int? userId;
  final String createdAt;

  AuditLog({
    this.id,
    required this.action,
    required this.tableName,
    required this.recordId,
    this.oldValue,
    this.newValue,
    this.userId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'action': action,
      'table_name': tableName,
      'record_id': recordId,
      'old_value': oldValue,
      'new_value': newValue,
      'user_id': userId,
      'created_at': createdAt,
    };
  }

  factory AuditLog.fromMap(Map<String, dynamic> map) {
    return AuditLog(
      id: map['id'],
      action: map['action'],
      tableName: map['table_name'],
      recordId: map['record_id'].toString(),
      oldValue: map['old_value'],
      newValue: map['new_value'],
      userId: map['user_id'],
      createdAt: map['created_at'],
    );
  }
}
