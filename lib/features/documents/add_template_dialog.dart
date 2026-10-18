import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/document_template.dart';
import '../../core/models/student.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'documents_provider.dart';
import 'document_generator.dart';

class AddTemplateDialog extends ConsumerStatefulWidget {
  const AddTemplateDialog({super.key});

  @override
  ConsumerState<AddTemplateDialog> createState() => _AddTemplateDialogState();
}

class _AddTemplateDialogState extends ConsumerState<AddTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _isSaving = false;
  String _preview = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _contentCtrl.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    _contentCtrl.removeListener(_onContentChanged);
    _contentCtrl.dispose();
    _nameCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onContentChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _generateLivePreview();
    });
  }

  Future<void> _generateLivePreview() async {
    final rawContent = _contentCtrl.text;
    if (rawContent.isEmpty) {
      setState(() => _preview = '');
      return;
    }

    final dummyStudent = Student(
      name: 'John Doe',
      admissionNumber: 'MIPS/2026/001',
      courseId: 1,
      universityId: 1,
    );

    final replaced = await DocumentGenerator.replaceVariables(rawContent, dummyStudent, 'MIPS/DOC/2026/0001');
    if (mounted) {
      setState(() => _preview = replaced);
    }
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      try {
        final repo = ref.read(documentRepositoryProvider);
        await repo.addTemplate(DocumentTemplate(
          name: _nameCtrl.text.trim(),
          content: _contentCtrl.text.trim(),
        ));
        
        ref.invalidate(templatesProvider);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save template: $e')));
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Template'),
      content: SizedBox(
        width: 1000,
        height: 600,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 1,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Template Name', hintText: 'e.g. Character Certificate'),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(
                      child: TextFormField(
                        controller: _contentCtrl,
                        expands: true,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          labelText: 'Template Content',
                          hintText: 'Use variables like {{student_name}}, {{admission_number}}',
                          alignLabelWithHint: true,
                        ),
                        validator: (val) => val == null || val.trim().isEmpty ? 'Content is required' : null,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Available variables: {{student_name}}, {{admission_number}}, {{registration_number}}, {{course}}, {{batch}}, {{university}}, {{date}}, {{title}}, {{he_she}}, {{his_her}}, {{him_her}}, {{son_daughter}}',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Live Preview (A4)', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textStrong)),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            _preview.isEmpty ? 'Preview will appear here...' : _preview,
                            style: const TextStyle(fontSize: 13, height: 1.8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isSaving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Template'),
        ),
      ],
    );
  }
}
