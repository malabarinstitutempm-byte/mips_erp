import '../../models/exam.dart';
import '../../models/mark.dart';
import '../../models/subject.dart';

abstract class ExamRepository {
  Future<List<Exam>> getExams({int? courseId, int? batchId, int? academicYearId});

  Future<Exam?> getExamById(int id);

  Future<Exam> createExam(Exam exam, List<Subject> subjects);

  Future<int> addExam(Exam exam);

  Future<int> addSubject(Subject subject);

  Future<Exam> updateExam(Exam exam, List<Subject> subjects);

  Future<void> deleteExam(int id);

  Future<List<Subject>> getExamSubjects(int examId);

  Future<List<Subject>> getSubjects(int examId);

  Future<int> publishExam(int id);

  Future<void> publishResults(int id);

  Future<void> unpublishExam(int id);

  Future<void> saveMarks(List<Mark> marks);
}
