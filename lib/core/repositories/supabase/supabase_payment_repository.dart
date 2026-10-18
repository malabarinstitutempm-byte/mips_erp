import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/payment.dart';
import '../../models/receipt.dart';
import '../../services/supabase_service.dart';
import '../interfaces/payment_repository_interface.dart';

class SupabasePaymentRepository implements PaymentRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  @override
  Future<Payment> recordPayment({
    required int studentId,
    required int amountPaise,
    required String paymentMode,
    String? referenceNumber,
    String? remarks,
  }) async {
    SupabaseService.instance.assertCanWrite('record payment');

    if (amountPaise <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }

    final modeClean = paymentMode.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
    final validMode = (modeClean == 'cash' || modeClean == 'upi' || modeClean == 'bank_transfer' || modeClean == 'cheque')
        ? modeClean
        : 'other';

    final res = await _client.rpc('record_payment', params: {
      'p_student_id': studentId,
      'p_amount_paise': amountPaise,
      'p_mode': validMode,
      'p_reference': referenceNumber,
      'p_remarks': remarks,
    });

    final resMap = Map<String, dynamic>.from(res as Map);
    final paymentId = resMap['payment_id'] as int;

    // Fetch the created payment record
    final data = await _client
        .from('payments')
        .select('*')
        .eq('id', paymentId)
        .single();

    return Payment.fromMap(Map<String, dynamic>.from(data));
  }

  @override
  Future<void> cancelPayment({
    required int paymentId,
    required String reason,
  }) async {
    SupabaseService.instance.assertCanWrite('cancel payment');

    if (reason.trim().isEmpty) {
      throw ArgumentError('A mandatory cancellation reason must be provided.');
    }

    await _client.rpc('cancel_payment', params: {
      'p_payment_id': paymentId,
      'p_reason': reason.trim(),
    });
  }

  @override
  Future<List<Payment>> getPaymentsForStudent(int studentId) async {
    final data = await _client
        .from('payments')
        .select('*')
        .eq('student_id', studentId)
        .order('id', ascending: false);

    return (data as List).map((row) => Payment.fromMap(Map<String, dynamic>.from(row))).toList();
  }

  @override
  Future<Receipt?> getReceiptByPaymentId(int paymentId) async {
    final data = await _client
        .from('receipts')
        .select('*')
        .eq('payment_id', paymentId)
        .maybeSingle();

    if (data == null) return null;
    return Receipt.fromMap(Map<String, dynamic>.from(data));
  }
}
