import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/daily_timetable.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/status_badge.dart';
import 'daily_timetable_export_helper.dart';
import 'exam_timetable_view.dart';

class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  int _scheduleMode = 0; // 0 = Daily Timetable, 1 = Exam Timetable

  // Date starts directly on TOMORROW
  late String _selectedDate;
  DailyTimetable? _currentTimetable;
  List<DailyTimetableEntry> _workingEntries = [];
  int? _selectedEntryIndex;
  bool _hasUnsavedChanges = false;
  bool _isLoading = true;

  final List<String> _courseOptions = [
    'DMLT',
    'DRT',
    'DOTAT',
    'B.Sc MLT',
    'B.Sc Medical Imaging',
    'Diploma in Dialysis Tech',
  ];

  final List<String> _yearOptions = [
    '1st Year',
    '2nd Year',
    '3rd Year',
  ];

  final List<String> _teacherOptions = [
    'Prof. Suresh Kumar',
    'Dr. Aysha Mariyam',
    'Prof. Fatima',
    'Dr. Alan Turing',
    'Prof. Abdul Rahman',
    'Dr. Salim PK',
    'Clinical Preceptor',
  ];

  final List<String> _roomOptions = [
    'LH-1',
    'LH-2',
    'LH-3',
    'Lab-A',
    'Lab-B',
    'OT-Lab',
    'X-Ray Lab',
    'Auditorium',
    'Seminar Hall',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = DailyTimetableService.getTomorrowDateString();
    _loadDateTimetable(_selectedDate);
  }

  Future<void> _loadDateTimetable(String date) async {
    setState(() => _isLoading = true);
    final tt = await DailyTimetableService.instance.getTimetableForDate(date);
    if (!mounted) return;
    setState(() {
      _selectedDate = date;
      _currentTimetable = tt;
      _workingEntries = List.from(tt.entries);
      _selectedEntryIndex = null;
      _hasUnsavedChanges = false;
      _isLoading = false;
    });
  }

  Future<bool> _promptUnsavedChangesGuard() async {
    if (!_hasUnsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: const Row(
          children: [
            Icon(LucideIcons.alertCircle, color: Colors.amber, size: 22),
            SizedBox(width: 8),
            Text('Unsaved Changes'),
          ],
        ),
        content: const Text(
          'You have unsaved changes in this timetable. Do you want to discard your edits and proceed?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel / Keep Editing')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard Changes'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _selectDate(BuildContext context) async {
    final currentDt = DateTime.tryParse(_selectedDate) ?? DateTime.now().add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDt,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );

    if (picked != null) {
      final newDateStr = "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      if (newDateStr != _selectedDate) {
        if (await _promptUnsavedChangesGuard()) {
          _loadDateTimetable(newDateStr);
        }
      }
    }
  }

  void _addRow() {
    final newEntry = DailyTimetableEntry(
      id: DateTime.now().microsecondsSinceEpoch,
      courseName: _courseOptions.first,
      year: _yearOptions.first,
      teacherName: _teacherOptions.first,
      subjectName: 'New Subject',
      classRoom: _roomOptions.first,
      startTime: '09:00 AM',
      endTime: '10:00 AM',
      sortOrder: _workingEntries.length + 1,
    );

    setState(() {
      _workingEntries.add(newEntry);
      _selectedEntryIndex = _workingEntries.length - 1;
      _hasUnsavedChanges = true;
    });
  }

  void _duplicateRow() {
    if (_selectedEntryIndex == null || _selectedEntryIndex! >= _workingEntries.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a row first to duplicate.')),
      );
      return;
    }
    final source = _workingEntries[_selectedEntryIndex!];
    final dup = source.copyWith(
      id: DateTime.now().microsecondsSinceEpoch,
      sortOrder: _workingEntries.length + 1,
    );

    setState(() {
      _workingEntries.add(dup);
      _selectedEntryIndex = _workingEntries.length - 1;
      _hasUnsavedChanges = true;
    });
  }

  void _deleteRow() {
    if (_selectedEntryIndex == null || _selectedEntryIndex! >= _workingEntries.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a row first to delete.')),
      );
      return;
    }

    setState(() {
      _workingEntries.removeAt(_selectedEntryIndex!);
      _selectedEntryIndex = null;
      _hasUnsavedChanges = true;
    });
  }

  Future<void> _copyFromPreviousDay() async {
    if (!await _promptUnsavedChangesGuard()) return;

    final copied = await DailyTimetableService.instance.copyFromPreviousDay(_selectedDate);
    if (!mounted) return;
    setState(() {
      _currentTimetable = copied;
      _workingEntries = List.from(copied.entries);
      _selectedEntryIndex = null;
      _hasUnsavedChanges = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Schedule copied from previous day into current draft!'),
        backgroundColor: AppColors.success.base,
      ),
    );
  }

  Future<void> _saveDraft() async {
    await DailyTimetableService.instance.saveDraft(_selectedDate, _workingEntries);
    final updated = await DailyTimetableService.instance.getTimetableForDate(_selectedDate);
    if (!mounted) return;
    setState(() {
      _currentTimetable = updated;
      _hasUnsavedChanges = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Timetable draft for $_selectedDate saved successfully.'),
        backgroundColor: AppColors.success.base,
      ),
    );
  }

  Future<void> _showPublishDialog() async {
    bool notifyUsers = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          title: const Row(
            children: [
              Icon(LucideIcons.checkCircle2, color: Colors.green, size: 22),
              SizedBox(width: 8),
              Text('Publish Timetable'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to publish the timetable for $_selectedDate?\n\nOnce published, it will be visible on the Student and Faculty portal.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: notifyUsers,
                contentPadding: EdgeInsets.zero,
                title: const Text('Notify students and teachers', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: const Text('Sends an automated timetable alert to enrolled cohorts', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                onChanged: (val) => setDlg(() => notifyUsers = val ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(LucideIcons.send, size: 16),
              label: const Text('Publish Schedule'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await DailyTimetableService.instance.publish(_selectedDate, _workingEntries, notifyUsers: notifyUsers);
      final updated = await DailyTimetableService.instance.getTimetableForDate(_selectedDate);
      if (!mounted) return;
      setState(() {
        _currentTimetable = updated;
        _hasUnsavedChanges = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Timetable for $_selectedDate published! (Notifications sent: ${notifyUsers ? "Yes" : "No"})'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _unpublish() async {
    await DailyTimetableService.instance.unpublish(_selectedDate);
    final updated = await DailyTimetableService.instance.getTimetableForDate(_selectedDate);
    if (!mounted) return;
    setState(() {
      _currentTimetable = updated;
      _hasUnsavedChanges = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Timetable for $_selectedDate has been unpublished and moved to Draft.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _exportPdf() {
    if (_currentTimetable == null) return;
    final effective = _currentTimetable!.copyWith(entries: _workingEntries);
    DailyTimetableExportHelper.exportPdf(effective);
  }

  void _exportExcel() async {
    if (_currentTimetable == null) return;
    final effective = _currentTimetable!.copyWith(entries: _workingEntries);
    final bytes = await DailyTimetableExportHelper.exportExcel(effective);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel spreadsheet generated (${bytes.lengthInBytes} bytes). Saved to downloads.'),
          backgroundColor: AppColors.success.base,
        ),
      );
    }
  }

  void _openMobileEditSheet(int index) {
    final entry = _workingEntries[index];
    final courseCtrl = TextEditingController(text: entry.courseName);
    final yearCtrl = TextEditingController(text: entry.year);
    final teacherCtrl = TextEditingController(text: entry.teacherName);
    final subjectCtrl = TextEditingController(text: entry.subjectName);
    final roomCtrl = TextEditingController(text: entry.classRoom);
    final startCtrl = TextEditingController(text: entry.startTime);
    final endCtrl = TextEditingController(text: entry.endTime);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Edit Schedule Row', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  IconButton(icon: const Icon(LucideIcons.x, size: 20), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _courseOptions.contains(courseCtrl.text) ? courseCtrl.text : _courseOptions.first,
                decoration: const InputDecoration(labelText: 'Course'),
                items: _courseOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => courseCtrl.text = v ?? '',
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _yearOptions.contains(yearCtrl.text) ? yearCtrl.text : _yearOptions.first,
                decoration: const InputDecoration(labelText: 'Academic Year'),
                items: _yearOptions.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                onChanged: (v) => yearCtrl.text = v ?? '',
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _teacherOptions.contains(teacherCtrl.text) ? teacherCtrl.text : _teacherOptions.first,
                decoration: const InputDecoration(labelText: 'Teacher / Faculty'),
                items: _teacherOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => teacherCtrl.text = v ?? '',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: subjectCtrl,
                decoration: const InputDecoration(labelText: 'Subject Name'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _roomOptions.contains(roomCtrl.text) ? roomCtrl.text : _roomOptions.first,
                decoration: const InputDecoration(labelText: 'Class / Room'),
                items: _roomOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => roomCtrl.text = v ?? '',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: startCtrl,
                      decoration: const InputDecoration(labelText: 'Start Time (e.g. 09:00 AM)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: endCtrl,
                      decoration: const InputDecoration(labelText: 'End Time (e.g. 10:00 AM)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(LucideIcons.check, size: 16),
                  label: const Text('Apply Changes'),
                  onPressed: () {
                    setState(() {
                      _workingEntries[index] = entry.copyWith(
                        courseName: courseCtrl.text,
                        year: yearCtrl.text,
                        teacherName: teacherCtrl.text,
                        subjectName: subjectCtrl.text,
                        classRoom: roomCtrl.text,
                        startTime: startCtrl.text,
                        endTime: endCtrl.text,
                      );
                      _hasUnsavedChanges = true;
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    final tomorrowStr = DailyTimetableService.getTomorrowDateString();
    final todayStr = DailyTimetableService.getTodayDateString();
    final isTomorrow = _selectedDate == tomorrowStr;
    final isToday = _selectedDate == todayStr;

    final clashes = DailyTimetableClashHelper.detectClashes(_workingEntries);
    final status = _currentTimetable?.status ?? 'not_created';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              PageHeader(
                title: 'Timetable Scheduling',
                subtitle: 'Daily lecture scheduling, teacher conflict monitoring, and instant publication',
                actions: [
                  if (_scheduleMode == 0) ...[
                    OutlinedButton.icon(
                      icon: const Icon(LucideIcons.fileSpreadsheet, size: 16),
                      label: const Text('Export Excel'),
                      onPressed: _exportExcel,
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(LucideIcons.fileText, size: 16),
                      label: const Text('Export PDF'),
                      onPressed: _exportPdf,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Mode Switcher: Daily Class Timetable vs Examination Schedule
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    avatar: Icon(LucideIcons.calendarDays, size: 16, color: _scheduleMode == 0 ? Colors.white : AppColors.brand),
                    label: const Text('Daily Timetable (Tomorrow Focus)'),
                    selected: _scheduleMode == 0,
                    selectedColor: AppColors.brand,
                    labelStyle: TextStyle(
                      color: _scheduleMode == 0 ? Colors.white : AppColors.textStrong,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _scheduleMode = 0);
                    },
                  ),
                  ChoiceChip(
                    avatar: Icon(LucideIcons.fileCheck2, size: 16, color: _scheduleMode == 1 ? Colors.white : Colors.indigo),
                    label: const Text('Examination Timetable'),
                    selected: _scheduleMode == 1,
                    selectedColor: Colors.indigo,
                    labelStyle: TextStyle(
                      color: _scheduleMode == 1 ? Colors.white : AppColors.textStrong,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _scheduleMode = 1);
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              if (_scheduleMode == 1) ...[
                const ExamTimetableScheduleView(),
              ] else ...[
                // Top Date Selector & Status Bar
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          // Small date field and label
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              InkWell(
                                onTap: () => _selectDate(context),
                                borderRadius: BorderRadius.circular(AppRadius.control),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(AppRadius.control),
                                    border: Border.all(color: AppColors.brand, width: 1.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(LucideIcons.calendar, size: 16, color: AppColors.brand),
                                      const SizedBox(width: 8),
                                      Text(
                                        _selectedDate,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textStrong),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(LucideIcons.chevronDown, size: 14, color: AppColors.textMuted),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (isTomorrow)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                                  ),
                                  child: const Text('TOMORROW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
                                )
                              else if (isToday)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                                  ),
                                  child: const Text('TODAY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal)),
                                ),
                              const SizedBox(width: 14),
                              // Status Chip (Draft, Published, Not Created)
                              if (status == 'published')
                                StatusBadge(text: 'PUBLISHED', status: BadgeStatus.success)
                              else if (status == 'draft')
                                StatusBadge(text: 'DRAFT (Unpublished)', status: BadgeStatus.warning)
                              else
                                StatusBadge(text: 'NOT CREATED', status: BadgeStatus.draft),
                              if (_hasUnsavedChanges) ...[
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('Unsaved edits', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),

                          // Short "Recent timetables" pills (last 7 dates)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('Recent:', style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                              ...DailyTimetableService.getRecentDates().take(4).map((d) {
                                final isSel = d == _selectedDate;
                                return InkWell(
                                  onTap: () async {
                                    if (d != _selectedDate) {
                                      if (await _promptUnsavedChangesGuard()) {
                                        _loadDateTimetable(d);
                                      }
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSel ? AppColors.brand : AppColors.surface,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: isSel ? AppColors.brand : AppColors.border),
                                    ),
                                    child: Text(
                                      d.substring(5), // MM-DD
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                        color: isSel ? Colors.white : AppColors.textStrong,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Action Buttons Row:
                      // Add row, Duplicate row, Delete row, Copy from previous day, Save draft, Publish, Unpublish
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _addRow,
                            icon: const Icon(LucideIcons.plus, size: 15),
                            label: const Text('Add Row'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: Colors.white),
                          ),
                          OutlinedButton.icon(
                            onPressed: _duplicateRow,
                            icon: const Icon(LucideIcons.copy, size: 15),
                            label: const Text('Duplicate Row'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _deleteRow,
                            icon: const Icon(LucideIcons.trash2, size: 15, color: Colors.red),
                            label: const Text('Delete Row', style: TextStyle(color: Colors.red)),
                          ),
                          OutlinedButton.icon(
                            onPressed: _copyFromPreviousDay,
                            icon: const Icon(LucideIcons.history, size: 15),
                            label: const Text('Copy from Previous Day'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _saveDraft,
                            icon: const Icon(LucideIcons.save, size: 15),
                            label: const Text('Save Draft'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
                          ),
                          if (status != 'published')
                            ElevatedButton.icon(
                              onPressed: _showPublishDialog,
                              icon: const Icon(LucideIcons.send, size: 15),
                              label: const Text('Publish'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: _unpublish,
                              icon: const Icon(LucideIcons.archive, size: 15, color: Colors.orange),
                              label: const Text('Unpublish', style: TextStyle(color: Colors.orange)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Inline Clash Warnings (Non-blocking warnings only)
                if (clashes.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(LucideIcons.alertTriangle, size: 18, color: Colors.amber),
                            SizedBox(width: 8),
                            Text(
                              'Schedule Clash Warnings (Advisory Only):',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ...clashes.map((msg) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                              Expanded(child: Text(msg, style: const TextStyle(fontSize: 12, color: AppColors.textStrong))),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],

                // Timetable Content Area (Table on Desktop/Tablet, Cards on Phone)
                if (_isLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
                else if (_workingEntries.isEmpty)
                  SectionCard(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            const Icon(LucideIcons.calendarX, size: 48, color: AppColors.textMuted),
                            const SizedBox(height: 12),
                            Text('No classes scheduled for $_selectedDate', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 6),
                            const Text('Click "Add Row" or "Copy from Previous Day" to design the timetable.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _addRow,
                              icon: const Icon(LucideIcons.plus, size: 16),
                              label: const Text('Add First Class'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (isMobile) ...[
                  // Phone Friendly: Cards with Edit Sheet
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _workingEntries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, idx) {
                      final e = _workingEntries[idx];
                      final isSelected = _selectedEntryIndex == idx;

                      return InkWell(
                        onTap: () {
                          setState(() => _selectedEntryIndex = idx);
                          _openMobileEditSheet(idx);
                        },
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.brand.withValues(alpha: 0.05) : AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border.all(color: isSelected ? AppColors.brand : AppColors.border, width: isSelected ? 1.5 : 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(LucideIcons.clock, size: 14, color: AppColors.brand),
                                      const SizedBox(width: 6),
                                      Text('${e.startTime} - ${e.endTime}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: AppColors.courses.tint, borderRadius: BorderRadius.circular(4)),
                                    child: Text('${e.courseName} (${e.year})', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.courses.base)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(e.subjectName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(LucideIcons.user, size: 13, color: AppColors.textMuted),
                                      const SizedBox(width: 4),
                                      Text(e.teacherName, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      const Icon(LucideIcons.mapPin, size: 13, color: AppColors.textMuted),
                                      const SizedBox(width: 4),
                                      Text(e.classRoom, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textStrong)),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ] else ...[
                  // Desktop & Tablet: Rich Editable Table
                  SectionCard(
                    padding: EdgeInsets.zero,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final tableWidth = constraints.maxWidth < 1000 ? 1000.0 : constraints.maxWidth;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: tableWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Table Headers
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: const BoxDecoration(
                                    color: AppColors.bg,
                                    border: Border(bottom: BorderSide(color: AppColors.border)),
                                  ),
                                  child: const Row(
                                    children: [
                                      SizedBox(width: 36, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                      Expanded(flex: 3, child: Text('COURSE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                      Expanded(flex: 2, child: Text('YEAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                      Expanded(flex: 4, child: Text('SUBJECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                      Expanded(flex: 4, child: Text('TEACHER / FACULTY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                      Expanded(flex: 2, child: Text('CLASS / ROOM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                      Expanded(flex: 2, child: Text('START TIME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                      Expanded(flex: 2, child: Text('END TIME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                    ],
                                  ),
                                ),

                                // Table Rows
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _workingEntries.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (ctx, idx) {
                                    final entry = _workingEntries[idx];
                                    final isSelected = _selectedEntryIndex == idx;

                                    return InkWell(
                                      onTap: () => setState(() => _selectedEntryIndex = idx),
                                      child: Container(
                                        color: isSelected ? AppColors.brand.withValues(alpha: 0.06) : Colors.transparent,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 36,
                                              child: Text('${idx + 1}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                            ),
                                            // Course
                                            Expanded(
                                              flex: 3,
                                              child: DropdownButtonFormField<String>(
                                                initialValue: _courseOptions.contains(entry.courseName) ? entry.courseName : _courseOptions.first,
                                                isExpanded: true,
                                                isDense: true,
                                                decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
                                                items: _courseOptions.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                                                onChanged: (v) {
                                                  if (v != null) {
                                                    setState(() {
                                                      _workingEntries[idx] = entry.copyWith(courseName: v);
                                                      _hasUnsavedChanges = true;
                                                    });
                                                  }
                                                },
                                              ),
                                            ),
                                            // Year
                                            Expanded(
                                              flex: 2,
                                              child: DropdownButtonFormField<String>(
                                                initialValue: _yearOptions.contains(entry.year) ? entry.year : _yearOptions.first,
                                                isExpanded: true,
                                                isDense: true,
                                                decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
                                                items: _yearOptions.map((y) => DropdownMenuItem(value: y, child: Text(y, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                                                onChanged: (v) {
                                                  if (v != null) {
                                                    setState(() {
                                                      _workingEntries[idx] = entry.copyWith(year: v);
                                                      _hasUnsavedChanges = true;
                                                    });
                                                  }
                                                },
                                              ),
                                            ),
                                            // Subject
                                            Expanded(
                                              flex: 4,
                                              child: TextFormField(
                                                initialValue: entry.subjectName,
                                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                                decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                                                onChanged: (v) {
                                                  _workingEntries[idx] = entry.copyWith(subjectName: v);
                                                  _hasUnsavedChanges = true;
                                                },
                                              ),
                                            ),
                                            // Teacher
                                            Expanded(
                                              flex: 4,
                                              child: DropdownButtonFormField<String>(
                                                initialValue: _teacherOptions.contains(entry.teacherName) ? entry.teacherName : _teacherOptions.first,
                                                isExpanded: true,
                                                isDense: true,
                                                decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
                                                items: _teacherOptions.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                                                onChanged: (v) {
                                                  if (v != null) {
                                                    setState(() {
                                                      _workingEntries[idx] = entry.copyWith(teacherName: v);
                                                      _hasUnsavedChanges = true;
                                                    });
                                                  }
                                                },
                                              ),
                                            ),
                                            // Class / Room
                                            Expanded(
                                              flex: 2,
                                              child: DropdownButtonFormField<String>(
                                                initialValue: _roomOptions.contains(entry.classRoom) ? entry.classRoom : _roomOptions.first,
                                                isExpanded: true,
                                                isDense: true,
                                                decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
                                                items: _roomOptions.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                                                onChanged: (v) {
                                                  if (v != null) {
                                                    setState(() {
                                                      _workingEntries[idx] = entry.copyWith(classRoom: v);
                                                      _hasUnsavedChanges = true;
                                                    });
                                                  }
                                                },
                                              ),
                                            ),
                                            // Start Time
                                            Expanded(
                                              flex: 2,
                                              child: TextFormField(
                                                initialValue: entry.startTime,
                                                style: const TextStyle(fontSize: 13),
                                                decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                                                onChanged: (v) {
                                                  _workingEntries[idx] = entry.copyWith(startTime: v);
                                                  _hasUnsavedChanges = true;
                                                },
                                              ),
                                            ),
                                            // End Time
                                            Expanded(
                                              flex: 2,
                                              child: TextFormField(
                                                initialValue: entry.endTime,
                                                style: const TextStyle(fontSize: 13),
                                                decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                                                onChanged: (v) {
                                                  _workingEntries[idx] = entry.copyWith(endTime: v);
                                                  _hasUnsavedChanges = true;
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
