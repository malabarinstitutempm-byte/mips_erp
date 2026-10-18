import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import 'excel_import_service.dart';
import 'student_provider.dart';

class ImportPreviewDialog extends ConsumerStatefulWidget {
  final String filePath;

  const ImportPreviewDialog({super.key, required this.filePath});

  @override
  ConsumerState<ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends ConsumerState<ImportPreviewDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _rows = [];
  int _validCount = 0;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final rows = await ExcelImportService.previewImport(widget.filePath);
      setState(() {
        _rows = rows;
        _validCount = rows.where((r) => r['is_valid'] == true).length;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to read Excel: $e')));
      }
    }
  }

  void _downloadErrors() async {
    try {
      final path = await ExcelImportService.downloadErrorReport(_rows);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error report saved to $path')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save error report: $e')));
    }
  }

  void _import() async {
    if (_validCount == 0) return;
    setState(() => _isImporting = true);

    try {
      final importId = const Uuid().v4();
      final res = await ExcelImportService.executeImport(_rows, importBatchId: importId);
      final importedCount = res['imported_count'] ?? _validCount;
      
      if (mounted) {
        ref.invalidate(studentsProvider);
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Successfully imported $importedCount students in batch.'),
          backgroundColor: AppColors.success.base,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: AppColors.danger.base,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Preview'),
      content: SizedBox(
        width: 800,
        height: 600,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$_validCount valid rows ready to import out of ${_rows.length}.', style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (_rows.length > _validCount)
                        TextButton.icon(
                          onPressed: _downloadErrors,
                          icon: const Icon(LucideIcons.downloadCloud, size: 16),
                          label: const Text('Download Error Report'),
                        ),
                    ],
                  ),
                  SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowColor: MaterialStateProperty.all(AppColors.surface),
                          columns: const [
                            DataColumn(label: Text('Row')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('Course')),
                            DataColumn(label: Text('Batch')),
                            DataColumn(label: Text('Errors')),
                          ],
                          rows: _rows.map((r) {
                            final valid = r['is_valid'] == true;
                            return DataRow(
                              color: MaterialStateProperty.all(valid ? Colors.transparent : AppColors.danger.tint),
                              cells: [
                                DataCell(Text(r['row'].toString())),
                                DataCell(Icon(valid ? LucideIcons.checkCircle : LucideIcons.xCircle, color: valid ? AppColors.success.base : AppColors.danger.base, size: 18)),
                                DataCell(Text(r['name'])),
                                DataCell(Text(r['course'])),
                                DataCell(Text(r['batch'])),
                                DataCell(Text((r['errors'] as List).join('; '), style: TextStyle(color: AppColors.danger.dark, fontSize: 12))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _isLoading || _isImporting || _validCount == 0 ? null : _import,
          child: _isImporting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text('Import $_validCount Rows'),
        ),
      ],
    );
  }
}
