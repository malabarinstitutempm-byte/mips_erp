import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../database_helper.dart';
import '../../core/models/fee.dart';
import '../../core/models/payment.dart';
import '../../core/models/receipt.dart';

class FeeRepository {
  SupabaseClient get _supabase => SupabaseConfig.client;
  Future<Database> get _localDb async => await DatabaseHelper.instance.database;

  Future<Fee?> getFeeByStudentId(int studentId) async {
    try {
      final res = await _supabase
          .from('fees')
          .select()
          .eq('student_id', studentId)
          .isFilter('deleted_at', null)
          .maybeSingle();

      if (res != null) {
        return Fee.fromMap(res);
      }

      // If missing in fees table, resolve from enrolled course
      final studentRes = await _supabase
          .from('students')
          .select('course_id, courses(total_fee_paise)')
          .eq('id', studentId)
          .maybeSingle();

      if (studentRes != null && studentRes['courses'] != null) {
        final totalPaise = (studentRes['courses']['total_fee_paise'] as num?)?.toInt() ?? 0;

        // Fetch sum of paid payments
        final payRes = await _supabase
            .from('payments')
            .select('amount_paise')
            .eq('student_id', studentId)
            .eq('is_cancelled', false)
            .isFilter('deleted_at', null);

        int paidPaise = 0;
        for (final row in payRes) {
          paidPaise += (row['amount_paise'] as num?)?.toInt() ?? 0;
        }

        final pendingPaise = totalPaise > paidPaise ? (totalPaise - paidPaise) : 0;

        final newFee = {
          'student_id': studentId,
          'total_fee_paise': totalPaise,
          'paid_amount_paise': paidPaise,
          'pending_amount_paise': pendingPaise,
        };

        final inserted = await _supabase
            .from('fees')
            .insert(newFee)
            .select()
            .single();

        return Fee.fromMap(inserted);
      }

      return null;
    } catch (_) {
      // Offline fallback: SQLite
      final db = await _localDb;
      final maps = await db.query(
        'fees',
        where: 'student_id = ? AND is_deleted = 0',
        whereArgs: [studentId],
      );
      if (maps.isNotEmpty) {
        return Fee.fromMap(maps.first);
      }
      return null;
    }
  }

  Future<void> initStudentFee(int studentId, double courseTotalFee, [int? courseTotalFeePaise]) async {
    final paise = courseTotalFeePaise ?? (courseTotalFee * 100).round();

    try {
      final existing = await _supabase
          .from('fees')
          .select('id')
          .eq('student_id', studentId)
          .isFilter('deleted_at', null)
          .maybeSingle();

      if (existing == null) {
        await _supabase.from('fees').insert({
          'student_id': studentId,
          'total_fee_paise': paise,
          'paid_amount_paise': 0,
          'pending_amount_paise': paise,
        });
      }
    } catch (_) {
      final db = await _localDb;
      final existing = await getFeeByStudentId(studentId);
      if (existing == null) {
        final fee = Fee(
          studentId: studentId,
          totalFeePaise: paise,
          paidAmountPaise: 0,
          pendingAmountPaise: paise,
        );
        await db.insert('fees', fee.toMap());
      }
    }
  }

  Future<List<Payment>> getPayments(int studentId) async {
    try {
      final res = await _supabase
          .from('payments')
          .select('*, receipts(id, receipt_number)')
          .eq('student_id', studentId)
          .isFilter('deleted_at', null)
          .order('date', ascending: false)
          .order('id', ascending: false);

      final list = <Payment>[];
      for (final item in (res as List)) {
        final map = Map<String, dynamic>.from(item as Map);
        if (map['receipts'] != null && (map['receipts'] as List).isNotEmpty) {
          final firstReceipt = (map['receipts'] as List).first as Map;
          map['receipt_id'] = firstReceipt['id'];
        }
        list.add(Payment.fromMap(map));
      }
      return list;
    } catch (_) {
      final db = await _localDb;
      final maps = await db.query(
        'payments',
        where: 'student_id = ? AND is_deleted = 0',
        whereArgs: [studentId],
        orderBy: 'date DESC',
      );
      return maps.map((e) => Payment.fromMap(e)).toList();
    }
  }

  Future<Receipt> addPayment(Payment payment) async {
    final amtPaise = payment.amountPaise > 0
        ? payment.amountPaise
        : (payment.amount * 100).round();

    final mode = payment.paymentMode.trim().toLowerCase();
    final validMode = ['cash', 'upi', 'bank_transfer', 'cheque', 'other'].contains(mode)
        ? mode
        : 'other';

    try {
      // Call transactional server function record_payment
      final rpcRes = await _supabase.rpc('record_payment', params: {
        'p_student_id': payment.studentId,
        'p_amount_paise': amtPaise,
        'p_payment_mode': validMode,
        'p_reference': payment.referenceNumber,
        'p_remarks': payment.remarks,
      });

      final receiptData = rpcRes as Map<String, dynamic>;
      final receiptId = receiptData['receipt_id'] is int
          ? receiptData['receipt_id'] as int
          : int.parse(receiptData['receipt_id'].toString());
      final paymentId = receiptData['payment_id'] is int
          ? receiptData['payment_id'] as int
          : int.parse(receiptData['payment_id'].toString());
      final receiptNumber = receiptData['receipt_number'].toString();

      final receipt = Receipt(
        id: receiptId,
        paymentId: paymentId,
        receiptNumber: receiptNumber,
      );

      // Local sync for offline receipts
      try {
        final localDb = await _localDb;
        final localPay = payment.toMap();
        localPay['id'] = paymentId;
        localPay['amount_paise'] = amtPaise;
        localPay['receipt_id'] = receiptId;
        await localDb.insert('payments', localPay, conflictAlgorithm: ConflictAlgorithm.replace);

        final localRec = receipt.toMap();
        await localDb.insert('receipts', localRec, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}

      return receipt;
    } catch (e) {
      // Re-throw if error was overpayment rejection so UI can display specific message
      if (e.toString().contains('Payment exceeds total fee obligation')) {
        rethrow;
      }

      // Offline fallback: local transaction
      final db = await _localDb;
      return await db.transaction((txn) async {
        final map = payment.toMap();
        map['created_at'] = DateTime.now().toIso8601String();
        final paymentId = await txn.insert('payments', map);

        final receiptNumber = 'REC-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase()}';
        final receipt = Receipt(
          paymentId: paymentId,
          receiptNumber: receiptNumber,
        );
        final receiptId = await txn.insert('receipts', receipt.toMap());
        await txn.update('payments', {'receipt_id': receiptId}, where: 'id = ?', whereArgs: [paymentId]);

        return Receipt(
          id: receiptId,
          paymentId: paymentId,
          receiptNumber: receiptNumber,
        );
      });
    }
  }

  Future<void> cancelPayment(int paymentId, String reason) async {
    try {
      await _supabase.rpc('cancel_payment', params: {
        'p_payment_id': paymentId,
        'p_reason': reason,
      });

      try {
        final localDb = await _localDb;
        await localDb.update(
          'payments',
          {
            'is_cancelled': 1,
            'cancel_reason': reason,
            'cancelled_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [paymentId],
        );
      } catch (_) {}
    } catch (_) {
      final db = await _localDb;
      await db.update(
        'payments',
        {
          'is_cancelled': 1,
          'cancel_reason': reason,
          'cancelled_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [paymentId],
      );
    }
  }
}
