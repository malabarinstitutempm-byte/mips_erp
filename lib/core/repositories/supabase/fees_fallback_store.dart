class FeesFallbackStore {
  static final List<Map<String, dynamic>> pendingFees = [
    {
      'id': 1,
      'name': 'Mohammed Hamiz',
      'adm': '2023MLT042',
      'course': 'Diploma in Medical Laboratory Technology [DMLT]',
      'total': 50000.0,
      'paid': 35000.0,
      'pending': 15000.0,
    },
    {
      'id': 2,
      'name': 'Amina Fathima',
      'adm': '2024MLT015',
      'course': 'Diploma in Medical Laboratory Technology [DMLT]',
      'total': 50000.0,
      'paid': 25000.0,
      'pending': 25000.0,
    },
    {
      'id': 3,
      'name': 'Rahul Varma',
      'adm': '2024OTA008',
      'course': 'Diploma in Operation Theatre & Anaesthesia Technology [DOTAT]',
      'total': 55000.0,
      'paid': 30000.0,
      'pending': 25000.0,
    },
    {
      'id': 4,
      'name': 'Sneha Krishna',
      'adm': '2024DXT012',
      'course': 'Diploma in X-Ray Technology [DXT]',
      'total': 50000.0,
      'paid': 30000.0,
      'pending': 20000.0,
    },
    {
      'id': 5,
      'name': 'Anas Bilal',
      'adm': '2023BML003',
      'course': 'B.Sc Medical Laboratory Technology [B.Sc MLT]',
      'total': 120000.0,
      'paid': 80000.0,
      'pending': 40000.0,
    },
  ];

  static final List<Map<String, dynamic>> recentPayments = [
    {
      'id': 1,
      'name': 'Mohammed Hamiz',
      'amount': 15000.0,
      'mode': 'UPI',
      'date': '2026-03-12',
      'receipt': 'MIPS/REC/2026/0142',
      'is_cancelled': 0,
    },
    {
      'id': 2,
      'name': 'Amina Fathima',
      'amount': 10000.0,
      'mode': 'BANK_TRANSFER',
      'date': '2026-03-10',
      'receipt': 'MIPS/REC/2026/0141',
      'is_cancelled': 0,
    },
    {
      'id': 3,
      'name': 'Rahul Varma',
      'amount': 20000.0,
      'mode': 'CASH',
      'date': '2026-03-08',
      'receipt': 'MIPS/REC/2026/0140',
      'is_cancelled': 0,
    },
    {
      'id': 4,
      'name': 'Sneha Krishna',
      'amount': 15000.0,
      'mode': 'UPI',
      'date': '2026-03-05',
      'receipt': 'MIPS/REC/2026/0139',
      'is_cancelled': 0,
    },
    {
      'id': 5,
      'name': 'Anas Bilal',
      'amount': 30000.0,
      'mode': 'CHEQUE',
      'date': '2026-03-01',
      'receipt': 'MIPS/REC/2026/0138',
      'is_cancelled': 0,
    },
  ];

  static void recordPayment({
    required int studentId,
    required double amount,
    required String mode,
    required String receiptNumber,
  }) {
    // 1. Update pending amount
    String studentName = 'Student #$studentId';
    final idx = pendingFees.indexWhere((s) => s['id'] == studentId);
    if (idx != -1) {
      final item = Map<String, dynamic>.from(pendingFees[idx]);
      studentName = item['name']?.toString() ?? studentName;
      final currentPaid = (item['paid'] as num?)?.toDouble() ?? 0.0;
      final currentPending = (item['pending'] as num?)?.toDouble() ?? 0.0;
      final newPaid = currentPaid + amount;
      final newPending = (currentPending - amount).clamp(0.0, double.infinity);
      item['paid'] = newPaid;
      item['pending'] = newPending;
      if (newPending <= 0) {
        pendingFees.removeAt(idx);
      } else {
        pendingFees[idx] = item;
      }
    }

    // 2. Add to recent payments list
    final newId = recentPayments.length + 1;
    recentPayments.insert(0, {
      'id': newId,
      'name': studentName,
      'amount': amount,
      'mode': mode.toUpperCase(),
      'date': DateTime.now().toIso8601String().split('T')[0],
      'receipt': receiptNumber,
      'is_cancelled': 0,
    });
  }

  static Map<String, double> getMetrics() {
    double total = 0;
    double collected = 0;
    double pending = 0;
    for (final s in pendingFees) {
      total += (s['total'] as num?)?.toDouble() ?? 0.0;
      collected += (s['paid'] as num?)?.toDouble() ?? 0.0;
      pending += (s['pending'] as num?)?.toDouble() ?? 0.0;
    }
    return {
      'total': total > 0 ? total + 1800000.0 : 2480000.0,
      'collected': collected > 0 ? collected + 1800000.0 : 1840000.0,
      'pending': pending > 0 ? pending : 640000.0,
    };
  }
}
