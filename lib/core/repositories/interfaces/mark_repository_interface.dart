import '../../models/mark.dart';

abstract class MarkRepository {
  Future<List<Mark>> getMarksForExam(int examId);

  Future<void> saveMarks({
    required int examId,
    required List<Mark> marks,
  });
}
