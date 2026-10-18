import '../../models/batch.dart';

abstract class BatchRepository {
  Future<List<Batch>> getBatches({
    int? courseId,
    bool includeDeleted = false,
    bool includeCompleted = false,
  });

  Future<Batch?> getBatchById(int id);

  Future<Batch> createBatch(Batch batch);

  Future<Batch> updateBatch(Batch batch);

  Future<void> deleteBatch(int id);

  Future<List<Map<String, dynamic>>> previewBatchCompletion(int batchId);

  Future<Map<String, dynamic>> completeBatch(
    int batchId, {
    DateTime? completedOn,
    List<int>? excludedStudentIds,
    DateTime? accessUntilOverride,
    bool closeLoginsNow = false,
  });

  Future<Map<String, dynamic>> reopenBatch(int batchId, {required String reason});

  // Phase 12B: Semester Promotion & Semester Dates Management
  Future<Map<String, dynamic>> previewSemesterPromotion(int batchId);

  Future<Map<String, dynamic>> promoteSemester(
    int batchId,
    DateTime closingEndDate,
    DateTime newStartDate,
  );

  Future<List<Map<String, dynamic>>> getBatchSemesters(int batchId);

  Future<Map<String, dynamic>> updateBatchSemesterDates(
    int batchId,
    int semesterNo,
    DateTime startDate,
    DateTime? endDate,
    String? reason,
  );
}
