import '../../models/payment.dart';
import '../../models/receipt.dart';

abstract class PaymentRepository {
  Future<Payment> recordPayment({
    required int studentId,
    required int amountPaise,
    required String paymentMode,
    String? referenceNumber,
    String? remarks,
  });

  Future<void> cancelPayment({
    required int paymentId,
    required String reason,
  });

  Future<List<Payment>> getPaymentsForStudent(int studentId);

  Future<Receipt?> getReceiptByPaymentId(int paymentId);
}
