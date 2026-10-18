import '../../models/result.dart';

abstract class ResultRepository {
  Future<List<Result>> getResultsForExam(int examId);

  Future<void> computeResults(int examId);

  Future<List<Result>> getStudentResults(int studentId);
}
