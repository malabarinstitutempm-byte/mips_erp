import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/student.dart';
import '../../core/models/payment.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'fees_provider.dart';

class CollectPaymentDialog extends ConsumerStatefulWidget {
  final Student student;
  final double pendingAmount;

  const CollectPaymentDialog({super.key, required this.student, required this.pendingAmount});

  @override
  ConsumerState<CollectPaymentDialog> createState() => _CollectPaymentDialogState();
}

class _CollectPaymentDialogState extends ConsumerState<CollectPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  String _mode = 'Cash';
  final _refCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  bool _isLoading = false;

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amountDouble = double.tryParse(_amountCtrl.text) ?? 0.0;
    if (amountDouble <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Amount must be positive.')));
      return;
    }

    if (amountDouble > widget.pendingAmount) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot overpay! Maximum allowed is the pending amount.')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final payment = Payment(
        studentId: widget.student.id!,
        amountPaise: (amountDouble * 100).round(),
        paymentMode: _mode,
        referenceNumber: _refCtrl.text,
        remarks: _remarksCtrl.text,
        date: DateTime.now().toIso8601String(),
      );

      final repo = ref.read(feeRepositoryProvider);
      await repo.addPayment(payment);

      if (mounted) {
        ref.invalidate(pendingFeesProvider);
        ref.invalidate(recentPaymentsProvider);
        ref.invalidate(feeMetricsProvider);
        ref.invalidate(studentPaymentsProvider(widget.student.id!));
        ref.invalidate(studentFeeDetailsProvider(widget.student.id!));

        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment collected successfully.')));
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Payment failed: $msg'),
          backgroundColor: AppColors.danger.base,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Collect Payment: ${widget.student.name}'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pending Amount: ₹${widget.pendingAmount.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.danger.base)),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount (₹)', border: OutlineInputBorder()),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final val = double.tryParse(v);
                  if (val == null || val <= 0) return 'Invalid amount';
                  if (val > widget.pendingAmount) return 'Cannot exceed pending amount';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                value: _mode,
                decoration: const InputDecoration(labelText: 'Payment Mode', border: OutlineInputBorder()),
                items: ['Cash', 'Bank Transfer', 'UPI', 'Cheque'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setState(() => _mode = v!),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_mode != 'Cash')
                TextFormField(
                  controller: _refCtrl,
                  decoration: const InputDecoration(labelText: 'Transaction Reference', border: OutlineInputBorder()),
                  validator: (v) => v == null || v.isEmpty ? 'Reference required for $_mode' : null,
                ),
              if (_mode != 'Cash') const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _remarksCtrl,
                decoration: const InputDecoration(labelText: 'Remarks (Optional)', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit'),
        ),
      ],
    );
  }
}
