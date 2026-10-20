import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/batch.dart';
import '../../core/models/course.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_data_table.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/status_badge.dart';
import '../courses/course_provider.dart';
import 'batch_completion_dialog.dart';
import 'reopen_batch_dialog.dart';
import 'semester_promotion_dialog.dart';
import 'year_promotion_dialog.dart';
import 'semester_dates_dialog.dart';
import '../students/student_provider.dart';

final showCompletedBatchesProvider = StateProvider<bool>((ref) => false);
final selectedCourseFilterProvider = StateProvider<int?>((ref) => null);
final batchSearchQueryProvider = StateProvider<String>((ref) => '');
final promotedYearsProvider = StateProvider<Map<int, int>>((ref) => {});

final batchesListProvider = FutureProvider<List<Batch>>((ref) async {
  final repo = ref.watch(batchRepositoryProvider);
  final showCompleted = ref.watch(showCompletedBatchesProvider);
  final courseId = ref.watch(selectedCourseFilterProvider);

  return repo.getBatches(
    courseId: courseId,
    includeCompleted: showCompleted,
  );
});

class BatchesScreen extends ConsumerStatefulWidget {
  const BatchesScreen({super.key});

  @override
  ConsumerState<BatchesScreen> createState() => _BatchesScreenState();
}

class _BatchesScreenState extends ConsumerState<BatchesScreen> {
  void _openAddBatchDialog(List<Course> courses) {
    if (courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create a course before adding a batch.')),
      );
      return;
    }

    final nameController = TextEditingController();
    int selectedCourseId = courses.first.id!;
    int startYear = DateTime.now().year;
    int endYear = DateTime.now().year + 2;
    int initialPeriod = 1;
    DateTime periodStartDate = DateTime.now();
    final dateFormat = DateFormat('yyyy-MM-dd');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedCourse = courses.firstWhere(
            (c) => c.id == selectedCourseId,
            orElse: () => courses.first,
          );

          final int maxPeriods = selectedCourse.isYearWise
              ? selectedCourse.durationYears
              : (selectedCourse.isSemesterWise ? selectedCourse.periodsCount : 1);

          if (initialPeriod > maxPeriods) {
            initialPeriod = 1;
          }

          final derivedYear = selectedCourse.isYearWise
              ? initialPeriod
              : ((initialPeriod + 1) ~/ 2);

