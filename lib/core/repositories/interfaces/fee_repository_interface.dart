import '../../models/fee.dart';

import '../../models/payment.dart';
import '../../models/receipt.dart';

abstract class FeeRepository {
  Future<Fee?> getFeeForStudent(int studentId);

  Future<Fee?> getFeeByStudentId(int studentId);

  Future<List<Fee>> getAllFees({int? courseId, int? batchId});

  Future<Receipt> addPayment(Payment payment);

  Future<void> initStudentFee(int studentId, double courseTotalFee);

  // Phase 4 additions:
  Future<List<Map<String, dynamic>>> getStudentFeeItems(int studentId);

  Future<Map<String, dynamic>?> getStudentFeeBreakdown(int studentId);

  Future<void> recordFeeAdjustment({
    required int studentId,
    required int enrollmentId,
    required int amountPaise,
    required String type,
    required String reason,
  });
}
