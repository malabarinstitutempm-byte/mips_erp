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
    final isMobile = MediaQuery.of(context).size.width < 700;

    return SectionCard(
      title: 'Student Record Types',
      trailing: isMobile ? null : ElevatedButton.icon(
        onPressed: () => _showEditDialog(null),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.documents.base, foregroundColor: Colors.white),
        icon: const Icon(LucideIcons.plus, size: 16),
        label: const Text('Add Type'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMobile) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showEditDialog(null),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.documents.base, foregroundColor: Colors.white),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add Type'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Text('Manage categories of scanned documents and certificates.', style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: AppSpacing.xl),
          
          typesAsync.when(
            data: (types) => _buildContent(types, isMobile),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<StudentRecordType> types, bool isMobile) {
    if (types.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No record types configured.')),
      );
    }

    if (isMobile) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: types.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final t = types[i];
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                          if (t.isSystem) ...[
                            const SizedBox(width: 6),
                            const Icon(LucideIcons.lock, size: 13, color: AppColors.textMuted),
                          ],
                        ],
                      ),
                    ),
                    StatusBadge(
                      text: t.isActive ? 'Active' : 'Inactive',
                      status: t.isActive ? BadgeStatus.success : BadgeStatus.draft,
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.edit2, size: 16),
                      onPressed: () => _showEditDialog(t),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.documents.tint,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(t.category, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.documents.dark)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t.isRequired ? 'Required' : 'Optional',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: t.isRequired ? FontWeight.bold : FontWeight.normal,
                        color: t.isRequired ? AppColors.danger.base : AppColors.textMuted,
                      ),
                    ),
                    const Text(' • ', style: TextStyle(color: AppColors.textMuted)),
                    Text(
                      t.allowMultiple ? 'Multiple files' : 'Single file',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
                if (t.allowedExtensions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Formats: ${t.allowedExtensions}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          );
        },
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
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
      isSystem: widget.type?.isSystem ?? false,
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
                enabled: !isSystem,
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
                onChanged: isSystem ? null : (v) => setState(() => _isActive = v),
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
