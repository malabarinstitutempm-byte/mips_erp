import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/kpi_card.dart';
import '../../shared/widgets/icon_tile.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/course_chip.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/form_section.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/filter_bar.dart';
import '../../shared/widgets/app_data_table.dart';
import '../../shared/widgets/progress_bar.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/toast.dart';
import '../../shared/widgets/stepper.dart';

class ComponentGalleryScreen extends StatefulWidget {
  const ComponentGalleryScreen({super.key});

  @override
  State<ComponentGalleryScreen> createState() => _ComponentGalleryScreenState();
}

class _ComponentGalleryScreenState extends State<ComponentGalleryScreen> {
  String _selectedFilter = 'All';
  List<int> _selectedItems = [];
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Component Gallery',
            subtitle: 'Phase 2: Verifying all reusable widgets in their various states',
          ),
          
          SectionCard(
            title: 'Badges, Chips, Avatars, Icons',
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                StatusBadge(text: 'Paid', status: BadgeStatus.success),
                StatusBadge(text: 'Pending', status: BadgeStatus.warning),
                StatusBadge(text: 'Overdue', status: BadgeStatus.danger),
                StatusBadge(text: 'Draft', status: BadgeStatus.draft),
                CourseChip(courseCode: 'DMLT', courseName: 'Diploma in Med Lab'),
                const AppAvatar(name: 'Rahul K'),
                const AppAvatar(name: 'Aisha M'),
                const AppAvatar(name: 'Zayed P'),
                IconTile(icon: LucideIcons.users, baseColor: AppColors.students.base, tintColor: AppColors.students.tint),
                IconTile(icon: LucideIcons.indianRupee, baseColor: AppColors.fees.base, tintColor: AppColors.fees.tint),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          SectionCard(
            title: 'KPI Cards & Progress Bars',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: KpiCard(title: 'Total Students', value: '248', icon: LucideIcons.users, baseColor: AppColors.students.base, tintColor: AppColors.students.tint)),
                    const SizedBox(width: 16),
                    Expanded(child: KpiCard(title: 'Total Collected', value: '₹18.4L', icon: LucideIcons.checkCircle, baseColor: AppColors.fees.base, tintColor: AppColors.fees.tint)),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Progress Bar (74%)'),
                const SizedBox(height: 8),
                ProgressBar(progress: 0.74),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SectionCard(
            title: 'Inputs & Steppers',
            child: Column(
              children: [
                FilterBar(
                  filters: const ['All', 'Active', 'Pending', 'Archived'],
                  selectedFilter: _selectedFilter,
                  onFilterSelected: (v) => setState(() => _selectedFilter = v),
                ),
                const SizedBox(height: 24),
                const SearchField(hint: 'Search gallery...'),
                const SizedBox(height: 24),
                const AppStepper(steps: ['Setup', 'Details', 'Confirm'], currentStep: 1),
                const SizedBox(height: 24),
                FormSection(
                  title: 'Form Section Example',
                  description: 'This groups related fields together cleanly.',
                  child: TextFormField(decoration: const InputDecoration(labelText: 'Sample Input')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          SectionCard(
            title: 'Dialogs & Toasts',
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    showDialog(context: context, builder: (_) => AppDialog(
                      title: 'Confirm Action',
                      content: const Text('Are you sure you want to perform this action?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Confirm')),
                      ],
                    ));
                  },
                  child: const Text('Show Dialog'),
                ),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: () => Toast.show(context, 'This is a successful toast message!'),
                  child: const Text('Show Success Toast'),
                ),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: () => Toast.show(context, 'This is an error message!', isError: true),
                  child: const Text('Show Error Toast'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SectionCard(
            title: 'AppDataTable (Loaded, Selectable, Paginated)',
            padding: EdgeInsets.zero,
            child: SizedBox(
              height: 300,
              child: AppDataTable<int>(
                columns: const ['ID', 'Name', 'Status'],
                flexes: const [1, 2, 1],
                data: const [1, 2, 3, 4, 5],
                selectable: true,
                selectedItems: _selectedItems,
                onSelectionChanged: (items) => setState(() => _selectedItems = items),
                totalItems: 42,
                rowsPerPage: 5,
                currentPage: _currentPage,
                onPageChanged: (page) => setState(() => _currentPage = page),
                rowBuilder: (context, item) {
                  return Row(
                    children: [
                      Expanded(flex: 1, child: Text('#$item')),
                      Expanded(flex: 2, child: Text('Sample Row Data')),
                      Expanded(flex: 1, child: Align(alignment: Alignment.centerLeft, child: StatusBadge(text: 'Active', status: BadgeStatus.success))),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SectionCard(
                  title: 'AppDataTable (Loading)',
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    height: 250,
                    child: AppDataTable<int>(
                      columns: const ['Col 1', 'Col 2'],
                      flexes: const [1, 1],
                      data: const [],
                      isLoading: true,
                      skeletonCount: 3,
                      rowBuilder: (_,__) => const SizedBox(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: SectionCard(
                  title: 'AppDataTable (Empty)',
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    height: 250,
                    child: AppDataTable<int>(
                      columns: const ['Col 1', 'Col 2'],
                      flexes: const [1, 1],
                      data: const [],
                      emptyState: EmptyState(title: 'No Data', message: 'The table is empty.', icon: LucideIcons.inbox),
                      rowBuilder: (_,__) => const SizedBox(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
