class GradingScheme {
  final int? id;
  final double minPercent;
  final double maxPercent;
  final String grade;
  final bool isPass;

  GradingScheme({
    this.id,
    required this.minPercent,
    required this.maxPercent,
    required this.grade,
    this.isPass = true,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'min_percent': minPercent,
      'max_percent': maxPercent,
      'grade': grade,
      'is_pass': isPass,
    };
  }

  factory GradingScheme.fromMap(Map<String, dynamic> map) {
    final rawPass = map['is_pass'];
    final pass = rawPass is bool ? rawPass : (rawPass == 1 || rawPass == '1');

    return GradingScheme(
      id: (map['id'] as num?)?.toInt(),
      minPercent: (map['min_percent'] as num).toDouble(),
      maxPercent: (map['max_percent'] as num).toDouble(),
      grade: map['grade'].toString(),
      isPass: pass,
    );
  }

  GradingScheme copyWith({
    int? id,
    double? minPercent,
    double? maxPercent,
    String? grade,
    bool? isPass,
  }) {
    return GradingScheme(
      id: id ?? this.id,
      minPercent: minPercent ?? this.minPercent,
      maxPercent: maxPercent ?? this.maxPercent,
      grade: grade ?? this.grade,
      isPass: isPass ?? this.isPass,
    );
  }
}
