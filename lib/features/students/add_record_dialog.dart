import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/student_record.dart';
import '../../core/models/student_record_type.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/services/file_storage_service.dart';
import 'student_provider.dart';
import 'student_records_provider.dart';

class AddRecordDialog extends ConsumerStatefulWidget {
  final int studentId;

  const AddRecordDialog({super.key, required this.studentId});

  static Future<void> show(BuildContext context, int studentId) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddRecordDialog(studentId: studentId),
    );
  }

  @override
  ConsumerState<AddRecordDialog> createState() => _AddRecordDialogState();
}

class _AddRecordDialogState extends ConsumerState<AddRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  
  File? _selectedFile;
  PlatformFile? _pickedPlatformFile;
  StudentRecordType? _selectedType;
  
  final _docNumberCtrl = TextEditingController();
  final _issueDateCtrl = TextEditingController();
  final _expiryDateCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _docNumberCtrl.dispose();
    _issueDateCtrl.dispose();
    _expiryDateCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (_selectedType == null) {
      setState(() => _error = 'Please select a record type first.');
      return;
    }
    
    final extensions = _selectedType!.allowedExtensions.split(',').map((e) => e.trim()).toList();
    
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        allowMultiple: false,
        withData: kIsWeb,
      );

      if (result != null && result.files.isNotEmpty) {
        final pf = result.files.single;
        if (pf.size > FileStorageService.maxRecordSizeBytes) {
          setState(() => _error = 'File is too large. Max 25MB.');
          return;
        }
        setState(() {
          _pickedPlatformFile = pf;
          if (!kIsWeb && pf.path != null) {
            _selectedFile = File(pf.path!);
          } else {
            _selectedFile = null;
          }
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'Failed to pick file.');
    }
  }

  Future<void> _saveRecord() async {
    final hasFile = kIsWeb ? (_pickedPlatformFile != null) : (_selectedFile != null || _pickedPlatformFile != null);
    if (!_formKey.currentState!.validate() || _selectedType == null || !hasFile) {
      setState(() => _error = 'Please complete all required fields and select a file.');
      return;
    }

    setState(() => _isSaving = true);
    
    try {
      final uuid = const Uuid().v4();
      
      String originalName;
      String ext;
      int sizeBytes;
      String hash;
      String relPath;

      if (kIsWeb || _selectedFile == null) {
        originalName = _pickedPlatformFile?.name ?? 'document.pdf';
        ext = _pickedPlatformFile?.extension ?? (originalName.contains('.') ? originalName.split('.').last.toLowerCase() : 'pdf');
        sizeBytes = _pickedPlatformFile?.size ?? 102400;
        hash = 'web_upload_${DateTime.now().millisecondsSinceEpoch}';
        relPath = 'student_files/student_${widget.studentId}/records/$uuid.$ext';
      } else {
        ext = _selectedFile!.path.split(RegExp(r'[\\/]')).last.split('.').last.toLowerCase();
        originalName = _selectedFile!.path.split(RegExp(r'[\\/]')).last;
        sizeBytes = await _selectedFile!.length();
        hash = await FileStorageService.getFileHash(_selectedFile!);
        
        // Copy to temp first
        final tempFile = await FileStorageService.moveToTemp(_selectedFile!, 'upload_$uuid.$ext');
        
        // Save permanently (this returns relative path)
        relPath = await FileStorageService.saveStudentRecord(widget.studentId, tempFile, uuid, ext);
      }
      
      final record = StudentRecord(
        id: uuid,
        studentId: widget.studentId,
        recordTypeId: _selectedType!.id!,
        filePath: relPath,
        originalFilename: originalName,
        extension: ext,
        sizeBytes: sizeBytes,
        sha256: hash,
        documentNumber: _docNumberCtrl.text.trim().isEmpty ? null : _docNumberCtrl.text.trim(),
        issueDate: _issueDateCtrl.text.trim().isEmpty ? null : _issueDateCtrl.text.trim(),
        expiryDate: _expiryDateCtrl.text.trim().isEmpty ? null : _expiryDateCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        uploadedAt: DateTime.now().toIso8601String(),
        uploadedBy: 'Admin',
      );

      final repo = ref.read(studentRepositoryProvider);
      await repo.addStudentRecord(record, 'Uploaded $originalName');

      if (mounted) {
        ref.invalidate(studentRecordsProvider(widget.studentId));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to save record: $e';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(studentRecordTypesProvider);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radius14)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Add Student Record', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  color: AppColors.danger.tint,
                  child: Text(_error!, style: TextStyle(color: AppColors.danger.base, fontSize: 13)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              typesAsync.when(
                data: (types) => DropdownButtonFormField<StudentRecordType>(
                  decoration: const InputDecoration(labelText: 'Record Type *'),
                  value: _selectedType,
                  items: types.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedType = val;
                      _selectedFile = null; // reset file since allowed extensions might change
                    });
                  },
                  validator: (v) => v == null ? 'Required' : null,
                ),
                loading: () => const CircularProgressIndicator(),
                error: (_,__) => const Text('Error loading record types'),
              ),
              
              const SizedBox(height: AppSpacing.md),
              
              // File Picker Area
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  color: AppColors.bg,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _pickedPlatformFile?.name ??
                            (_selectedFile != null
                                ? _selectedFile!.path.split(RegExp(r'[\\/]')).last
                                : 'No file selected'),
                        style: TextStyle(
                          color: (_pickedPlatformFile != null || _selectedFile != null)
                              ? AppColors.textStrong
                              : AppColors.textMuted,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ElevatedButton.icon(
                      onPressed: _selectedType == null ? null : _pickFile,
                      icon: const Icon(LucideIcons.upload, size: 14),
                      label: const Text('Browse'),
                      style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _docNumberCtrl,
                decoration: const InputDecoration(labelText: 'Document Number (Optional)', hintText: 'e.g., ABC1234567'),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _issueDateCtrl,
                      decoration: const InputDecoration(labelText: 'Issue Date (Optional)', hintText: 'YYYY-MM-DD'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      controller: _expiryDateCtrl,
                      decoration: const InputDecoration(labelText: 'Expiry Date (Optional)', hintText: 'YYYY-MM-DD'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes (Optional)'),
                maxLines: 2,
              ),

              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveRecord,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.documents.base,
                      foregroundColor: Colors.white,
                    ),
                    child: _isSaving 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Save Record'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
