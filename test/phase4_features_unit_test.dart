// test/phase4_features_unit_test.dart
// Unit tests for Phase 4 calculations: Attendance Percentage, Band Boundaries,
// can_miss_more, recover_sessions, and FIFO Payment Allocation.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

/// Helper model replicating Attendance Summary calculation logic
class AttendanceCalculator {
  static Map<String, dynamic> calculate({
    required int sessionsHeld,
    required int present,
    required int lateCount,
    required int absent,
    required int leave,
    double lateWeight = 0.5,
    String leaveHandling = 'excluded', // 'excluded', 'absent', 'present'
    double minPercent = 75.0,
    double reminderPercent = 80.0,
  }) {
    int effectiveHeld = sessionsHeld;
    if (leaveHandling == 'excluded') {
      effectiveHeld = max(0, sessionsHeld - leave);
    }

    double weightedPresent = present + (lateCount * lateWeight);
    if (leaveHandling == 'present') {
      weightedPresent += leave;
    }

    double percentage = 100.0;
    if (effectiveHeld > 0) {
      percentage = (weightedPresent / effectiveHeld) * 100.0;
      percentage = double.parse(percentage.toStringAsFixed(2));
    }

    String band = 'ok';
    if (percentage > reminderPercent) {
      band = 'ok';
    } else if (percentage >= minPercent) {
      band = 'low';
    } else {
      band = 'shortage';
    }

    int canMissMore = 0;
    if (minPercent > 0 && percentage >= minPercent) {
      canMissMore = max(0, ((weightedPresent / (minPercent / 100.0)) - effectiveHeld).floor());
    }

    int recoverSessions = 0;
    if (percentage < minPercent && minPercent < 100.0) {
      final needed = ((minPercent / 100.0 * effectiveHeld) - weightedPresent) / (1.0 - (minPercent / 100.0));
      recoverSessions = max(0, needed.ceil());
    }

    return {
      'effectiveHeld': effectiveHeld,
      'weightedPresent': weightedPresent,
      'percentage': percentage,
      'band': band,
      'canMissMore': canMissMore,
      'recoverSessions': recoverSessions,
    };
  }
}

/// Helper model replicating FIFO Payment Allocation
class FeeItemLedger {
  final int id;
  final String label;
  final int amountPaise;
  int paidAmountPaise;
  final DateTime dueDate;

  FeeItemLedger({
    required this.id,
    required this.label,
    required this.amountPaise,
    this.paidAmountPaise = 0,
    required this.dueDate,
  });

  int get pendingPaise => max(0, amountPaise - paidAmountPaise);
  bool get isPaid => pendingPaise == 0;
}

class PaymentAllocator {
  static List<Map<String, dynamic>> allocateFifo({
    required List<FeeItemLedger> items,
    required int paymentAmountPaise,
  }) {
    // Sort items by due date ASC, then id ASC
    final sorted = List<FeeItemLedger>.from(items)
      ..sort((a, b) {
        final cmp = a.dueDate.compareTo(b.dueDate);
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      });

    int remaining = paymentAmountPaise;
    final allocations = <Map<String, dynamic>>[];

    for (final item in sorted) {
      if (item.pendingPaise <= 0) continue;
      final alloc = min(remaining, item.pendingPaise);
      item.paidAmountPaise += alloc;
      allocations.add({
        'feeItemId': item.id,
        'amountPaise': alloc,
      });
      remaining -= alloc;
      if (remaining <= 0) break;
    }

    if (remaining > 0) {
      throw StateError('Overpayment: $remaining paise could not be allocated.');
    }

    return allocations;
  }

  static void reverseAllocation({
    required List<FeeItemLedger> items,
    required List<Map<String, dynamic>> allocations,
  }) {
    for (final alloc in allocations) {
      final itemId = alloc['feeItemId'] as int;
      final amount = alloc['amountPaise'] as int;
      final item = items.firstWhere((i) => i.id == itemId);
      item.paidAmountPaise = max(0, item.paidAmountPaise - amount);
    }
  }
}