          return AlertDialog(
            title: const Text('Add New Batch'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Course *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      value: selectedCourseId,
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: courses.map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text('${c.name} (${c.structure.toUpperCase()})'),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedCourseId = val;
                            initialPeriod = 1;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text('Batch Name *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Batch 2024-26 (A)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Start Year', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<int>(
                                value: startYear,
                                decoration: const InputDecoration(border: OutlineInputBorder()),
                                items: List.generate(10, (i) => 2020 + i).map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                                onChanged: (v) {
                                  if (v != null) setDialogState(() => startYear = v);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('End Year', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<int>(
                                value: endYear,
                                decoration: const InputDecoration(border: OutlineInputBorder()),
                                items: List.generate(10, (i) => 2022 + i).map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                                onChanged: (v) {
                                  if (v != null) setDialogState(() => endYear = v);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Current Period & Period Start Date
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedCourse.isYearWise
                                    ? 'Initial Year *'
                                    : (selectedCourse.isSemesterWise ? 'Initial Semester *' : 'Initial Period *'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 6),
                              if (selectedCourse.isSingle)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade400),
                                    borderRadius: BorderRadius.circular(4),
                                    color: Colors.grey.shade100,
                                  ),
                                  child: const Text('Single Period (1)', style: TextStyle(fontSize: 13)),
                                )
                              else
                                DropdownButtonFormField<int>(
                                  value: initialPeriod,
                                  decoration: const InputDecoration(border: OutlineInputBorder()),
                                  items: List.generate(maxPeriods, (i) => i + 1).map((p) {
                                    final label = selectedCourse.isYearWise
                                        ? 'Year $p'
                                        : 'Semester $p';
                                    return DropdownMenuItem(value: p, child: Text(label));
                                  }).toList(),
                                  onChanged: (v) {
                                    if (v != null) setDialogState(() => initialPeriod = v);
                                  },
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Period Start Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: periodStartDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) {
                                    setDialogState(() => periodStartDate = picked);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade400),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(dateFormat.format(periodStartDate), style: const TextStyle(fontSize: 13)),
                                      const Icon(LucideIcons.calendar, size: 16, color: AppColors.textMuted),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Academic Year: Year $derivedYear (${selectedCourse.structure.toUpperCase()}-wise)',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: Colors.white),
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx);

                  int curSem = 1;
                  int curYr = 1;
                  if (selectedCourse.isYearWise) {
                    curYr = initialPeriod;
                    curSem = initialPeriod * 2;
                  } else if (selectedCourse.isSingle) {
                    curYr = 1;
                    curSem = 1;
                  } else {
                    curSem = initialPeriod;
                    curYr = (initialPeriod + 1) ~/ 2;
                  }

                  final newBatch = Batch(
                    courseId: selectedCourseId,
                    batchName: name,
                    startYear: startYear,
                    endYear: endYear,
                    currentSemester: curSem,
                    currentYear: curYr,
                    startDate: dateFormat.format(periodStartDate),
                    endDate: '$endYear-06-30',
                  );

                  await ref.read(batchRepositoryProvider).createBatch(newBatch);
                  ref.invalidate(batchesListProvider);
                },
                child: const Text('Create Batch'),
              ),
            ],
          );
        },
      ),
    );
  }

  int _getBatchYearNumber(Batch b) {
    return b.currentYear;
  }

  String _formatSemesterAndYear(Batch b, Course? course) {
    if (course?.isYearWise == true) {
      return 'Year ${b.currentYear}';
    } else if (course?.isSingle == true) {
      return 'Year ${b.currentYear} (Single)';
    }
    return 'Semester ${b.currentSemester} (Year ${b.currentYear})';
  }

  bool _isLastPeriod(Batch b, Course? course) {
    if (course == null) return false;
    if (course.isYearWise) {
      return b.currentYear >= course.durationYears;
    } else if (course.isSingle) {
      return true;
    } else {
      return b.currentSemester >= course.periodsCount;
    }
  }

  Future<void> _confirmAndPromoteBatch(Batch b, Course? course) async {
    if (course?.isYearWise == true) {
      await YearPromotionDialog.show(
        context,
        batch: b,
        onPromoted: () {
          ref.invalidate(batchesListProvider);
          ref.invalidate(allBatchesProvider);
          ref.invalidate(batchesMapProvider);
        },
      );
    } else {
      await SemesterPromotionDialog.show(
        context,
        batch: b,
        onPromoted: () {
          ref.invalidate(batchesListProvider);
          ref.invalidate(allBatchesProvider);
          ref.invalidate(batchesMapProvider);
        },
      );
    }
  }

  Future<void> _openSemesterDatesDialog(Batch b) async {
    await SemesterDatesDialog.show(
      context,
      batch: b,
      onUpdated: () {
        ref.invalidate(batchesListProvider);
        ref.invalidate(allBatchesProvider);
        ref.invalidate(batchesMapProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final batchesAsync = ref.watch(batchesListProvider);
    final coursesAsync = ref.watch(coursesProvider);
    final showCompleted = ref.watch(showCompletedBatchesProvider);
    final selectedCourseId = ref.watch(selectedCourseFilterProvider);
    final searchQuery = ref.watch(batchSearchQueryProvider).toLowerCase();

    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Page Header
            PageHeader(
              title: 'Batches & Cohorts',
              subtitle: 'Manage academic batches, mark batch completion, and view enrollment cohorts',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: Colors.white),
                  onPressed: () => _openAddBatchDialog(coursesAsync.value ?? []),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('Add Batch'),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            // Filter & Search Toolbar
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.border),
              ),
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SearchField(
                          hint: 'Search batch name...',
                          onChanged: (v) => ref.read(batchSearchQueryProvider.notifier).state = v.trim(),
                        ),
                        const SizedBox(height: 10),
                        coursesAsync.maybeWhen(
                          data: (courses) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(AppRadius.control),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int?>(
                                value: selectedCourseId,
                                isExpanded: true,
                                hint: const Text('All Courses', style: TextStyle(fontSize: 13)),
                                items: [
                                  const DropdownMenuItem<int?>(value: null, child: Text('All Courses')),
                                  ...courses.map((c) => DropdownMenuItem<int?>(
                                    value: c.id,
                                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                                  )),
                                ],
                                onChanged: (v) => ref.read(selectedCourseFilterProvider.notifier).state = v,
                              ),
                            ),
                          ),
                          orElse: () => const SizedBox(),
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () {
                            ref.read(showCompletedBatchesProvider.notifier).state = !showCompleted;
                          },
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: showCompleted ? Colors.blue.withOpacity(0.08) : Colors.transparent,
                              border: Border.all(color: showCompleted ? Colors.blue : AppColors.border),
                              borderRadius: BorderRadius.circular(AppRadius.control),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  showCompleted ? LucideIcons.checkSquare : LucideIcons.square,
                                  size: 16,
                                  color: showCompleted ? Colors.blue : AppColors.textMuted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Show Completed Batches',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: showCompleted ? FontWeight.bold : FontWeight.w500,
                                      color: showCompleted ? Colors.blue[900] : AppColors.textStrong,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        // Search
                        SizedBox(
                          width: 280,
                          child: SearchField(
                            hint: 'Search batch name...',
                            onChanged: (v) => ref.read(batchSearchQueryProvider.notifier).state = v.trim(),
                          ),
                        ),

                        // Course Dropdown
                        coursesAsync.maybeWhen(
                          data: (courses) => Container(
                            width: 240,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(AppRadius.control),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int?>(
                                value: selectedCourseId,
                                isExpanded: true,
                                hint: const Text('All Courses', style: TextStyle(fontSize: 13)),
                                items: [
                                  const DropdownMenuItem<int?>(value: null, child: Text('All Courses')),
                                  ...courses.map((c) => DropdownMenuItem<int?>(
                                    value: c.id,
                                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                                  )),
                                ],
                                onChanged: (v) => ref.read(selectedCourseFilterProvider.notifier).state = v,
                              ),
                            ),
                          ),
                          orElse: () => const SizedBox(),
                        ),

                        // "Show Completed" Toggle (Hides completed by default!)
                        InkWell(
                          onTap: () {
                            ref.read(showCompletedBatchesProvider.notifier).state = !showCompleted;
                          },
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: showCompleted ? Colors.blue.withOpacity(0.08) : Colors.transparent,
                              border: Border.all(color: showCompleted ? Colors.blue : AppColors.border),
                              borderRadius: BorderRadius.circular(AppRadius.control),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  showCompleted ? LucideIcons.checkSquare : LucideIcons.square,
                                  size: 16,
                                  color: showCompleted ? Colors.blue : AppColors.textMuted,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Show Completed Batches',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: showCompleted ? FontWeight.bold : FontWeight.w500,
                                    color: showCompleted ? Colors.blue[900] : AppColors.textStrong,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Content List
            Expanded(
              child: batchesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error loading batches: $err', style: const TextStyle(color: Colors.red))),
                data: (allBatches) {
                  final courses = coursesAsync.value ?? [];
                  final courseMap = {for (final c in courses) c.id: c.name};

                  final filtered = allBatches.where((b) {
                    if (searchQuery.isNotEmpty && !b.batchName.toLowerCase().contains(searchQuery)) {
                      return false;
                    }
                    return true;
                  }).toList();

                  if (filtered.isEmpty) {
                    return SectionCard(
                      child: EmptyState(
                        title: 'No Batches Found',
                        message: showCompleted
                            ? 'No batches match your filter.'
                            : 'No active batches found. Toggle "Show Completed Batches" or create a new batch.',
                        icon: LucideIcons.layers,
                      ),
                    );
                  }

                  // Mobile Layout: Cards
                  if (isMobile) {
                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (ctx, index) {
                        final b = filtered[index];
                        final cName = courseMap[b.courseId] ?? 'Course #${b.courseId}';
                        final isCompleted = b.status == 'completed';
                        final course = (coursesAsync.valueOrNull ?? []).firstWhere(
                          (c) => c.id == b.courseId,
                          orElse: () => Course(name: cName, code: '', duration: '2 Years'),
                        );
                        final isLastPeriod = _isLastPeriod(b, course);
                        final isSingleCourse = course.isSingle;
                        final isYearWise = course.isYearWise;

                        return Container(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                alignment: WrapAlignment.spaceBetween,
                                children: [
                                  Text(
                                    b.batchName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.brand.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AppColors.brand.withOpacity(0.3)),
                                        ),
                                        child: Text(
                                          _formatSemesterAndYear(b, course),
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.brand),
                                        ),
                                      ),
                                      StatusBadge(
                                        text: isCompleted ? 'COMPLETED' : 'ACTIVE',
                                        status: isCompleted ? BadgeStatus.info : BadgeStatus.success,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(cName, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                              if (isCompleted && b.completedOn != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Completed on ${b.completedOn}',
                                  style: const TextStyle(color: Colors.purple, fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ],
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.end,
                                children: [
                                  if (!isCompleted) ...[
                                    if (!isLastPeriod && !isSingleCourse)
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF2563EB),
                                          side: const BorderSide(color: Color(0xFF93C5FD)),
                                        ),
                                        onPressed: () => _confirmAndPromoteBatch(b, course),
                                        icon: const Icon(LucideIcons.arrowUpRight, size: 14),
                                        label: Text(
                                          isYearWise ? 'Promote to Next Year' : 'Promote to Next Semester',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.textStrong,
                                        side: const BorderSide(color: AppColors.border),
                                      ),
                                      onPressed: () => _openSemesterDatesDialog(b),
                                      icon: const Icon(LucideIcons.calendarRange, size: 14),
                                      label: const Text('Dates', style: TextStyle(fontSize: 12)),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isLastPeriod ? const Color(0xFF2563EB) : Colors.teal[700],
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => BatchCompletionDialog.show(
                                        context,
                                        batch: b,
                                        onCompleted: () => ref.invalidate(batchesListProvider),
                                      ),
                                      icon: const Icon(LucideIcons.checkCheck, size: 14),
                                      label: Text(isLastPeriod ? 'Mark batch completed' : 'Mark Completed', style: const TextStyle(fontSize: 12)),
                                    ),
                                  ] else
                                    OutlinedButton.icon(
                                      onPressed: () => ReopenBatchDialog.show(
                                        context,
                                        batch: b,
                                        onReopened: () => ref.invalidate(batchesListProvider),
                                      ),
                                      icon: const Icon(LucideIcons.rotateCcw, size: 14, color: Colors.orange),
                                      label: const Text('Reopen Batch', style: TextStyle(color: Colors.orange, fontSize: 12)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }

                  // Desktop / Tablet Layout: AppDataTable
                  return AppDataTable<Batch>(
                    columns: const ['Batch Name', 'Course', 'Semester / Year', 'Status', 'Timeline', 'Actions'],
                    flexes: const [3, 2, 3, 2, 2, 6],
                    data: filtered,
                    rowBuilder: (context, b) {
                      final cName = courseMap[b.courseId] ?? 'Course #${b.courseId}';
                      final isCompleted = b.status == 'completed';
                      final course = (coursesAsync.valueOrNull ?? []).firstWhere(
                        (c) => c.id == b.courseId,
                        orElse: () => Course(name: cName, code: '', duration: '2 Years'),
                      );
                      final isLastPeriod = _isLastPeriod(b, course);
                      final isSingleCourse = course.isSingle;
                      final isYearWise = course.isYearWise;

                      return Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(b.batchName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                if (isCompleted && b.completedOn != null)
                                  Text('Completed: ${b.completedOn}', style: const TextStyle(color: Colors.purple, fontSize: 11)),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(cName, style: const TextStyle(fontSize: 13, color: AppColors.textStrong), overflow: TextOverflow.ellipsis),
                          ),
                          Expanded(
                            flex: 3,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.brand.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.brand.withOpacity(0.25)),
                                ),
                                child: Text(
                                  _formatSemesterAndYear(b, course),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.brand),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(
                                text: isCompleted ? 'COMPLETED' : 'ACTIVE',
                                status: isCompleted ? BadgeStatus.info : BadgeStatus.success,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              (b.startYear != null && b.endYear != null)
                                  ? '${b.startYear} - ${b.endYear}'
                                  : (b.startDate ?? 'N/A'),
                              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                            ),
                          ),
                          Expanded(
                            flex: 6,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                if (!isCompleted) ...[
                                  if (!isLastPeriod && !isSingleCourse) ...[
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF2563EB),
                                        side: const BorderSide(color: Color(0xFF93C5FD)),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () => _confirmAndPromoteBatch(b, course),
                                      icon: const Icon(LucideIcons.arrowUpRight, size: 13),
                                      label: Text(
                                        isYearWise ? 'Promote to Year ${b.currentYear + 1}' : 'Promote Semester',
                                        style: const TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.textStrong,
                                      side: const BorderSide(color: AppColors.border),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () => _openSemesterDatesDialog(b),
                                    icon: const Icon(LucideIcons.calendarRange, size: 13),
                                    label: const Text('Dates', style: TextStyle(fontSize: 11.5)),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isLastPeriod ? const Color(0xFF2563EB) : Colors.teal[700],
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () => BatchCompletionDialog.show(
                                      context,
                                      batch: b,
                                      onCompleted: () => ref.invalidate(batchesListProvider),
                                    ),
                                    icon: const Icon(LucideIcons.checkCheck, size: 13),
                                    label: Text(isLastPeriod ? 'Mark batch completed' : 'Mark Completed', style: const TextStyle(fontSize: 11.5)),
                                  ),
                                ] else
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.orange),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () => ReopenBatchDialog.show(
                                      context,
                                      batch: b,
                                      onReopened: () => ref.invalidate(batchesListProvider),
                                    ),
                                    icon: const Icon(LucideIcons.rotateCcw, size: 13, color: Colors.orange),
                                    label: const Text('Reopen', style: TextStyle(color: Colors.orange, fontSize: 11.5)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
