class FeesFallbackStore {
  static final List<Map<String, dynamic>> pendingFees = [];
  static final List<Map<String, dynamic>> recentPayments = [];

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
