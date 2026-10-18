class Receipt {
  final int? id;
  final int paymentId;
  final String receiptNumber;
  final int? studentId;
  final int? amountPaise;
  final String? filePath;
  final String? createdAt;

  Receipt({
    this.id,
    required this.paymentId,
    required this.receiptNumber,
    this.studentId,
    this.amountPaise,
    this.filePath,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'payment_id': paymentId,
      'receipt_number': receiptNumber,
      if (studentId != null) 'student_id': studentId,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (filePath != null) 'file_path': filePath,
      if (createdAt != null) 'created_at': createdAt,
    };
  }

  factory Receipt.fromMap(Map<String, dynamic> map) {
    return Receipt(
      id: (map['id'] as num?)?.toInt(),
      paymentId: (map['payment_id'] as num).toInt(),
      receiptNumber: (map['receipt_number'] ?? '').toString(),
      studentId: (map['student_id'] as num?)?.toInt(),
      amountPaise: (map['amount_paise'] as num?)?.toInt(),
      filePath: map['file_path']?.toString(),
      createdAt: map['created_at']?.toString(),
    );
  }
}
