// lib/core/models/fee_item.dart

class FeeItem {
  final int id;
  final int studentId;
  final int? enrollmentId;
  final String label;
  final int amountPaise;
  final int paidAmountPaise;
  final String? dueDate;
  final String status; // 'unpaid', 'partially_paid', 'paid'
  final String? createdAt;

  FeeItem({
    required this.id,
    required this.studentId,
    this.enrollmentId,
    required this.label,
    required this.amountPaise,
    this.paidAmountPaise = 0,
    this.dueDate,
    this.status = 'unpaid',
    this.createdAt,
  });

  double get amount => amountPaise / 100.0;
  double get paidAmount => paidAmountPaise / 100.0;
  int get pendingPaise => (amountPaise - paidAmountPaise).clamp(0, amountPaise);
  double get pendingAmount => pendingPaise / 100.0;

  factory FeeItem.fromMap(Map<String, dynamic> map) {
    return FeeItem(
      id: map['id'] is int ? map['id'] : int.parse(map['id'].toString()),
      studentId: map['student_id'] is int ? map['student_id'] : int.parse(map['student_id'].toString()),
      enrollmentId: map['enrollment_id'] != null
          ? (map['enrollment_id'] is int ? map['enrollment_id'] : int.tryParse(map['enrollment_id'].toString()))
          : null,
      label: map['label'] ?? '',
      amountPaise: map['amount_paise'] is int ? map['amount_paise'] : int.tryParse(map['amount_paise']?.toString() ?? '0') ?? 0,
      paidAmountPaise: map['paid_amount_paise'] is int ? map['paid_amount_paise'] : int.tryParse(map['paid_amount_paise']?.toString() ?? '0') ?? 0,
      dueDate: map['due_date']?.toString(),
      status: map['status'] ?? 'unpaid',
      createdAt: map['created_at']?.toString(),
    );
  }
}
