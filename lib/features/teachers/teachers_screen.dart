import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/models/teacher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'add_teacher_dialog.dart';
import 'edit_teacher_dialog.dart';
import 'teacher_action_dialogs.dart';
import 'teacher_detail_screen.dart';
import 'teacher_provider.dart';

class TeachersScreen extends ConsumerStatefulWidget {
  const TeachersScreen({super.key});

  @override
  ConsumerState<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends ConsumerState<TeachersScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Never';
    return DateFormat('MMM d, yyyy • h:mm a').format(dt.toLocal());
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    Color fg;
    IconData icon;

    switch (status) {
      case 'Active':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        icon = LucideIcons.checkCircle;
        break;
      case 'Locked':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        icon = LucideIcons.lock;
        break;
      case 'Inactive':
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475569);
        icon = LucideIcons.userX;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(status, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredTeachersAsync = ref.watch(filteredTeachersProvider);
    final allTeachersAsync = ref.watch(teachersListProvider);
    final activeFilter = ref.watch(teacherStatusFilterProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    // Compute status counts
    final allTeachers = allTeachersAsync.valueOrNull ?? [];
    final totalCount = allTeachers.length;
    final activeCount = allTeachers.where((t) => t.effectiveStatus == 'Active').length;
    final inactiveCount = allTeachers.where((t) => t.effectiveStatus == 'Inactive').length;
    final lockedCount = allTeachers.where((t) => t.effectiveStatus == 'Locked').length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          if (isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Teachers & Faculty Accounts',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Manage faculty credentials, login locks, and attendance marking permissions.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                  ),
                  icon: const Icon(LucideIcons.userPlus, size: 16),
                  label: const Text('Add Teacher', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => AddTeacherDialog.show(context),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Teachers & Faculty Accounts',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Manage faculty credentials, login locks, and attendance marking permissions.',
                        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                  ),
                  icon: const Icon(LucideIcons.userPlus, size: 16),
                  label: const Text('Add Teacher', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => AddTeacherDialog.show(context),
                ),
              ],
            ),
          const SizedBox(height: 18),

          // Filters and Search Row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Filter Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildFilterChip('All', totalCount, activeFilter == 'All'),
                    _buildFilterChip('Active', activeCount, activeFilter == 'Active'),
                    _buildFilterChip('Inactive', inactiveCount, activeFilter == 'Inactive'),
                    _buildFilterChip('Locked', lockedCount, activeFilter == 'Locked'),
                  ],
                ),

                // Search Bar
                SizedBox(
                  width: isMobile ? double.infinity : 280,
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => ref.read(teacherSearchQueryProvider.notifier).state = val,
                    decoration: InputDecoration(
                      hintText: 'Search by name, phone, username...',
                      hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                      prefixIcon: const Icon(LucideIcons.search, size: 16, color: AppColors.textMuted),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(LucideIcons.x, size: 14),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(teacherSearchQueryProvider.notifier).state = '';
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                      filled: true,
                      fillColor: AppColors.bg,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Teacher Data List
          Expanded(
            child: filteredTeachersAsync.when(
              data: (teachers) {
                if (teachers.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      child: Container(
                        padding: EdgeInsets.all(isMobile ? 16 : 32),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.users, size: 40, color: AppColors.textMuted),
                            const SizedBox(height: 10),
                            const Text('No teachers found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 6),
                            const Text('Try adjusting your search criteria or add a new teacher.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
                              icon: const Icon(LucideIcons.userPlus, size: 16),
                              label: const Text('Add Teacher'),
                              onPressed: () => AddTeacherDialog.show(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                // Phone/Mobile: Cards layout
                if (isMobile) {
                  return ListView.builder(
                    itemCount: teachers.length,
                    itemBuilder: (context, idx) {
                      final t = teachers[idx];
                      return _buildMobileTeacherCard(context, t);
                    },
                  );
                }

                // Desktop & Tablet: Data Table layout
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 58,
                        horizontalMargin: 20,
                        columnSpacing: 24,
                        columns: const [
                          DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong))),
                          DataColumn(label: Text('Username', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong))),
                          DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong))),
                          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong))),
                          DataColumn(label: Text('Last Login', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong))),
                          DataColumn(label: Text('Sessions Marked', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong))),
                          DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong))),
                        ],
                        rows: teachers.map((t) {
                          return DataRow(
                            cells: [
                              DataCell(
                                InkWell(
                                  onTap: () => _openTeacherDetail(context, t.id),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: AppColors.brandTint,
                                        child: Text(
                                          t.name.isNotEmpty ? t.name[0].toUpperCase() : 'T',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.brandDark),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        t.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandDark, decoration: TextDecoration.underline),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.atSign, size: 12, color: AppColors.textMuted),
                                    const SizedBox(width: 2),
                                    Text(t.loginUsername, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              DataCell(Text(t.phone?.isNotEmpty == true ? t.phone! : '—', style: const TextStyle(color: AppColors.textMuted))),
                              DataCell(_buildStatusChip(t.effectiveStatus)),
                              DataCell(Text(_formatDateTime(t.lastLoginAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${t.sessionsMarkedCount} marked',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(LucideIcons.eye, size: 16, color: AppColors.brandDark),
                                      tooltip: 'View Details & Sessions',
                                      onPressed: () => _openTeacherDetail(context, t.id),
                                    ),
                                    IconButton(
                                      icon: const Icon(LucideIcons.edit3, size: 16, color: AppColors.brand),
                                      tooltip: 'Edit Teacher',
                                      onPressed: () => EditTeacherDialog.show(context, t),
                                    ),
                                    IconButton(
                                      icon: const Icon(LucideIcons.keyRound, size: 16, color: Color(0xFFD97706)),
                                      tooltip: 'Reset Password',
                                      onPressed: () => TeacherActionDialogs.showResetPassword(context, ref, t),
                                    ),
                                    _buildTeacherMenu(context, t),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error loading teachers: $err', textAlign: TextAlign.center),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int count, bool isSelected) {
    return ChoiceChip(
      label: Text('$label ($count)'),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : AppColors.textStrong,
      ),
      selected: isSelected,
      selectedColor: AppColors.brand,
      backgroundColor: AppColors.bg,
      onSelected: (_) => ref.read(teacherStatusFilterProvider.notifier).state = label,
    );
  }

  Widget _buildMobileTeacherCard(BuildContext context, Teacher t) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.border),
      ),
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.brandTint,
                  child: Text(
                    t.name.isNotEmpty ? t.name[0].toUpperCase() : 'T',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandDark),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Icon(LucideIcons.atSign, size: 12, color: AppColors.textMuted),
                          Text(t.loginUsername, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                          if (t.phone != null && t.phone!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text('• ${t.phone}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(t.effectiveStatus),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Last Login: ${_formatDateTime(t.lastLoginAt)}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                  child: Text('${t.sessionsMarkedCount} marked', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8))),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                  icon: const Icon(LucideIcons.eye, size: 13),
                  label: const Text('Details', style: TextStyle(fontSize: 11.5)),
                  onPressed: () => _openTeacherDetail(context, t.id),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                  icon: const Icon(LucideIcons.edit3, size: 13),
                  label: const Text('Edit', style: TextStyle(fontSize: 11.5)),
                  onPressed: () => EditTeacherDialog.show(context, t),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                  icon: const Icon(LucideIcons.keyRound, size: 13),
                  label: const Text('Reset', style: TextStyle(fontSize: 11.5)),
                  onPressed: () => TeacherActionDialogs.showResetPassword(context, ref, t),
                ),
                _buildTeacherMenu(context, t),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherMenu(BuildContext context, Teacher t) {
    return PopupMenuButton<String>(
      icon: const Icon(LucideIcons.moreVertical, size: 16, color: AppColors.textMuted),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (val) {
        if (val == 'unlock') {
          TeacherActionDialogs.confirmUnlock(context, ref, t);
        } else if (val == 'deactivate') {
          TeacherActionDialogs.confirmDeactivate(context, ref, t);
        } else if (val == 'reactivate') {
          TeacherActionDialogs.confirmReactivate(context, ref, t);
        }
      },
      itemBuilder: (context) => [
        if (t.isLocked)
          const PopupMenuItem(
            value: 'unlock',
            child: Row(
              children: [
                Icon(LucideIcons.unlock, size: 15, color: Color(0xFF2563EB)),
                SizedBox(width: 8),
                Text('Unlock Account'),
              ],
            ),
          ),
        if (t.effectiveStatus == 'Active')
          const PopupMenuItem(
            value: 'deactivate',
            child: Row(
              children: [
                Icon(LucideIcons.userX, size: 15, color: Color(0xFFDC2626)),
                SizedBox(width: 8),
                Text('Deactivate Account', style: TextStyle(color: Color(0xFFDC2626))),
              ],
            ),
          )
        else if (t.effectiveStatus == 'Inactive')
          const PopupMenuItem(
            value: 'reactivate',
            child: Row(
              children: [
                Icon(LucideIcons.userCheck, size: 15, color: Color(0xFF059669)),
                SizedBox(width: 8),
                Text('Reactivate Account', style: TextStyle(color: Color(0xFF059669))),
              ],
            ),
          ),
      ],
    );
  }

  void _openTeacherDetail(BuildContext context, int teacherId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TeacherDetailScreen(teacherId: teacherId)),
    );
  }
}
