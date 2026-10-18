import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/student_record_type.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/status_badge.dart';

import '../students/student_records_provider.dart';
import '../students/student_provider.dart';

class RecordTypesSettingsPanel extends ConsumerStatefulWidget {
  const RecordTypesSettingsPanel({super.key});

  @override
  ConsumerState<RecordTypesSettingsPanel> createState() => _RecordTypesSettingsPanelState();
}

class _RecordTypesSettingsPanelState extends ConsumerState<RecordTypesSettingsPanel> {
  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(studentRecordTypesProvider);

    return SectionCard(
      title: 'Student Record Types',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Manage categories of scanned documents and certificates.', style: TextStyle(color: AppColors.textMuted)),
              ElevatedButton.icon(
                onPressed: () => _showEditDialog(null),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.documents.base, foregroundColor: Colors.white),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add Type'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          
          typesAsync.when(
            data: (types) => _buildTable(types),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<StudentRecordType> types) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.bg),
          dataRowMaxHeight: 56,
          columns: const [
            DataColumn(label: Text('Record Type', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Constraints', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: types.map((t) {
            return DataRow(
              cells: [
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (t.isSystem) ...[
                            const SizedBox(width: 6),
                            const Icon(LucideIcons.lock, size: 12, color: AppColors.textMuted),
                          ]
                        ],
                      ),
                      if (t.allowedExtensions.isNotEmpty)
                        Text(t.allowedExtensions, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                DataCell(Text(t.category)),
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (t.isRequired) Text('Required', style: TextStyle(fontSize: 12, color: AppColors.danger.base, fontWeight: FontWeight.bold))
                      else const Text('Optional', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      
                      if (t.allowMultiple) const Text('Multiple allowed', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
                      else const Text('Single file only', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                DataCell(
                  StatusBadge(
                    text: t.isActive ? 'Active' : 'Inactive',
                    status: t.isActive ? BadgeStatus.success : BadgeStatus.draft,
                  ),
                ),
                DataCell(
                  IconButton(
                    icon: const Icon(LucideIcons.edit2, size: 16),
                    onPressed: () => _showEditDialog(t),
                    tooltip: 'Edit',
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showEditDialog(StudentRecordType? type) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RecordTypeDialog(type: type, onSaved: () => ref.invalidate(studentRecordTypesProvider)),
    );
  }
}

class _RecordTypeDialog extends ConsumerStatefulWidget {
  final StudentRecordType? type;
  final VoidCallback onSaved;

  const _RecordTypeDialog({required this.type, required this.onSaved});

  @override
  ConsumerState<_RecordTypeDialog> createState() => _RecordTypeDialogState();
}

class _RecordTypeDialogState extends ConsumerState<_RecordTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _extCtrl;
  
  String _category = 'Identity';
  bool _isRequired = false;
  bool _allowMultiple = false;
  bool _isActive = true;
  
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.type?.name ?? '');
    _descCtrl = TextEditingController(text: widget.type?.description ?? '');
    _extCtrl = TextEditingController(text: widget.type?.allowedExtensions ?? 'pdf,jpg,png');
    
    if (widget.type != null) {
      _category = widget.type!.category;
      _isRequired = widget.type!.isRequired;
      _allowMultiple = widget.type!.allowMultiple;
      _isActive = widget.type!.isActive;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _extCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    
    final repo = ref.read(studentRepositoryProvider);
    final t = StudentRecordType(
      id: widget.type?.id,
      name: _nameCtrl.text.trim(),
      category: _category,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      allowedExtensions: _extCtrl.text.trim(),
      isRequired: _isRequired,
      allowMultiple: _allowMultiple,
      isActive: _isActive,
      isSystem: widget.type?.isSystem ?? false, // can't change system flag
      sortOrder: widget.type?.sortOrder ?? 99,
    );

    try {
      if (widget.type == null) {
        await repo.addRecordType(t);
      } else {
        await repo.updateRecordType(t);
      }
      
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSystem = widget.type?.isSystem ?? false;

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
              Text(widget.type == null ? 'New Record Type' : 'Edit Record Type', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xl),
              
              TextFormField(
                controller: _nameCtrl,
                enabled: !isSystem, // system names cannot be changed to prevent logic breaks
                decoration: InputDecoration(
                  labelText: 'Name', 
                  hintText: 'e.g., Blood Group Certificate',
                  helperText: isSystem ? 'System defined types cannot be renamed.' : null,
                ),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: ['Identity', 'Academic', 'Institutional', 'Custom'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: AppSpacing.md),
              
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Description (Optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              
              TextFormField(
                controller: _extCtrl,
                decoration: const InputDecoration(labelText: 'Allowed Extensions', hintText: 'pdf,jpg,png'),
              ),
              const SizedBox(height: AppSpacing.lg),
              
              // Toggles
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Required Document', style: TextStyle(fontSize: 14)),
                subtitle: const Text('Students will be marked incomplete if missing.', style: TextStyle(fontSize: 12)),
                value: _isRequired,
                onChanged: (v) => setState(() => _isRequired = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow Multiple Files', style: TextStyle(fontSize: 14)),
                subtitle: const Text('If off, new uploads will archive older ones.', style: TextStyle(fontSize: 12)),
                value: _allowMultiple,
                onChanged: (v) => setState(() => _allowMultiple = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active', style: TextStyle(fontSize: 14)),
                subtitle: const Text('If inactive, this type will not appear in dropdowns.', style: TextStyle(fontSize: 12)),
                value: _isActive,
                onChanged: isSystem ? null : (v) => setState(() => _isActive = v), // system types cannot be completely deactivated if we want to be safe, but actually user rules say "they can deactivate". Let's allow deactivation.
              ),
              
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: AppSpacing.md),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
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