void main() {
  group('Sub-phase 4C: Attendance Percentage Maths & Edge Cases', () {
    test('Standard attendance: 8 present, 2 late out of 10 held sessions', () {
      final res = AttendanceCalculator.calculate(
        sessionsHeld: 10,
        present: 8,
        lateCount: 2,
        absent: 0,
        leave: 0,
        lateWeight: 0.5,
      );

      expect(res['effectiveHeld'], 10);
      expect(res['weightedPresent'], 9.0);
      expect(res['percentage'], 90.0);
      expect(res['band'], 'ok');
      // can_miss_more = floor(9.0 / 0.75 - 10) = floor(12 - 10) = 2
      expect(res['canMissMore'], 2);
      expect(res['recoverSessions'], 0);
    });

    test('Leave excluded handling: 10 held, 1 leave, 7 present, 1 late, 1 absent', () {
      final res = AttendanceCalculator.calculate(
        sessionsHeld: 10,
        present: 7,
        lateCount: 1,
        absent: 1,
        leave: 1,
        leaveHandling: 'excluded',
        lateWeight: 0.5,
      );

      // Leave is excluded from total held (10 - 1 = 9)
      expect(res['effectiveHeld'], 9);
      expect(res['weightedPresent'], 7.5);
      // 7.5 / 9 * 100 = 83.33%
      expect(res['percentage'], 83.33);
      expect(res['band'], 'ok');
      // can_miss_more: floor(7.5 / 0.75 - 9) = floor(10 - 9) = 1
      expect(res['canMissMore'], 1);
    });

    test('Exact boundary at 80.00% triggers low band', () {
      // 8 present out of 10 held = exactly 80.00%
      final res = AttendanceCalculator.calculate(
        sessionsHeld: 10,
        present: 8,
        lateCount: 0,
        absent: 2,
        leave: 0,
      );

      expect(res['percentage'], 80.0);
      // > 80 is ok; 80 or below shows low band
      expect(res['band'], 'low');
    });

    test('Exact boundary at 75.00% triggers low band with 0 can_miss_more', () {
      // 7.5 weighted out of 10 held = 75.00%
      final res = AttendanceCalculator.calculate(
        sessionsHeld: 10,
        present: 7,
        lateCount: 1,
        absent: 2,
        leave: 0,
        lateWeight: 0.5,
      );

      expect(res['percentage'], 75.0);
      expect(res['band'], 'low');
      expect(res['canMissMore'], 0);
      expect(res['recoverSessions'], 0);
    });

    test('Shortage boundary at 74.90% triggers shortage with accurate recovery count', () {
      // 11 held, 7.5 weighted: 7.5 / 11 * 100 = 68.18%
      final res = AttendanceCalculator.calculate(
        sessionsHeld: 11,
        present: 7,
        lateCount: 1,
        absent: 3,
        leave: 0,
        lateWeight: 0.5,
      );

      expect(res['percentage'], 68.18);
      expect(res['band'], 'shortage');
      expect(res['canMissMore'], 0);
      // ceil((0.75 * 11 - 7.5) / (1 - 0.75)) = ceil((8.25 - 7.5) / 0.25) = ceil(0.75 / 0.25) = 3
      expect(res['recoverSessions'], 3);

      // Verify recovery: if student attends 3 full sessions present:
      // (7.5 + 3) / (11 + 3) = 10.5 / 14 = 75.00%!
      final verified = AttendanceCalculator.calculate(
        sessionsHeld: 14,
        present: 10,
        lateCount: 1,
        absent: 3,
        leave: 0,
        lateWeight: 0.5,
      );
      expect(verified['percentage'], 75.0);
    });

    test('Zero sessions held defaults to 100% ok', () {
      final res = AttendanceCalculator.calculate(
        sessionsHeld: 0,
        present: 0,
        lateCount: 0,
        absent: 0,
        leave: 0,
      );

      expect(res['percentage'], 100.0);
      expect(res['band'], 'ok');
      expect(res['canMissMore'], 0);
      expect(res['recoverSessions'], 0);
    });
  });

  group('Sub-phase 4C: FIFO Payment Allocation & Cancellation', () {
    test('FIFO allocation pays earlier due date first and splits across items', () {
      final itemPrimary = FeeItemLedger(
        id: 1,
        label: 'Primary Tuition',
        amountPaise: 5000000, // 50,000 INR
        dueDate: DateTime(2026, 9, 1),
      );
      final itemSkill = FeeItemLedger(
        id: 2,
        label: 'Skill Course Fee',
        amountPaise: 2000000, // 20,000 INR
        dueDate: DateTime(2026, 10, 1),
      );

      final items = [itemPrimary, itemSkill];

      // Pay 60,000 INR (6,000,000 paise)
      final allocations = PaymentAllocator.allocateFifo(
        items: items,
        paymentAmountPaise: 6000000,
      );

      expect(allocations.length, 2);
      expect(allocations[0]['feeItemId'], 1);
      expect(allocations[0]['amountPaise'], 5000000); // Fully paid primary
      expect(allocations[1]['feeItemId'], 2);
      expect(allocations[1]['amountPaise'], 1000000); // Partially paid skill

      expect(itemPrimary.isPaid, true);
      expect(itemPrimary.pendingPaise, 0);
      expect(itemSkill.isPaid, false);
      expect(itemSkill.pendingPaise, 1000000); // 10,000 INR remaining

      // Test reversal
      PaymentAllocator.reverseAllocation(items: items, allocations: allocations);
      expect(itemPrimary.paidAmountAmountOrZero(), 0);
      expect(itemSkill.paidAmountAmountOrZero(), 0);
      expect(itemPrimary.pendingPaise, 5000000);
      expect(itemSkill.pendingPaise, 2000000);
    });

    test('Overpayment throws error', () {
      final item = FeeItemLedger(
        id: 1,
        label: 'Tuition',
        amountPaise: 1000000,
        dueDate: DateTime(2026, 9, 1),
      );

      expect(
        () => PaymentAllocator.allocateFifo(items: [item], paymentAmountPaise: 1500000),
        throwsA(isA<StateError>()),
      );
    });
  });
}

extension on FeeItemLedger {
  int paidAmountAmountOrZero() => paidAmountPaise;
}
