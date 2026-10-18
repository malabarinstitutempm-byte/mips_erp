import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/batch.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../courses/course_provider.dart';

class ReopenBatchDialog extends ConsumerStatefulWidget {
  final Batch batch;
  final VoidCallback onReopened;

  const ReopenBatchDialog({
    super.key,
    required this.batch,
    required this.onReopened,
  });

  static Future<void> show(BuildContext context, {required Batch batch, required VoidCallback onReopened}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReopenBatchDialog(batch: batch, onReopened: onReopened),
    );
  }

  @override
  ConsumerState<ReopenBatchDialog> createState() => _ReopenBatchDialogState();
}

class _ReopenBatchDialogState extends ConsumerState<ReopenBatchDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final reason = _reasonController.text.trim();

    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(batchRepositoryProvider);
      final res = await repo.reopenBatch(widget.batch.id!, reason: reason);

      if (mounted) {
        setState(() => _isSubmitting = false);
        Navigator.pop(context);

        final reopenedCount = res['reopened_students_count'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Batch "${widget.batch.batchName}" reopened successfully ($reopenedCount students restored to active).'),
            backgroundColor: Colors.green,
          ),
        );

        widget.onReopened();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reopen batch: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.orange.withOpacity(0.1),
            child: const Icon(LucideIcons.rotateCcw, color: Colors.orange, size: 18),
          ),
          const SizedBox(width: 12),
          const Text('Reopen Batch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are reopening batch "${widget.batch.batchName}". All students completed under this batch will be restored to active status, and attendance marking will resume.',
                style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textStrong),
              ),
              const SizedBox(height: 16),
              const Text(
                'Reason for Reopening *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Enter justification (e.g. Exam postponement, curriculum extension, etc.)...',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'A valid reason is required to reopen a batch.';
                  }
                  if (val.trim().length < 5) {
                    return 'Please enter a more descriptive reason (min 5 characters).';
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
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange[800],
            foregroundColor: Colors.white,
          ),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Reopen Batch'),
        ),
      ],
    );
  }
}
