import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models/student.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/app_data_table.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/app_avatar.dart';
import 'student_provider.dart';
import 'add_student_screen.dart';
import 'student_profile_screen.dart';
import '../courses/course_provider.dart';
import 'excel_import_service.dart';
import 'import_preview_dialog.dart';

class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  String _searchQuery = '';
  int? _selectedCourseId;
  int? _selectedYear;
  String _statusFilter = 'active'; // 'active', 'inactive', 'deleted'
  int _currentPage = 0;
  static const int _pageSize = 25;

  void _exportExcel(List<Student> students) async {
    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Students'];
      
      sheetObject.appendRow([
        TextCellValue('ID'), 
        TextCellValue('Admission Number'), 
        TextCellValue('Registration Number'), 
        TextCellValue('Name'), 
        TextCellValue('Phone'),
        TextCellValue('Status'),
      ]);
      
      for (var s in students) {
        sheetObject.appendRow([
          TextCellValue(s.id?.toString() ?? ''),
          TextCellValue(s.admissionNumber ?? ''),
          TextCellValue(s.registrationNumber ?? ''),
          TextCellValue(s.name),
          TextCellValue(s.phone ?? ''),
          TextCellValue(s.deletedAt != null ? 'DELETED' : s.status),
        ]);
      }
      
      var fileBytes = excel.save();
      if (fileBytes != null) {
        var dir = await getDownloadsDirectory();
        var path = '${dir!.path}/students_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export saved to $path')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  void _importExcel() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
      if (result != null && result.files.single.path != null) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (c) => ImportPreviewDialog(filePath: result.files.single.path!),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _downloadTemplate() async {
    try {
      final path = await ExcelImportService.generateTemplate();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Template saved to $path')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _undoImport() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Undo Last Import?'),
        content: const Text('This will rollback all students created during the last import session. Proceed?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger.base, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true), 
            child: const Text('Undo Import'),
          ),
        ],
      ),
    );
    if (proceed != true) return;

    try {
      final repo = ref.read(studentRepositoryProvider);
      final lastBatchId = await repo.getLastImportBatchId();
      if (lastBatchId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No active import batch found to undo.')),
          );
        }
        return;
      }
      
      final res = await ExcelImportService.undoImport(lastBatchId);
      final count = res['undone_count'] ?? 0;
      
      if (mounted) {
        ref.invalidate(paginatedStudentsProvider);
        ref.invalidate(studentsTotalCountProvider);
        ref.invalidate(studentsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Undo successful. Removed $count students.'),
            backgroundColor: AppColors.success.base,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Undo failed: $e'),
            backgroundColor: AppColors.danger.base,
          ),
        );
      }
    }
  }

  void _confirmDeleteStudent(BuildContext context, Student s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: AppColors.danger.base, size: 22),
            const SizedBox(width: 10),
            const Text('Delete Student?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${s.name}" (Admission No: ${s.admissionNumber ?? "N/A"})?\n\nThis will remove the student from active lists, fees, and exams.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger.base,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (s.id != null) {
                await ref.read(studentRepositoryProvider).deleteStudent(s.id!);
                ref.invalidate(paginatedStudentsProvider);
                ref.invalidate(studentsTotalCountProvider);
                ref.invalidate(studentsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Student "${s.name}" deleted successfully.')),
                  );
                }
              }
            },
            child: const Text('Delete Student'),
          ),
        ],
      ),
    );
  }

  void _confirmRestoreStudent(BuildContext context, Student s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.rotateCcw, color: AppColors.success.base, size: 22),
            const SizedBox(width: 10),
            const Text('Restore Student?'),
          ],
        ),
        content: Text(
          'Are you sure you want to restore "${s.name}" (Admission No: ${s.admissionNumber ?? "N/A"}) back to the active directory?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success.base,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (s.id != null) {
                await ref.read(studentRepositoryProvider).restoreStudent(s.id!);
                ref.invalidate(paginatedStudentsProvider);
                ref.invalidate(studentsTotalCountProvider);
                ref.invalidate(studentsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Student "${s.name}" restored successfully.'),
                      backgroundColor: AppColors.success.base,
                    ),
                  );
                }
              }
            },
            child: const Text('Restore Student'),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileStudentCard(
    BuildContext context, {
    required Student s,
    required String courseName,
    required dynamic batch,
    required bool isDeleted,
    required String badgeText,
    required BadgeStatus badgeStatus,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x060F172A), offset: Offset(0, 1), blurRadius: 2),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (c) => StudentProfileScreen(student: s)));
          },
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppAvatar(name: s.name, radius: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textStrong),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Adm: ${s.admissionNumber ?? "—"} • Reg: ${s.registrationNumber ?? "—"}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(text: badgeText, status: badgeStatus),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        courseName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textStrong),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (batch != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.brand.withOpacity(0.2)),
                        ),
                        child: Text(
                          'Sem ${batch.currentSemester} (Yr ${batch.currentYear})',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.brand),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      s.phone != null && s.phone!.isNotEmpty ? '📞 ${s.phone}' : 'No phone',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isDeleted)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.success.base,
                              side: BorderSide(color: AppColors.success.base.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _confirmRestoreStudent(context, s),
                            icon: const Icon(LucideIcons.rotateCcw, size: 12),
                            label: const Text('Restore', style: TextStyle(fontSize: 11)),
                          )
                        else ...[
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => StudentProfileScreen(student: s)));
                            },
                            child: const Text('View Profile →', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(LucideIcons.trash2, size: 15, color: AppColors.danger.base),
                            tooltip: 'Delete',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _confirmDeleteStudent(context, s),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = StudentFilter(
      query: _searchQuery,
      courseId: _selectedCourseId,
      year: _selectedYear,
      status: _statusFilter,
      includeDeleted: _statusFilter == 'deleted',
      page: _currentPage,
      pageSize: _pageSize,
    );

    final studentsAsync = ref.watch(paginatedStudentsProvider(filter));
    final countAsync = ref.watch(studentsTotalCountProvider(filter));
    final coursesAsync = ref.watch(coursesProvider);
    final batchesMap = ref.watch(batchesMapProvider).valueOrNull ?? {};
    final courseMap = coursesAsync.maybeWhen(
      data: (courses) => {for (var c in courses) if (c.id != null) c.id!: c.name},
      orElse: () => <int, String>{},
    );

    final isMobile = MediaQuery.of(context).size.width < 750;

    return Column(
      children: [
        PageHeader(
          title: 'Students Directory',
          subtitle: 'Manage admissions and student records',
          actions: [
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'template') _downloadTemplate();
                if (val == 'undo') _undoImport();
              },
              itemBuilder: (c) => const [
                PopupMenuItem(value: 'template', child: Text('Download Template')),
                PopupMenuItem(value: 'undo', child: Text('Undo Last Import', style: TextStyle(color: Colors.red))),
              ],
              child: const OutlinedButton(onPressed: null, child: Icon(LucideIcons.moreVertical, size: 18)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _importExcel,
              icon: const Icon(LucideIcons.uploadCloud, size: 18),
              label: const Text('Import'),
            ),
            const SizedBox(width: 8),
            studentsAsync.when(
              data: (students) => OutlinedButton.icon(
                onPressed: () => _exportExcel(students),
                icon: const Icon(LucideIcons.downloadCloud, size: 18),
                label: const Text('Export'),
              ),
              loading: () => const OutlinedButton(onPressed: null, child: Text('Exporting...')),
              error: (_,__) => const SizedBox(),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => AddStudentPanel.show(context),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('Add Student'),
            ),
          ],
        ),
        
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: AppColors.border)),
            child: Column(
              children: [
                // Toolbar
                Padding(
                  padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: isMobile ? double.infinity : 280,
                        child: SearchField(
                          hint: 'Search by name, admission no, or reg no...',
                          onChanged: (v) => setState(() {
                            _searchQuery = v;
                            _currentPage = 0;
                          }),
                        ),
                      ),
                      // Course Filter Dropdown
                      Container(
                        height: 40,
                        width: isMobile ? double.infinity : 200,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            isExpanded: true,
                            value: _selectedCourseId,
                            items: [
                              const DropdownMenuItem<int?>(value: null, child: Text('All Courses', overflow: TextOverflow.ellipsis)),
                              ...coursesAsync.maybeWhen(
                                data: (courses) => courses.map((c) => DropdownMenuItem<int?>(
                                  value: c.id,
                                  child: Text(c.name, overflow: TextOverflow.ellipsis),
                                )),
                                orElse: () => <DropdownMenuItem<int?>>[],
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              _selectedCourseId = v;
                              _currentPage = 0;
                            }),
                            icon: const Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textMuted),
                          ),
                        ),
                      ),
                      // Academic Year Filter Dropdown
                      Container(
                        height: 40,
                        width: isMobile ? double.infinity : 150,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            isExpanded: true,
                            value: _selectedYear,
                            items: const [
                              DropdownMenuItem<int?>(value: null, child: Text('All Years')),
                              DropdownMenuItem<int?>(value: 1, child: Text('Year 1')),
                              DropdownMenuItem<int?>(value: 2, child: Text('Year 2')),
                              DropdownMenuItem<int?>(value: 3, child: Text('Year 3')),
                              DropdownMenuItem<int?>(value: 4, child: Text('Year 4')),
                            ],
                            onChanged: (v) => setState(() {
                              _selectedYear = v;
                              _currentPage = 0;
                            }),
                            icon: const Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textMuted),
                          ),
                        ),
                      ),
                      // Status / Deleted Filter Dropdown
                      Container(
                        height: 40,
                        width: isMobile ? double.infinity : 170,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _statusFilter,
                            items: const [
                              DropdownMenuItem(value: 'active', child: Text('Active Students', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'completed', child: Text('Completed Students', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'discontinued', child: Text('Discontinued Students', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'tc_issued', child: Text('TC Issued Students', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'all', child: Text('All Students', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'deleted', child: Text('Deleted Students', overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _statusFilter = v;
                                  _currentPage = 0;
                                });
                              }
                            },
                            icon: const Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textMuted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content (Mobile Cards or Desktop Table)
                Expanded(
                  child: studentsAsync.when(
                    data: (students) {
                      if (students.isEmpty) {
                        return EmptyState(
                          title: _statusFilter == 'deleted' ? 'No Deleted Students' : 'No Students Found',
                          message: _statusFilter == 'deleted' 
                              ? 'There are no deleted or archived students.' 
                              : 'There are no students matching your criteria.',
                          icon: LucideIcons.users,
                        );
                      }

                      // Mobile Card View: Zero horizontal scrolling!
                      if (isMobile) {
                        return ListView.separated(
                          itemCount: students.length,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final s = students[index];
                            final courseName = courseMap[s.courseId] ?? (s.courseId != null ? 'Course #${s.courseId}' : 'N/A');
                            final batch = s.batchId != null ? batchesMap[s.batchId] : null;
                            final isDeleted = s.deletedAt != null || _statusFilter == 'deleted';

                            BadgeStatus badgeStatus = BadgeStatus.success;
                            String badgeText = s.status.toUpperCase();
                            if (isDeleted) {
                              badgeStatus = BadgeStatus.danger;
                              badgeText = 'DELETED';
                            } else if (s.status == 'completed') {
                              badgeStatus = BadgeStatus.info;
                            } else if (s.status == 'discontinued') {
                              badgeStatus = BadgeStatus.neutral;
                            } else if (s.status == 'tc_issued') {
                              badgeStatus = BadgeStatus.warning;
                            }

                            return _buildMobileStudentCard(
                              context,
                              s: s,
                              courseName: courseName,
                              batch: batch,
                              isDeleted: isDeleted,
                              badgeText: badgeText,
                              badgeStatus: badgeStatus,
                            );
                          },
                        );
                      }

                      // Desktop Table View
                      return AppDataTable<Student>(
                        columns: const ['Adm. No', 'Student', 'Course', 'Batch / Semester', 'Status', 'Actions'],
                        flexes: const [2, 4, 3, 3, 2, 3],
                        data: students,
                        emptyState: EmptyState(
                          title: _statusFilter == 'deleted' ? 'No Deleted Students' : 'No Students Found',
                          message: _statusFilter == 'deleted' 
                              ? 'There are no deleted or archived students.' 
                              : 'There are no students matching your criteria.',
                          icon: LucideIcons.users,
                        ),
                        rowBuilder: (context, s) {
                          final courseName = courseMap[s.courseId] ?? (s.courseId != null ? 'Course #${s.courseId}' : 'N/A');
                          final batch = s.batchId != null ? batchesMap[s.batchId] : null;
                          final isDeleted = s.deletedAt != null || _statusFilter == 'deleted';

                          BadgeStatus badgeStatus = BadgeStatus.success;
                          String badgeText = s.status.toUpperCase();
                          if (isDeleted) {
                            badgeStatus = BadgeStatus.danger;
                            badgeText = 'DELETED';
                          } else if (s.status == 'completed') {
                            badgeStatus = BadgeStatus.info;
                          } else if (s.status == 'discontinued') {
                            badgeStatus = BadgeStatus.neutral;
                          } else if (s.status == 'tc_issued') {
                            badgeStatus = BadgeStatus.warning;
                          }

                          return Row(
                            children: [
                              Expanded(flex: 2, child: Text(s.admissionNumber ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w500))),
                              Expanded(flex: 4, child: Row(
                                children: [
                                  AppAvatar(name: s.name, radius: 18),
                                  const SizedBox(width: AppSpacing.md),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textStrong)),
                                      Text('${s.phone ?? 'No phone'} • ${s.gender ?? 'Male'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                    ],
                                  ),
                                ],
                              )),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  courseName,
                                  style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.textStrong),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: batch != null
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            batch.batchName,
                                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: AppColors.textStrong),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.brand.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: AppColors.brand.withOpacity(0.2)),
                                            ),
                                            child: Text(
                                              'Sem ${batch.currentSemester} (Yr ${batch.currentYear})',
                                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.brand),
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Text('No Batch', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              ),
                              Expanded(
                                flex: 2, 
                                child: Align(
                                  alignment: Alignment.centerLeft, 
                                  child: StatusBadge(text: badgeText, status: badgeStatus),
                                ),
                              ),
                              Expanded(flex: 3, child: Align(
                                alignment: Alignment.centerLeft,
                                child: isDeleted
                                    ? OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.success.base,
                                          side: BorderSide(color: AppColors.success.base.withOpacity(0.5)),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () => _confirmRestoreStudent(context, s),
                                        icon: const Icon(LucideIcons.rotateCcw, size: 14),
                                        label: const Text('Restore', style: TextStyle(fontSize: 12)),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextButton(
                                            onPressed: () {
                                              Navigator.push(context, MaterialPageRoute(builder: (c) => StudentProfileScreen(student: s)));
                                            },
                                            child: const Text('View Profile'),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            icon: Icon(LucideIcons.trash2, size: 16, color: AppColors.danger.base),
                                            tooltip: 'Delete Student',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () => _confirmDeleteStudent(context, s),
                                          ),
                                        ],
                                      ),
                              )),
                            ],
                          );
                        },
                      );
                    },
                    loading: () => ListView.separated(
                      itemCount: 5,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      separatorBuilder: (_,__) => const Divider(),
                      itemBuilder: (_,__) => const SkeletonLoader(width: double.infinity, height: 40),
                    ),
                    error: (e, st) => EmptyState(title: 'Error', message: e.toString(), icon: LucideIcons.alertCircle),
                  ),
                ),

                // Pagination Footer
                countAsync.maybeWhen(
                  data: (total) {
                    final start = total == 0 ? 0 : (_currentPage * _pageSize) + 1;
                    final end = min((_currentPage + 1) * _pageSize, total);
                    final totalPages = max(1, (total / _pageSize).ceil());

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: AppColors.border)),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            total == 0 ? '0 students' : 'Showing $start - $end of $total students',
                            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(LucideIcons.chevronLeft, size: 18),
                                onPressed: _currentPage > 0
                                    ? () => setState(() => _currentPage--)
                                    : null,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  'Page ${_currentPage + 1} of $totalPages',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(LucideIcons.chevronRight, size: 18),
                                onPressed: (_currentPage + 1) < totalPages
                                    ? () => setState(() => _currentPage++)
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                  orElse: () => const SizedBox(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
