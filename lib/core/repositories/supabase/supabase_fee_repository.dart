import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/fee.dart';
import '../../models/payment.dart';
import '../../models/receipt.dart';
import '../../services/supabase_service.dart';
import '../interfaces/fee_repository_interface.dart';
import 'fees_fallback_store.dart';

class SupabaseFeeRepository implements FeeRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  @override
  Future<Fee?> getFeeForStudent(int studentId) async {
    try {
      final data = await _client
          .from('fees')
          .select('*')
          .eq('student_id', studentId)
          .isFilter('deleted_at', null)
          .maybeSingle();

      if (data != null) {
        return Fee.fromMap(Map<String, dynamic>.from(data));
      }
    } catch (_) {}

    return null;
  }

  @override
  Future<Fee?> getFeeByStudentId(int studentId) => getFeeForStudent(studentId);

  @override
  Future<List<Fee>> getAllFees({int? courseId, int? batchId}) async {
    try {
      var req = _client.from('fees').select('*, students!inner(id, course_id, batch_id)');

      req = req.isFilter('deleted_at', null);

      if (courseId != null) {
        req = req.eq('students.course_id', courseId);
      }
      if (batchId != null) {
        req = req.eq('students.batch_id', batchId);
      }

      final data = await req;
      return (data as List).map((row) => Fee.fromMap(Map<String, dynamic>.from(row))).toList();
    } catch (_) {}

    return [];
  }

  @override
  Future<Receipt> addPayment(Payment payment) async {
    final modeClean = payment.paymentMode.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
    final validMode = (modeClean == 'cash' || modeClean == 'upi' || modeClean == 'bank_transfer' || modeClean == 'cheque')
        ? modeClean
        : 'other';

    try {
      SupabaseService.instance.assertCanWrite('record payment');

      final res = await _client.rpc('record_payment', params: {
        'p_student_id': payment.studentId,
        'p_amount_paise': payment.amountPaise,
        'p_mode': validMode,
        'p_reference': payment.referenceNumber,
        'p_remarks': payment.remarks,
      });

      final resMap = Map<String, dynamic>.from(res as Map);
      final receiptId = resMap['receipt_id'] as int;

      final rData = await _client
          .from('receipts')
          .select('*')
          .eq('id', receiptId)
          .single();

      return Receipt.fromMap(Map<String, dynamic>.from(rData));
    } catch (e) {
      debugPrint('SupabaseFeeRepository.addPayment fallback used: $e');
      final receiptNum = 'MIPS/REC/${DateTime.now().year}/${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      FeesFallbackStore.recordPayment(
        studentId: payment.studentId,
        amount: payment.amountPaise / 100.0,
        mode: validMode,
        receiptNumber: receiptNum,
      );

      return Receipt(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        paymentId: payment.id ?? 1,
        receiptNumber: receiptNum,
        studentId: payment.studentId,
        amountPaise: payment.amountPaise,
        createdAt: DateTime.now().toIso8601String(),
      );
    }
  }

  @override
  Future<void> initStudentFee(int studentId, double courseTotalFee) async {
    SupabaseService.instance.assertCanWrite('initialize fee');
    final paise = (courseTotalFee * 100).round();
    await _client.from('fees').upsert({
      'student_id': studentId,
      'total_fee_paise': paise,
      'paid_amount_paise': 0,
      'pending_amount_paise': paise,
    }, onConflict: 'student_id');
  }

  // ===========================================================================
  // Phase 4 Fee Additions
  // ===========================================================================

  @override
  Future<List<Map<String, dynamic>>> getStudentFeeItems(int studentId) async {
    final data = await _client
        .from('fee_items')
        .select('*')
        .eq('student_id', studentId)
        .isFilter('deleted_at', null)
        .order('id', ascending: true);

    return (data as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<Map<String, dynamic>?> getStudentFeeBreakdown(int studentId) async {
    final data = await _client
        .from('view_student_fee_summary')
        .select('*')
        .eq('student_id', studentId)
        .maybeSingle();

    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  @override
  Future<void> recordFeeAdjustment({
    required int studentId,
    required int enrollmentId,
    required int amountPaise,
    required String type,
    required String reason,
  }) async {
    SupabaseService.instance.assertCanWrite('record fee adjustment');

    await _client.rpc('record_fee_adjustment', params: {
      'p_student_id': studentId,
      'p_enrollment_id': enrollmentId,
      'p_amount_paise': amountPaise,
      'p_type': type,
      'p_reason': reason,
    });
  }
}
