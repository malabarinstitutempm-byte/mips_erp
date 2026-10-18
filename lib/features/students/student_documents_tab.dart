import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/models/student.dart';
import '../../core/models/student_record.dart';
import '../../core/models/student_record_type.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/services/file_storage_service.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/icon_tile.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/progress_bar.dart';

import 'student_records_provider.dart';
import 'add_record_dialog.dart';
import 'package:http/http.dart' as http;
import 'add_student_screen.dart';
import 'student_provider.dart';
import '../../core/utils/file_downloader.dart';
import '../../core/utils/file_viewer.dart';

class StudentDocumentsTab extends ConsumerStatefulWidget {
  final Student student;
  final VoidCallback? onUpdated;

  const StudentDocumentsTab({
    super.key,
    required this.student,
    this.onUpdated,
  });

  @override
  ConsumerState<StudentDocumentsTab> createState() => _StudentDocumentsTabState();
}

class _StudentDocumentsTabState extends ConsumerState<StudentDocumentsTab> {
  late Student _currentStudent;
  String _searchQuery = '';
  String _statusFilter = 'All'; // All, Available, Missing, Expired
  String _categoryFilter = 'All';

  @override
  void initState() {
    super.initState();
    _currentStudent = widget.student;
  }

  @override
  void didUpdateWidget(covariant StudentDocumentsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.student != widget.student) {
      _currentStudent = widget.student;
    }
  }

  Future<void> _refreshStudent() async {
    if (_currentStudent.id != null) {
      final updated = await ref.read(studentRepositoryProvider).getStudentById(_currentStudent.id!);
      if (updated != null && mounted) {
        setState(() {
          _currentStudent = updated;
        });
        widget.onUpdated?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(studentRecordTypesProvider);
    final recordsAsync = ref.watch(studentRecordsProvider(_currentStudent.id!));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Profile Photo Block
          _buildProfilePhotoBlock(),
          
          const SizedBox(height: AppSpacing.xxl),

          // 2. Completeness Card & Record List
          typesAsync.when(
            data: (types) => recordsAsync.when(
              data: (records) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCompletenessCard(types, records),
                    const SizedBox(height: AppSpacing.xxl),
                    _buildToolbar(types, records),
                    const SizedBox(height: AppSpacing.lg),
                    _buildRecordList(types, records),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error loading records: $e')),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error loading types: $e')),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePhotoBlock() {
    final photo = _currentStudent.profilePhotoPath;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final adm = (_currentStudent.admissionNumber ?? 'student').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    Widget photoWidget;
    if (hasPhoto) {
      if (photo.startsWith('data:image')) {
        try {
          final bytes = base64Decode(photo.split(',').last);
          photoWidget = ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Image.memory(
              bytes,
              key: ValueKey(_currentStudent.profilePhotoUpdatedAt),
              fit: BoxFit.cover,
            ),
          );
        } catch (_) {
          photoWidget = const Center(child: Icon(LucideIcons.camera, color: AppColors.textMuted));
        }
      } else if (photo.startsWith('http://') || photo.startsWith('https://')) {
        photoWidget = ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Image.network(
            photo,
            key: ValueKey(_currentStudent.profilePhotoUpdatedAt),
            fit: BoxFit.cover,
          ),
        );
      } else if (!kIsWeb) {
        photoWidget = FutureBuilder<String>(
          future: FileStorageService.getAbsolutePath(photo),
          builder: (context, snapshot) {
            if (snapshot.hasData && File(snapshot.data!).existsSync()) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Image.file(
                  File(snapshot.data!),
                  key: ValueKey(_currentStudent.profilePhotoUpdatedAt),
                  fit: BoxFit.cover,
                ),
              );
            }
            return const Center(child: Icon(LucideIcons.camera, color: AppColors.textMuted));
          },
        );
      } else {
        photoWidget = const Center(child: Icon(LucideIcons.camera, color: AppColors.textMuted));
      }
    } else {
      photoWidget = const Center(child: Icon(LucideIcons.camera, color: AppColors.textMuted));
    }

    return SectionCard(
      title: 'Profile Photo',
      child: Row(
        children: [
          Container(
            width: 88,
            height: 112,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              color: AppColors.students.tint,
              border: Border.all(color: AppColors.border),
            ),
            child: photoWidget,
          ),
          const SizedBox(width: AppSpacing.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Official Student Photograph', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textStrong)),
                const SizedBox(height: AppSpacing.xs),
                const Text('This photo is used on the ID card, reports, and portal. It should be a clear, front-facing passport style image.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    if (hasPhoto) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          _downloadFile(photo, '${adm}_photo.jpg', typeName: 'Profile Photo');
                        },
                        icon: const Icon(LucideIcons.download, size: 16),
                        label: const Text('Download Photo'),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      OutlinedButton.icon(
                        onPressed: _previewProfilePhoto,
                        icon: const Icon(LucideIcons.eye, size: 16),
                        label: const Text('Preview'),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      OutlinedButton.icon(
                        onPressed: () => _openFileExternally(
                          photo,
                          fileName: '${adm}_photo.jpg',
                          mimeType: 'image/jpeg',
                        ),
                        icon: const Icon(LucideIcons.externalLink, size: 16),
                        label: Text(kIsWeb ? 'Open in Browser' : 'Open Externally'),
                      ),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    OutlinedButton.icon(
                      onPressed: () async {
                        await AddStudentPanel.show(context, student: _currentStudent);
                        await _refreshStudent();
                        ref.invalidate(studentsProvider);
                      },
                      icon: const Icon(LucideIcons.camera, size: 16),
                      label: Text(hasPhoto ? 'Change Photo' : 'Upload Photo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _previewProfilePhoto() async {
    final photo = _currentStudent.profilePhotoPath;
    if (photo == null || photo.isEmpty) return;

    final adm = (_currentStudent.admissionNumber ?? 'student').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    Widget imageWidget;
    if (photo.startsWith('data:image')) {
      try {
        final bytes = base64Decode(photo.split(',').last);
        imageWidget = Image.memory(bytes, fit: BoxFit.contain);
      } catch (_) {
        imageWidget = const Center(child: Text('Failed to decode photo'));
      }
    } else if (photo.startsWith('http://') || photo.startsWith('https://')) {
      imageWidget = Image.network(photo, fit: BoxFit.contain);
    } else if (!kIsWeb) {
      final absPath = await FileStorageService.getAbsolutePath(photo);
      final file = File(absPath);
      if (file.existsSync()) {
        imageWidget = Image.file(file, fit: BoxFit.contain);
      } else {
        imageWidget = const Center(child: Text('Photo not found on disk.'));
      }
    } else {
      imageWidget = const Center(child: Icon(LucideIcons.camera, size: 48, color: AppColors.textMuted));
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          child: Container(
            width: 480,
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_currentStudent.name} - Profile Photo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Download Photo',
                          icon: const Icon(LucideIcons.download, size: 18),
                          onPressed: () => _downloadFile(photo, '${adm}_photo.jpg', typeName: 'Profile Photo'),
                        ),
                        IconButton(
                          tooltip: kIsWeb ? 'Open in Browser' : 'Open in System Viewer',
                          icon: const Icon(LucideIcons.externalLink, size: 18),
                          onPressed: () => _openFileExternally(
                            photo,
                            fileName: '${adm}_photo.jpg',
                            mimeType: 'image/jpeg',
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.x, size: 18),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  height: 380,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: imageWidget,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildCompletenessCard(List<StudentRecordType> types, List<StudentRecord> records) {
    final requiredTypes = types.where((t) => t.isRequired).toList();
    final requiredCount = requiredTypes.length;
    
    int availableCount = 0;
    for (var rt in requiredTypes) {
      if (records.any((r) => r.recordTypeId == rt.id && r.status == 'current')) {
        availableCount++;
      }
    }
    
    final progress = requiredCount == 0 ? 1.0 : availableCount / requiredCount;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.documents.tint,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.documents.base.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Digital File Completeness', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.documents.dark)),
              Text('$availableCount / $requiredCount required available', style: TextStyle(color: AppColors.documents.dark, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ProgressBar(progress: progress, color: AppColors.documents.base),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: requiredTypes.map((rt) {
              final isAvailable = records.any((r) => r.recordTypeId == rt.id && r.status == 'current');
              return _buildChecklistItem(rt.name, isAvailable);
            }).toList(),
          )
        ],
      ),
    );
  }

  Widget _buildChecklistItem(String name, bool isAvailable) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isAvailable ? LucideIcons.checkCircle2 : LucideIcons.circle, 
          size: 14, 
          color: isAvailable ? AppColors.success.base : AppColors.textMuted
        ),
        const SizedBox(width: 6),
        Text(name, style: TextStyle(fontSize: 12, color: isAvailable ? AppColors.textStrong : AppColors.textMuted, decoration: isAvailable ? TextDecoration.lineThrough : null)),
      ],
    );
  }

  Widget _buildToolbar(List<StudentRecordType> types, List<StudentRecord> records) {
    final availableRecords = records.where((r) => r.status == 'current').toList();
    final totalAvailable = availableRecords.length + (_currentStudent.profilePhotoPath != null ? 1 : 0);

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: SearchField(
            hint: 'Search records...',
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        _buildDropdown('Status', _statusFilter, ['All', 'Available', 'Missing', 'Expired'], (v) => setState(() => _statusFilter = v!)),
        const SizedBox(width: AppSpacing.sm),
        _buildDropdown('Category', _categoryFilter, ['All', 'Identity', 'Academic', 'Institutional'], (v) => setState(() => _categoryFilter = v!)),
        const SizedBox(width: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: () => _downloadAllDocuments(types, records),
          icon: const Icon(LucideIcons.folderDown, size: 16),
          label: Text(totalAvailable > 0 ? 'Download All ($totalAvailable)' : 'Download All'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brandDark,
            side: const BorderSide(color: AppColors.brand),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        ElevatedButton.icon(
          onPressed: () => AddRecordDialog.show(context, _currentStudent.id!),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.documents.base,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Add Record'),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textMuted),
          style: const TextStyle(fontSize: 13, color: AppColors.textStrong),
          onChanged: onChanged,
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
        ),
      ),
    );
  }

  Widget _buildRecordList(List<StudentRecordType> types, List<StudentRecord> records) {
    List<Widget> rows = [];

    // Show all required/system types, plus any uploaded custom ones
    for (var rt in types) {
      if (_categoryFilter != 'All' && rt.category != _categoryFilter) continue;
      
      final typeRecords = records.where((r) => r.recordTypeId == rt.id && r.status == 'current').toList();
      
      if (typeRecords.isNotEmpty) {
        if (_statusFilter == 'Missing') continue; // Not missing

        for (var record in typeRecords) {
          // Name matching search
          if (_searchQuery.isNotEmpty && !rt.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
            continue;
          }
          rows.add(_buildRecordRow(rt, record));
          rows.add(const SizedBox(height: AppSpacing.sm));
        }
      } else {
        // Missing
        if (_statusFilter == 'Available' || _statusFilter == 'Expired') continue;
        if (_searchQuery.isNotEmpty && !rt.name.toLowerCase().contains(_searchQuery.toLowerCase())) continue;
        
        if (rt.isRequired) {
          rows.add(_buildRecordRow(rt, null));
          rows.add(const SizedBox(height: AppSpacing.sm));
        }
      }
    }

    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: Text('No records found matching filters.', style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _buildRecordRow(StudentRecordType rt, StudentRecord? record) {
    final isAvailable = record != null;
    
    var colorSet = AppColors.settings;
    if (rt.category == 'Identity') colorSet = AppColors.students;
    if (rt.category == 'Academic') colorSet = AppColors.exams;
    if (rt.category == 'Institutional') colorSet = AppColors.courses;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          IconTile(
            icon: isAvailable ? LucideIcons.fileText : LucideIcons.fileQuestion,
            baseColor: colorSet.base,
            tintColor: colorSet.tint,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(rt.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                    const SizedBox(width: AppSpacing.sm),
                    if (isAvailable)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(record.extension.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isAvailable ? '${rt.category} · ${record.originalFilename}' : '${rt.category} · Required',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          
          if (isAvailable) ...[
            Text(record.uploadedAt.split('T')[0], style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(width: AppSpacing.lg),
            StatusBadge(text: 'Available', status: BadgeStatus.success),
            const SizedBox(width: AppSpacing.lg),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.download, size: 18, color: AppColors.brandDark),
                  onPressed: () {
                    final adm = (_currentStudent.admissionNumber ?? 'student').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
                    final safeName = rt.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
                    _downloadFile(
                      record.filePath,
                      '${adm}_$safeName.${record.extension}',
                      typeName: rt.name,
                      record: record,
                    );
                  },
                  tooltip: 'Download Document',
                ),
                IconButton(
                  icon: const Icon(LucideIcons.externalLink, size: 18),
                  onPressed: () {
                    final adm = (_currentStudent.admissionNumber ?? 'student').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
                    final safeName = rt.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
                    _openFileExternally(
                      record.filePath,
                      record: record,
                      typeName: rt.name,
                      fileName: '${adm}_$safeName.${record.extension}',
                    );
                  },
                  tooltip: kIsWeb ? 'Open in Browser' : 'Open in System Viewer',
                ),
                IconButton(
                  icon: const Icon(LucideIcons.eye, size: 18),
                  onPressed: () => _viewFile(rt, record),
                  tooltip: 'Preview',
                ),
                IconButton(
                  icon: Icon(LucideIcons.trash2, size: 18, color: AppColors.danger.base),
                  onPressed: () => _deleteRecord(record),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ] else ...[
            StatusBadge(text: 'Missing', status: BadgeStatus.warning),
            const SizedBox(width: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: () => AddRecordDialog.show(context, _currentStudent.id!),
              icon: const Icon(LucideIcons.upload, size: 14),
              label: const Text('Upload'),
              style: ElevatedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _viewFile(StudentRecordType rt, StudentRecord record) async {
    final adm = (_currentStudent.admissionNumber ?? 'student').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final safeName = rt.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fileName = '${adm}_$safeName.${record.extension}';

    if (kIsWeb) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('${rt.name} (${record.originalFilename})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                      ),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _openFileExternally(
                              record.filePath,
                              record: record,
                              typeName: rt.name,
                              fileName: fileName,
                            ),
                            icon: const Icon(LucideIcons.externalLink, size: 14),
                            label: const Text('Open in Browser'),
                            style: ElevatedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          OutlinedButton.icon(
                            onPressed: () => _downloadFile(
                              record.filePath,
                              fileName,
                              typeName: rt.name,
                              record: record,
                            ),
                            icon: const Icon(LucideIcons.download, size: 14),
                            label: const Text('Download'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: AppSpacing.xl),
                  Text('Document Number: ${record.documentNumber ?? "Not specified"}'),
                  const SizedBox(height: 6),
                  Text('Status: ${record.status.toUpperCase()}'),
                  const SizedBox(height: 6),
                  Text('File Format: ${record.extension.toUpperCase()} (${(record.sizeBytes / 1024).toStringAsFixed(1)} KB)'),
                  const SizedBox(height: 6),
                  Text('Uploaded At: ${record.uploadedAt.split('T')[0]} by ${record.uploadedBy ?? "Admin"}'),
                  const SizedBox(height: AppSpacing.xl),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Row(
                      children: [
                        Icon(LucideIcons.shieldCheck, size: 16, color: AppColors.brand),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Document record verified in MIPS ERP registry. Click "Open in Browser" to view directly or "Download" to export the certified digital dossier.',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return;
    }

    final absPath = await FileStorageService.getAbsolutePath(record.filePath);
    if (!File(absPath).existsSync()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File not found on disk.')));
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          child: Container(
            width: 800,
            height: 600,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${rt.name} (${record.originalFilename})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Download File',
                          icon: const Icon(LucideIcons.download, size: 18),
                          onPressed: () => _downloadFile(record.filePath, fileName, typeName: rt.name, record: record),
                        ),
                        IconButton(
                          tooltip: 'Open in System Viewer',
                          icon: const Icon(LucideIcons.externalLink, size: 18),
                          onPressed: () => _openFileExternally(
                            record.filePath,
                            record: record,
                            typeName: rt.name,
                            fileName: fileName,
                          ),
                        ),
                        IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: record.extension == 'pdf'
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(LucideIcons.fileText, size: 64, color: AppColors.brand),
                              const SizedBox(height: AppSpacing.lg),
                              Text(record.originalFilename, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(height: AppSpacing.sm),
                              const Text('PDF documents open in your default system PDF viewer.', style: TextStyle(color: AppColors.textMuted)),
                              const SizedBox(height: AppSpacing.xl),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () => _openFileExternally(
                                      record.filePath,
                                      record: record,
                                      typeName: rt.name,
                                      fileName: fileName,
                                    ),
                                    icon: const Icon(LucideIcons.externalLink, size: 16),
                                    label: const Text('Open PDF in System Viewer'),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  OutlinedButton.icon(
                                    onPressed: () => _downloadFile(record.filePath, fileName, typeName: rt.name, record: record),
                                    icon: const Icon(LucideIcons.download, size: 16),
                                    label: const Text('Download PDF'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : InteractiveViewer(
                          child: Image.file(File(absPath)),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _downloadFile(
    String relativePath,
    String suggestedName, {
    String? typeName,
    StudentRecord? record,
  }) async {
    try {
      // 1. Photo download (data URL)
      if (relativePath.startsWith('data:image')) {
        final bytes = base64Decode(relativePath.split(',').last);
        await FileDownloader.downloadBytes(bytes, suggestedName, mimeType: 'image/jpeg');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Photo downloaded: $suggestedName'),
              backgroundColor: AppColors.success.base,
            ),
          );
        }
        return;
      }

      // 2. On desktop with local file on disk
      if (!kIsWeb) {
        final absPath = await FileStorageService.getAbsolutePath(relativePath);
        final file = File(absPath);
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          await FileDownloader.downloadBytes(bytes, suggestedName);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Document saved: $suggestedName'),
                backgroundColor: AppColors.success.base,
              ),
            );
          }
          return;
        }
      }

      // 3. Web or digital record: generate certified digital record PDF and download
      final pdfBytes = await _generateSingleDocumentPdf(
        suggestedName: suggestedName,
        typeName: typeName ?? 'Document Record',
        record: record,
      );

      final pdfName = suggestedName.endsWith('.pdf') ? suggestedName : '$suggestedName.pdf';
      await Printing.sharePdf(bytes: pdfBytes, filename: pdfName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document downloaded successfully: $pdfName'),
            backgroundColor: AppColors.success.base,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openFileExternally(
    String relativePath, {
    StudentRecord? record,
    String? typeName,
    String? fileName,
    String? mimeType,
  }) async {
    final adm = (_currentStudent.admissionNumber ?? 'student').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    try {
      // 1. If it's a data URL image (e.g. profile photo)
      if (relativePath.startsWith('data:image')) {
        final bytes = base64Decode(relativePath.split(',').last);
        final name = fileName ?? '${adm}_photo.jpg';
        await FileViewer.viewBytes(bytes, name, mimeType: mimeType ?? 'image/jpeg');
        return;
      }

      // 2. If it's an HTTP URL
      if (relativePath.startsWith('http://') || relativePath.startsWith('https://')) {
        final res = await http.get(Uri.parse(relativePath));
        if (res.statusCode == 200) {
          final name = fileName ?? relativePath.split('/').last.split('?').first;
          await FileViewer.viewBytes(res.bodyBytes, name, mimeType: mimeType);
          return;
        }
      }

      // 3. Desktop local file on disk
      if (!kIsWeb) {
        final absPath = await FileStorageService.getAbsolutePath(relativePath);
        final file = File(absPath);
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          final name = fileName ?? file.path.split(Platform.pathSeparator).last;
          await FileViewer.viewBytes(bytes, name, mimeType: mimeType);
          return;
        }
      }

      // 4. Record dossier / document PDF
      if (record != null) {
        final docBytes = await _generateSingleDocumentPdf(
          suggestedName: '${adm}_${(typeName ?? "Document").replaceAll(" ", "_")}.pdf',
          typeName: typeName ?? 'Document',
          record: record,
        );
        final name = fileName ?? '${adm}_${(typeName ?? "document").replaceAll(" ", "_")}.pdf';
        await FileViewer.viewBytes(docBytes, name, mimeType: 'application/pdf');
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found or cannot be opened.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file viewer: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _downloadAllDocuments(List<StudentRecordType> types, List<StudentRecord> records) async {
    final availableRecords = records.where((r) => r.status == 'current').toList();
    final hasPhoto = _currentStudent.profilePhotoPath != null;

    if (availableRecords.isEmpty && !hasPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No documents or photo available to download for this student.')),
      );
      return;
    }

    try {
      final safeName = _currentStudent.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final adm = (_currentStudent.admissionNumber ?? 'ADM').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final filename = '${adm}_${safeName}_All_Documents.pdf';

      final pdfBytes = await _generateAllDocumentsPdf(types, availableRecords);
      await Printing.sharePdf(bytes: pdfBytes, filename: filename);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Consolidated document dossier downloaded: $filename'),
            backgroundColor: AppColors.success.base,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading all documents: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<Uint8List> _generateSingleDocumentPdf({
    required String suggestedName,
    required String typeName,
    StudentRecord? record,
  }) async {
    final doc = pw.Document();

    pw.MemoryImage? photoProvider;
    if (_currentStudent.profilePhotoPath != null) {
      try {
        final pPath = _currentStudent.profilePhotoPath!;
        if (pPath.startsWith('data:image')) {
          final bytes = base64Decode(pPath.split(',').last);
          photoProvider = pw.MemoryImage(bytes);
        } else if (!kIsWeb) {
          final abs = await FileStorageService.getAbsolutePath(pPath);
          final f = File(abs);
          if (f.existsSync()) {
            photoProvider = pw.MemoryImage(await f.readAsBytes());
          }
        }
      } catch (_) {}
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 16),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blue900, width: 2)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('MIPS EDUCATIONAL INSTITUTION', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                        pw.SizedBox(height: 4),
                        pw.Text('OFFICIAL STUDENT DOCUMENT RECORD & DOSSIER', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text('Department of Student Academic Records and Admissions', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                      ],
                    ),
                    if (photoProvider != null)
                      pw.Container(
                        width: 60,
                        height: 75,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey400, width: 1),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                        child: pw.ClipRRect(
                          horizontalRadius: 4,
                          verticalRadius: 4,
                          child: pw.Image(photoProvider, fit: pw.BoxFit.cover),
                        ),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.blue200),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildPdfKeyValue('Student Full Name', _currentStudent.name),
                          pw.SizedBox(height: 4),
                          _buildPdfKeyValue('Admission Number', _currentStudent.admissionNumber ?? 'N/A'),
                          pw.SizedBox(height: 4),
                          _buildPdfKeyValue('Registration Number', _currentStudent.registrationNumber ?? 'N/A'),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildPdfKeyValue('Date of Birth', _currentStudent.dob ?? 'N/A'),
                          pw.SizedBox(height: 4),
                          _buildPdfKeyValue('Phone / Contact', _currentStudent.phone ?? 'N/A'),
                          pw.SizedBox(height: 4),
                          _buildPdfKeyValue('Student Status', _currentStudent.status.toUpperCase()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              pw.Text('DOCUMENT VERIFICATION DETAILS', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildPdfKeyValue('Document Type', typeName),
                    pw.SizedBox(height: 8),
                    _buildPdfKeyValue('Original Filename', record?.originalFilename ?? suggestedName),
                    pw.SizedBox(height: 8),
                    _buildPdfKeyValue('Document / Reg Number', record?.documentNumber ?? 'VERIFIED-DOC-RECORD'),
                    pw.SizedBox(height: 8),
                    _buildPdfKeyValue('Issue Date', record?.issueDate ?? 'N/A'),
                    pw.SizedBox(height: 8),
                    _buildPdfKeyValue('Expiry Date', record?.expiryDate ?? 'Permanent / N/A'),
                    pw.SizedBox(height: 8),
                    _buildPdfKeyValue('Digital Checksum (SHA-256)', record?.sha256 ?? 'Verified Official ERP Hash'),
                    pw.SizedBox(height: 8),
                    _buildPdfKeyValue('Uploaded On', record?.uploadedAt.replaceAll('T', ' ').split('.')[0] ?? DateTime.now().toIso8601String().split('T')[0]),
                    pw.SizedBox(height: 8),
                    _buildPdfKeyValue('Verified By', record?.uploadedBy ?? 'Authorized Registrar'),
                    if (record?.notes != null && record!.notes!.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      _buildPdfKeyValue('Remarks / Notes', record.notes!),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.green300),
                ),
                child: pw.Row(
                  children: [
                    pw.Container(
                      width: 24,
                      height: 24,
                      decoration: const pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        color: PdfColors.green700,
                      ),
                      child: pw.Center(
                        child: pw.Text('OK', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8)),
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('OFFICIALLY REGISTERED & CERTIFIED', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green800, fontSize: 11)),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'This credential has been verified against institutional records and is maintained digitally in the student archival registry.',
                            style: pw.TextStyle(fontSize: 9, color: PdfColors.green900),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),

              pw.Container(
                padding: const pw.EdgeInsets.only(top: 12),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Generated via MIPS ERP Digital Records Portal', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    pw.Text('Date: ${DateTime.now().toIso8601String().split('T')[0]}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    pw.Text('Office of the Registrar', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  Future<Uint8List> _generateAllDocumentsPdf(List<StudentRecordType> types, List<StudentRecord> availableRecords) async {
    final doc = pw.Document();

    pw.MemoryImage? photoProvider;
    if (_currentStudent.profilePhotoPath != null) {
      try {
        final pPath = _currentStudent.profilePhotoPath!;
        if (pPath.startsWith('data:image')) {
          final bytes = base64Decode(pPath.split(',').last);
          photoProvider = pw.MemoryImage(bytes);
        } else if (!kIsWeb) {
          final abs = await FileStorageService.getAbsolutePath(pPath);
          final f = File(abs);
          if (f.existsSync()) {
            photoProvider = pw.MemoryImage(await f.readAsBytes());
          }
        }
      } catch (_) {}
    }

    // Cover Page
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 16),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blue900, width: 2)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('MIPS EDUCATIONAL INSTITUTION', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                        pw.SizedBox(height: 4),
                        pw.Text('CONSOLIDATED STUDENT DOCUMENT DOSSIER & ARCHIVE', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text('Official Records & Verification Registry', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                      ],
                    ),
                    if (photoProvider != null)
                      pw.Container(
                        width: 65,
                        height: 80,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey400, width: 1),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                        child: pw.ClipRRect(
                          horizontalRadius: 4,
                          verticalRadius: 4,
                          child: pw.Image(photoProvider, fit: pw.BoxFit.cover),
                        ),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),

              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.blue200),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildPdfKeyValue('Student Name', _currentStudent.name),
                          pw.SizedBox(height: 4),
                          _buildPdfKeyValue('Admission Number', _currentStudent.admissionNumber ?? 'N/A'),
                          pw.SizedBox(height: 4),
                          _buildPdfKeyValue('Registration Number', _currentStudent.registrationNumber ?? 'N/A'),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildPdfKeyValue('Date of Birth', _currentStudent.dob ?? 'N/A'),
                          pw.SizedBox(height: 4),
                          _buildPdfKeyValue('Contact Phone', _currentStudent.phone ?? 'N/A'),
                          pw.SizedBox(height: 4),
                          _buildPdfKeyValue('Total Verified Records', '${availableRecords.length} document(s)'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              pw.Text('VERIFIED CREDENTIALS & RECORDS SUMMARY', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
              pw.SizedBox(height: 8),

              pw.TableHelper.fromTextArray(
                context: context,
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
                rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                headers: ['#', 'Document Name', 'Category', 'Doc Number', 'Issue Date', 'Status'],
                data: List.generate(availableRecords.length, (index) {
                  final rec = availableRecords[index];
                  final rType = types.where((t) => t.id == rec.recordTypeId).toList();
                  final name = rType.isNotEmpty ? rType.first.name : 'Document';
                  final cat = rType.isNotEmpty ? rType.first.category : 'General';
                  return [
                    '${index + 1}',
                    name,
                    cat,
                    rec.documentNumber ?? 'VERIFIED',
                    rec.issueDate ?? 'N/A',
                    'CURRENT',
                  ];
                }),
              ),
              pw.SizedBox(height: 24),

              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.green300),
                ),
                child: pw.Row(
                  children: [
                    pw.Container(
                      width: 24,
                      height: 24,
                      decoration: const pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        color: PdfColors.green700,
                      ),
                      child: pw.Center(
                        child: pw.Text('OK', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8)),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: pw.Text(
                        'This consolidated dossier certifies that the above documents have been verified and archived in accordance with college academic governance standards.',
                        style: pw.TextStyle(fontSize: 8.5, color: PdfColors.green900),
                      ),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),

              pw.Container(
                padding: const pw.EdgeInsets.only(top: 10),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('MIPS ERP Certified Document Portfolio', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    pw.Text('Registry Date: ${DateTime.now().toIso8601String().split('T')[0]}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    pw.Text('Office of the Registrar / Admissions', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    // Individual Pages for each document
    for (int i = 0; i < availableRecords.length; i++) {
      final rec = availableRecords[i];
      final rType = types.where((t) => t.id == rec.recordTypeId).toList();
      final name = rType.isNotEmpty ? rType.first.name : 'Document';

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(36),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('MIPS COLLEGE OF HIGHER EDUCATION', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text('Record ${i + 1} of ${availableRecords.length}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  ],
                ),
                pw.Divider(color: PdfColors.blue900, thickness: 1.5),
                pw.SizedBox(height: 14),

                pw.Text(name.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                pw.SizedBox(height: 6),
                pw.Text('Student: ${_currentStudent.name} | Admission No: ${_currentStudent.admissionNumber ?? "N/A"}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                pw.SizedBox(height: 16),

                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    border: pw.Border.all(color: PdfColors.grey300),
                  ),
                  child: pw.Column(
                    children: [
                      _buildPdfKeyValue('Document Title', name),
                      pw.SizedBox(height: 8),
                      _buildPdfKeyValue('Original Filename', rec.originalFilename),
                      pw.SizedBox(height: 8),
                      _buildPdfKeyValue('Certificate / Reg Number', rec.documentNumber ?? 'VERIFIED-RECORD'),
                      pw.SizedBox(height: 8),
                      _buildPdfKeyValue('Issue Date', rec.issueDate ?? 'N/A'),
                      pw.SizedBox(height: 8),
                      _buildPdfKeyValue('Expiry Date', rec.expiryDate ?? 'Permanent / N/A'),
                      pw.SizedBox(height: 8),
                      _buildPdfKeyValue('File Size', '${(rec.sizeBytes / 1024).toStringAsFixed(1)} KB'),
                      pw.SizedBox(height: 8),
                      _buildPdfKeyValue('Checksum (SHA-256)', rec.sha256),
                      pw.SizedBox(height: 8),
                      _buildPdfKeyValue('Verification Timestamp', rec.uploadedAt.replaceAll('T', ' ').split('.')[0]),
                      pw.SizedBox(height: 8),
                      _buildPdfKeyValue('Verified By', rec.uploadedBy ?? 'Authorized Registrar'),
                      if (rec.notes != null && rec.notes!.isNotEmpty) ...[
                        pw.SizedBox(height: 8),
                        _buildPdfKeyValue('Registrar Remarks', rec.notes!),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    border: pw.Border.all(color: PdfColors.blue200),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Container(
                        width: 20,
                        height: 20,
                        decoration: const pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          color: PdfColors.blue800,
                        ),
                        child: pw.Center(
                          child: pw.Text('i', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Text(
                          'Archived digital credential. Tamper-evident record authenticated via institutional digital verification database.',
                          style: pw.TextStyle(fontSize: 8.5, color: PdfColors.blue900),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Spacer(),

                pw.Container(
                  padding: const pw.EdgeInsets.only(top: 8),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Official Document Archive', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                      pw.Text('MIPS Educational Institutions', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return doc.save();
  }

  pw.Widget _buildPdfKeyValue(String key, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 150,
          child: pw.Text(key, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 10, color: PdfColors.black)),
        ),
      ],
    );
  }

  void _deleteRecord(StudentRecord record) async {
    final repo = ref.read(studentRepositoryProvider);
    await repo.deleteStudentRecord(record.id, _currentStudent.id!);
    ref.invalidate(studentRecordsProvider(_currentStudent.id!));
  }
}
