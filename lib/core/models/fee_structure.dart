class FeeStructure {
  final int? id;
  final int courseId;
  final int academicYearId;
  final int feeHeadId;
  final int amountPaise;

  FeeStructure({this.id, required this.courseId, required this.academicYearId, required this.feeHeadId, this.amountPaise = 0});

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'course_id': courseId,
    'academic_year_id': academicYearId,
    'fee_head_id': feeHeadId,
    'amount_paise': amountPaise,
  };

  factory FeeStructure.fromMap(Map<String, dynamic> map) => FeeStructure(
    id: map['id'],
    courseId: map['course_id'] is int ? map['course_id'] : int.parse(map['course_id'].toString()),
    academicYearId: map['academic_year_id'] is int ? map['academic_year_id'] : int.parse(map['academic_year_id'].toString()),
    feeHeadId: map['fee_head_id'] is int ? map['fee_head_id'] : int.parse(map['fee_head_id'].toString()),
    amountPaise: map['amount_paise'] is int ? map['amount_paise'] : int.parse(map['amount_paise'].toString()),
  );
}
