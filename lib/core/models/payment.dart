class Payment {
  final int? id;
  final int studentId;
  final int amountPaise;
  final String paymentMode;
  final String? referenceNumber;
  final String? remarks;
  final String date;
  final int? receiptId;
  final bool isCancelled;
  final String? cancelReason;
  final String? cancelledAt;
  final String? cancelledBy;
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;
  final bool isDeleted;

  double get amount => amountPaise / 100.0;

  Payment({
    this.id,
    required this.studentId,
    required this.amountPaise,
    required this.paymentMode,
    this.referenceNumber,
    this.remarks,
    required this.date,
    this.receiptId,
    this.isCancelled = false,
    this.cancelReason,
    this.cancelledAt,
    this.cancelledBy,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'student_id': studentId,
      'amount_paise': amountPaise,
      'payment_mode': paymentMode,
      if (referenceNumber != null) 'reference': referenceNumber,
      if (referenceNumber != null) 'reference_number': referenceNumber,
      if (remarks != null) 'remarks': remarks,
      'date': date,
      if (receiptId != null) 'receipt_id': receiptId,
      'cancelled': isCancelled,
      'is_cancelled': isCancelled ? 1 : 0,
      if (cancelReason != null) 'cancel_reason': cancelReason,
      if (cancelledAt != null) 'cancelled_at': cancelledAt,
      if (cancelledBy != null) 'cancelled_by': cancelledBy,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    final amtP = (map['amount_paise'] as num?)?.toInt() ??
        (((map['amount'] as num?)?.toDouble() ?? 0.0) * 100).toInt();

    final isCanc = map['cancelled'] == true ||
        map['is_cancelled'] == true ||
        map['is_cancelled'] == 1;

    final isDel = map['deleted_at'] != null ||
        map['is_deleted'] == 1 ||
        map['is_deleted'] == true;

    return Payment(
      id: (map['id'] as num?)?.toInt(),
      studentId: (map['student_id'] as num).toInt(),
      amountPaise: amtP,
      paymentMode: (map['payment_mode'] ?? map['mode'] ?? 'cash').toString(),
      referenceNumber: (map['reference'] ?? map['reference_number'])?.toString(),
      remarks: map['remarks']?.toString(),
      date: (map['date'] ?? map['created_at'] ?? DateTime.now().toIso8601String()).toString().split('T')[0],
      receiptId: (map['receipt_id'] as num?)?.toInt(),
      isCancelled: isCanc,
      cancelReason: map['cancel_reason']?.toString(),
      cancelledAt: map['cancelled_at']?.toString(),
      cancelledBy: map['cancelled_by']?.toString(),
      createdAt: map['created_at']?.toString(),
      updatedAt: map['updated_at']?.toString(),
      deletedAt: map['deleted_at']?.toString(),
      isDeleted: isDel,
    );
  }
}
