abstract class ReportRepository {
  Future<Map<String, dynamic>> getDashboardKPIs();

  Future<List<Map<String, dynamic>>> getFeeCollectionReport({
    DateTime? from,
    DateTime? to,
    String? paymentMode,
  });

  Future<List<Map<String, dynamic>>> getCourseRevenueReport();

  Future<List<Map<String, dynamic>>> getDefaultersReport({
    int? courseId,
    int? batchId,
  });

  Future<List<Map<String, dynamic>>> getMeritList({
    int? examId,
    int? courseId,
    int? batchId,
    int limit = 50,
  });

  Future<List<Map<String, dynamic>>> getStudentList({
    int? courseId,
    int? batchId,
    String? status,
  });
}
