class Fee {
  final int? id;
  final int studentId;
  final int totalFeePaise;
  final int paidAmountPaise;
  final int pendingAmountPaise;
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;

  double get totalFee => totalFeePaise / 100.0;
  double get paidAmount => paidAmountPaise / 100.0;
  double get pendingAmount => pendingAmountPaise / 100.0;

  Fee({
    this.id,
    required this.studentId,
    required this.totalFeePaise,
    required this.paidAmountPaise,
    required this.pendingAmountPaise,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'student_id': studentId,
      'total_fee_paise': totalFeePaise,
      'paid_amount_paise': paidAmountPaise,
      'pending_amount_paise': pendingAmountPaise,
      'total_fee': totalFee,
      'paid_amount': paidAmount,
      'pending_amount': pendingAmount,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
    };
  }

  factory Fee.fromMap(Map<String, dynamic> map) {
    final totP = (map['total_fee_paise'] as num?)?.toInt() ??
        (((map['total_fee'] as num?)?.toDouble() ?? 0.0) * 100).toInt();

    final paidP = (map['paid_amount_paise'] as num?)?.toInt() ??
        (((map['paid_amount'] as num?)?.toDouble() ?? 0.0) * 100).toInt();

    final pendP = (map['pending_amount_paise'] as num?)?.toInt() ??
        (((map['pending_amount'] as num?)?.toDouble() ?? 0.0) * 100).toInt();

    return Fee(
      id: (map['id'] as num?)?.toInt(),
      studentId: (map['student_id'] as num).toInt(),
      totalFeePaise: totP,
      paidAmountPaise: paidP,
      pendingAmountPaise: pendP,
      createdAt: map['created_at']?.toString(),
      updatedAt: map['updated_at']?.toString(),
      deletedAt: map['deleted_at']?.toString(),
    );
  }
}
