class Subject {
  final int? id;
  final int examId;
  final String name;
  final String? code;
  final double maxMarks;
  final double passMarks;
  final double? theoryMarks;
  final double? practicalMarks;
  final int displayOrder;

  Subject({
    this.id,
    required this.examId,
    required this.name,
    this.code,
    required this.maxMarks,
    required this.passMarks,
    this.theoryMarks,
    this.practicalMarks,
    this.displayOrder = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'exam_id': examId,
      'name': name,
      if (code != null) 'code': code,
      'max_marks': maxMarks,
      'pass_marks': passMarks,
      if (theoryMarks != null) 'theory_marks': theoryMarks,
      if (practicalMarks != null) 'practical_marks': practicalMarks,
      'display_order': displayOrder,
    };
  }

  factory Subject.fromMap(Map<String, dynamic> map) {
    return Subject(
      id: (map['id'] as num?)?.toInt(),
      examId: (map['exam_id'] as num).toInt(),
      name: (map['name'] ?? '').toString(),
      code: map['code']?.toString(),
      maxMarks: (map['max_marks'] as num?)?.toDouble() ?? 100.0,
      passMarks: (map['pass_marks'] as num?)?.toDouble() ?? 40.0,
      theoryMarks: (map['theory_marks'] as num?)?.toDouble(),
      practicalMarks: (map['practical_marks'] as num?)?.toDouble(),
      displayOrder: (map['display_order'] as num?)?.toInt() ?? 0,
    );
  }
}
