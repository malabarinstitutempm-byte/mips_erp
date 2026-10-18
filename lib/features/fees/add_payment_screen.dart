import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../core/models/student.dart';
import '../../core/models/payment.dart';
import '../../core/theme/app_theme.dart';
import '../../features/settings/settings_provider.dart';
import 'fee_provider.dart';
import 'receipt_pdf_generator.dart';

class AddPaymentScreen extends ConsumerStatefulWidget {
  final Student student;
  const AddPaymentScreen({super.key, required this.student});

  @override
  ConsumerState<AddPaymentScreen> createState() => _AddPaymentScreenState();
}

class _AddPaymentScreenState extends ConsumerState<AddPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _modeCtrl = TextEditingController(text: 'Cash');
  final _refCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  
  bool _isProcessing = false;

  void _submitPayment(double pending) async {
    if (_formKey.currentState!.validate()) {
      final amount = double.tryParse(_amountCtrl.text) ?? 0.0;
      
      if (amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Amount must be greater than 0.')));
        return;
      }
      
      if (amount > pending) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Warning: Overpayment'),
            content: Text('The entered amount (₹$amount) is greater than the pending fee (₹$pending). Do you want to proceed?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Proceed')),
            ],
          ),
        );
        if (proceed != true) return;
      }

      setState(() => _isProcessing = true);

      final payment = Payment(
        studentId: widget.student.id!,
        amountPaise: (amount * 100).round(),
        paymentMode: _modeCtrl.text,
        referenceNumber: _refCtrl.text,
        remarks: _remarksCtrl.text,
        date: DateTime.now().toIso8601String(),
      );

      try {
        final receipt = await ref.read(feeRepositoryProvider).addPayment(payment);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Successful! Receipt: ${receipt.receiptNumber}'),
              backgroundColor: AppTheme.success,
            )
          );
          ref.invalidate(feeDetailsProvider(widget.student.id!));
          ref.invalidate(paymentHistoryProvider(widget.student.id!));
          _amountCtrl.clear();
          _refCtrl.clear();
          _remarksCtrl.clear();
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final feeAsync = ref.watch(feeDetailsProvider(widget.student.id!));
    final historyAsync = ref.watch(paymentHistoryProvider(widget.student.id!));

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Manage Fees', style: Theme.of(context).textTheme.displayMedium),
                    const SizedBox(height: 4),
                    Text('${widget.student.name} (${widget.student.admissionNumber ?? ''})', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Fee Summary & Payment Form
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(48.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        feeAsync.when(
                          data: (fee) {
                            if (fee == null) {
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    children: [
                                      const Text('Fee structure not initialized for this student.'),
                                      const SizedBox(height: 16),
                                      ElevatedButton(
                                        onPressed: () async {
                                          await ref.read(feeRepositoryProvider).initStudentFee(widget.student.id!, 50000.0);
                                          ref.invalidate(feeDetailsProvider(widget.student.id!));
                                        },
                                        child: const Text('Initialize Fee structure'),
                                      )
                                    ],
                                  ),
                                ),
                              );
                            }
                            
                            return Row(
                              children: [
                                Expanded(child: _buildStatCard('Total Fee', fee.totalFee, AppTheme.info)),
                                const SizedBox(width: 16),
                                Expanded(child: _buildStatCard('Paid Amount', fee.paidAmount, AppTheme.success)),
                                const SizedBox(width: 16),
                                Expanded(child: _buildStatCard('Pending', fee.pendingAmount, fee.pendingAmount > 0 ? AppTheme.error : AppTheme.success)),
                              ],
                            );
                          },
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, s) => Text('Error: $e'),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Payment Form
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Record New Payment', style: Theme.of(context).textTheme.titleLarge),
                                  const SizedBox(height: 24),
                                  
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Amount (₹)', style: _labelStyle(context)),
                                            const SizedBox(height: 8),
                                            TextFormField(
                                              controller: _amountCtrl,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(hintText: '0.00'),
                                              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Payment Mode', style: _labelStyle(context)),
                                            const SizedBox(height: 8),
                                            DropdownButtonFormField<String>(
                                              value: _modeCtrl.text,
                                              decoration: const InputDecoration(hintText: 'Select mode'),
                                              items: ['Cash', 'Bank Transfer', 'UPI', 'Cheque']
                                                .map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                                              onChanged: (v) => setState(() => _modeCtrl.text = v!),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 24),
                                  
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Reference Number (Optional)', style: _labelStyle(context)),
                                            const SizedBox(height: 8),
                                            TextFormField(
                                              controller: _refCtrl,
                                              decoration: const InputDecoration(hintText: 'Txn ID / Cheque No'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Remarks (Optional)', style: _labelStyle(context)),
                                            const SizedBox(height: 8),
                                            TextFormField(
                                              controller: _remarksCtrl,
                                              decoration: const InputDecoration(hintText: 'Additional details'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 32),
                                  
                                  feeAsync.when(
                                    data: (fee) {
                                      final pending = fee?.pendingAmount ?? 0.0;
                                      return SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: _isProcessing || fee == null ? null : () => _submitPayment(pending),
                                          icon: _isProcessing 
                                              ? const SizedBox(width:20, height:20, child: CircularProgressIndicator(color: Colors.white, strokeWidth:2))
                                              : Icon(Icons.payment),
                                          label: Text(_isProcessing ? 'Processing...' : 'Submit Payment'),
                                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
                                        ),
                                      );
                                    },
                                    loading: () => const SizedBox.shrink(),
                                    error: (_,__) => const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Right Column: Payment History
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppTheme.surface,
                      border: Border(left: BorderSide(color: AppTheme.border)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text('Payment History', style: Theme.of(context).textTheme.titleLarge),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: historyAsync.when(
                            data: (payments) {
                              if (payments.isEmpty) {
                                return const Center(child: Text('No payments recorded yet.'));
                              }
                              return ListView.separated(
                                itemCount: payments.length,
                                separatorBuilder: (_,__) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final p = payments[index];
                                  final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(p.date));
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                    title: Text('₹${p.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text('Receipt: ${p.id} • ${p.paymentMode}'),
                                        Text(dateStr, style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: Icon(Icons.print, color: AppTheme.primaryColor),
                                      tooltip: 'Print Receipt',
                                      onPressed: () => _printReceipt(context, ref, p),
                                    ),
                                  );
                                },
                              );
                            },
                            loading: () => const Center(child: CircularProgressIndicator()),
                            error: (e, s) => Center(child: Text('Error: $e')),
                          ),
                        )
                      ],
                    ),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('₹${amount.toStringAsFixed(0)}', style: Theme.of(context).textTheme.displayMedium?.copyWith(
            color: color,
          )),
        ],
      ),
    );
  }

  TextStyle _labelStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontWeight: FontWeight.w600,
      color: AppTheme.textPrimary,
    );
  }

  void _printReceipt(BuildContext context, WidgetRef ref, Payment payment) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt printing triggered.')));
  }
}
