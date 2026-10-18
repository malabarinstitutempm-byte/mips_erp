import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/models/student.dart';
import '../../core/models/payment.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_card.dart';
import '../fees/fees_provider.dart';
import '../fees/collect_payment_dialog.dart';
import '../fees/receipt_pdf_generator.dart';
import '../settings/settings_provider.dart';

class StudentFeesTab extends ConsumerWidget {
  final Student student;
  const StudentFeesTab({super.key, required this.student});

  Future<void> _printPaymentReceipt(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> p,
    Map<String, dynamic>? details, {
    required bool isThermal,
  }) async {
    try {
      final receiptNo = p['receipt']?.toString();
      final effectiveReceiptNo = (receiptNo != null && receiptNo.isNotEmpty)
          ? receiptNo
          : 'MIPS/${DateTime.now().year}/${p['id'].toString().padLeft(4, '0')}';

      final amountDouble = (p['amount'] as num?)?.toDouble() ?? 0.0;
      final amountPaise = (amountDouble * 100).round();

      final paymentObj = Payment(
        id: p['id'] as int?,
        studentId: student.id!,
        amountPaise: amountPaise,
        paymentMode: p['payment_mode']?.toString() ?? 'Cash',
        referenceNumber: p['ref']?.toString(),
        date: p['date']?.toString() ?? DateTime.now().toIso8601String(),
      );

      final settings = await ref.read(settingsRepositoryProvider).getAllSettings();

      await ReceiptPdfGenerator.printReceipt(
        student: student,
        payment: paymentObj,
        receiptNumber: effectiveReceiptNo,
        settings: settings,
        courseName: details?['course_name']?.toString(),
        isThermal: isThermal,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating receipt: $e')),
        );
      }
    }
  }

  void _confirmCancelPayment(BuildContext context, WidgetRef ref, Map<String, dynamic> p) {
    final formKey = GlobalKey<FormState>();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: AppColors.danger.base, size: 22),
            const SizedBox(width: 10),
            const Text('Cancel Payment?'),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to cancel payment of ₹${p['amount']} (Receipt: ${p['receipt'] ?? 'N/A'})?\n\nThis will reverse the fee balance and mark the receipt as void.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cancellation Reason (Mandatory)',
                    hintText: 'e.g., Cheque bounce, wrong entry, refunded',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'A cancellation reason is strictly required.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Go Back'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger.base,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);

              try {
                final paymentId = p['id'] as int;
                await ref.read(paymentRepositoryProvider).cancelPayment(
                  paymentId: paymentId,
                  reason: reasonCtrl.text.trim(),
                );

                ref.invalidate(studentFeeDetailsProvider(student.id!));
                ref.invalidate(studentPaymentsProvider(student.id!));
                ref.invalidate(pendingFeesProvider);
                ref.invalidate(recentPaymentsProvider);
                ref.invalidate(feeMetricsProvider);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Payment cancelled successfully.'),
                      backgroundColor: AppColors.danger.base,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to cancel payment: $e'),
                      backgroundColor: AppColors.danger.base,
                    ),
                  );
                }
              }
            },
            child: const Text('Confirm Cancellation'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(studentFeeDetailsProvider(student.id!));
    final paymentsAsync = ref.watch(studentPaymentsProvider(student.id!));
    final format = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs.');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Fee Details & Installments
        Expanded(
          flex: 2,
          child: Column(
            children: [
              detailsAsync.when(
                data: (details) {
                  final pending = (details['pending'] as num?)?.toDouble() ?? 0.0;
                  return SectionCard(
                    title: 'Fee Summary',
                    trailing: pending > 0
                        ? ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandDark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            icon: const Icon(LucideIcons.plusCircle, size: 16),
                            label: const Text('Collect Payment'),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => CollectPaymentDialog(
                                  student: student,
                                  pendingAmount: pending,
                                ),
                              ).then((_) {
                                ref.invalidate(studentFeeDetailsProvider(student.id!));
                                ref.invalidate(studentPaymentsProvider(student.id!));
                                ref.invalidate(pendingFeesProvider);
                                ref.invalidate(recentPaymentsProvider);
                                ref.invalidate(feeMetricsProvider);
                              });
                            },
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStat('Total Fee', format.format(details['total'] ?? 0), AppColors.textBody),
                              _buildStat('Paid Amount', format.format(details['paid'] ?? 0), AppColors.success.base),
                              _buildStat('Pending Amount', format.format(details['pending'] ?? 0), AppColors.danger.base),
                            ],
                          ),
                          if (details['has_skill'] == true) ...[
                            const SizedBox(height: AppSpacing.md),
                            const Divider(height: 1),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.courses.tint,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.courses.base.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Primary Course', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.courses.dark)),
                                        const SizedBox(height: 4),
                                        Text('Total: ${format.format(details['primary_total'] ?? 0)}', style: const TextStyle(fontSize: 11)),
                                        Text('Paid: ${format.format(details['primary_paid'] ?? 0)}', style: const TextStyle(fontSize: 11, color: Colors.green)),
                                        Text('Pending: ${format.format(details['primary_pending'] ?? 0)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: (details['primary_pending'] as num? ?? 0) > 0 ? Colors.red : Colors.green)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.purple.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Skill Course', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.purple)),
                                        const SizedBox(height: 4),
                                        Text('Total: ${format.format(details['skill_total'] ?? 0)}', style: const TextStyle(fontSize: 11)),
                                        Text('Paid: ${format.format(details['skill_paid'] ?? 0)}', style: const TextStyle(fontSize: 11, color: Colors.green)),
                                        Text('Pending: ${format.format(details['skill_pending'] ?? 0)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: (details['skill_pending'] as num? ?? 0) > 0 ? Colors.red : Colors.green)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => const Center(child: Text('Failed to load fee details')),
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Text('Fee Items & Course Ledger', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: detailsAsync.when(
                          data: (details) {
                            final rawItems = details['fee_items'] as List<dynamic>? ?? [];
                            if (rawItems.isNotEmpty) {
                              return ListView.separated(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                itemCount: rawItems.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, idx) {
                                  final item = rawItems[idx] as Map<String, dynamic>;
                                  final label = item['label']?.toString() ?? 'Fee Item';
                                  final amount = ((item['amount_paise'] as num?)?.toDouble() ?? 0.0) / 100.0;
                                  final paid = ((item['paid_amount_paise'] as num?)?.toDouble() ?? 0.0) / 100.0;
                                  final pending = (amount - paid).clamp(0.0, amount);
                                  final status = item['status']?.toString() ?? 'unpaid';

                                  return Container(
                                    padding: const EdgeInsets.all(AppSpacing.md),
                                    decoration: BoxDecoration(
                                      color: AppColors.bg,
                                      borderRadius: BorderRadius.circular(AppRadius.card),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppColors.brandDark.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Icon(
                                            label.toLowerCase().contains('skill') ? LucideIcons.sparkles : LucideIcons.graduationCap,
                                            color: label.toLowerCase().contains('skill') ? Colors.purple : AppColors.brandDark,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.md),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                              const SizedBox(height: 2),
                                              Text('Paid: ${format.format(paid)} • Pending: ${format.format(pending)}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(format.format(amount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: status == 'paid'
                                                    ? AppColors.success.tint
                                                    : (status == 'partially_paid' ? Colors.amber.shade50 : AppColors.danger.tint),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                status == 'paid' ? 'PAID' : (status == 'partially_paid' ? 'PARTIAL' : 'UNPAID'),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: status == 'paid'
                                                      ? AppColors.success.base
                                                      : (status == 'partially_paid' ? Colors.amber.shade800 : AppColors.danger.base),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            }

                            final courseName = details['course_name']?.toString() ?? 'Course Tuition Fee';
                            final total = (details['total'] as num?)?.toDouble() ?? 0.0;
                            final paid = (details['paid'] as num?)?.toDouble() ?? 0.0;
                            final pending = (details['pending'] as num?)?.toDouble() ?? 0.0;
                            final status = pending <= 0 && total > 0 ? 'paid' : (paid > 0 ? 'partial' : 'pending');

                            return ListView(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.lg),
                                  decoration: BoxDecoration(
                                    color: AppColors.bg,
                                    borderRadius: BorderRadius.circular(AppRadius.card),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: AppColors.brandDark.withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(LucideIcons.graduationCap, color: AppColors.brandDark, size: 24),
                                      ),
                                      const SizedBox(width: AppSpacing.lg),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              courseName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textStrong),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Enrolled Program Total Course Tuition',
                                              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            format.format(total),
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textStrong),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: status == 'paid'
                                                  ? AppColors.success.tint
                                                  : (status == 'partial' ? Colors.amber.shade50 : AppColors.danger.tint),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              status == 'paid' ? 'FULLY PAID' : (status == 'partial' ? 'PARTIALLY PAID' : 'PENDING'),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: status == 'paid'
                                                    ? AppColors.success.base
                                                    : (status == 'partial' ? Colors.amber.shade800 : AppColors.danger.base),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                          loading: () => const SizedBox(),
                          error: (_, __) => const SizedBox(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xl),

        // Right Column: Payment History
        Expanded(
          flex: 1,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('Payment History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: paymentsAsync.when(
                    data: (payments) {
                      if (payments.isEmpty) {
                        return EmptyState(
                          icon: LucideIcons.indianRupee,
                          title: 'No payments made yet',
                          message: 'No recorded payments for this student.',
                        );
                      }
                      return ListView.separated(
                        itemCount: payments.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final p = payments[index];
                          final isCancelled = p['is_cancelled'] == 1;
                          final date = p['date']?.toString() ?? '';
                          final mode = p['payment_mode']?.toString() ?? 'Cash';
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isCancelled ? AppColors.danger.tint : AppColors.success.tint,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isCancelled ? LucideIcons.xCircle : LucideIcons.checkCircle,
                                size: 16,
                                color: isCancelled ? AppColors.danger.dark : AppColors.success.dark,
                              ),
                            ),
                            title: Text(
                              format.format(p['amount'] ?? 0.0),
                              style: TextStyle(
                                decoration: isCancelled ? TextDecoration.lineThrough : null,
                                color: isCancelled ? AppColors.textMuted : AppColors.textStrong,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              isCancelled
                                  ? '$date - CANCELLED (${p['cancel_reason'] ?? 'Void'})'
                                  : '$date - $mode (Receipt: ${p['receipt'] ?? 'N/A'})',
                              style: TextStyle(
                                fontSize: 12,
                                color: isCancelled ? AppColors.danger.base : AppColors.textMuted,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isCancelled) ...[
                                  PopupMenuButton<String>(
                                    tooltip: 'Print Receipt',
                                    icon: const Icon(LucideIcons.printer, size: 18),
                                    onSelected: (type) async {
                                      final isThermal = (type == 'thermal');
                                      await _printPaymentReceipt(
                                        context,
                                        ref,
                                        p,
                                        detailsAsync.valueOrNull,
                                        isThermal: isThermal,
                                      );
                                    },
                                    itemBuilder: (ctx) => const [
                                      PopupMenuItem(value: 'a4', child: Text('Print A4 Receipt (Standard)')),
                                      PopupMenuItem(value: 'thermal', child: Text('Print Thermal Receipt (80mm POS)')),
                                    ],
                                  ),
                                  IconButton(
                                    icon: Icon(LucideIcons.ban, size: 17, color: AppColors.danger.base),
                                    tooltip: 'Cancel Payment',
                                    onPressed: () => _confirmCancelPayment(context, ref, p),
                                  ),
                                ] else ...[
                                  Tooltip(
                                    message: 'Cancelled: ${p['cancel_reason'] ?? 'Voided'}',
                                    child: const Icon(LucideIcons.info, size: 18, color: AppColors.textMuted),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, st) => const Center(child: Text('Failed to load history')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
