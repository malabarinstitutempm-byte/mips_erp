class StudentFee {
  final int? id;
  final int studentId;
  final int feeHeadId;
  final int amountPaise;
  final String? dueDate;
  final int discountPaise;
  final int finePaise;
  final String status;

  StudentFee({this.id, required this.studentId, required this.feeHeadId, this.amountPaise = 0, this.dueDate, this.discountPaise = 0, this.finePaise = 0, this.status = 'pending'});

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'student_id': studentId,
    'fee_head_id': feeHeadId,
    'amount_paise': amountPaise,
    'due_date': dueDate,
    'discount_paise': discountPaise,
    'fine_paise': finePaise,
    'status': status,
  };

  factory StudentFee.fromMap(Map<String, dynamic> map) => StudentFee(
    id: map['id'],
    studentId: map['student_id'] is int ? map['student_id'] : int.parse(map['student_id'].toString()),
    feeHeadId: map['fee_head_id'] is int ? map['fee_head_id'] : int.parse(map['fee_head_id'].toString()),
    amountPaise: map['amount_paise'] is int ? map['amount_paise'] : int.parse(map['amount_paise'].toString()),
    dueDate: map['due_date'],
    discountPaise: map['discount_paise'] is int ? map['discount_paise'] : int.parse(map['discount_paise'].toString()),
    finePaise: map['fine_paise'] is int ? map['fine_paise'] : int.parse(map['fine_paise'].toString()),
    status: map['status'] ?? 'pending',
  );
}
