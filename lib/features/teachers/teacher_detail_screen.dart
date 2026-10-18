import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'edit_teacher_dialog.dart';
import 'teacher_action_dialogs.dart';
import 'teacher_provider.dart';

class TeacherDetailScreen extends ConsumerStatefulWidget {
  final int teacherId;

  const TeacherDetailScreen({super.key, required this.teacherId});

  @override
  ConsumerState<TeacherDetailScreen> createState() => _TeacherDetailScreenState();
}

class _TeacherDetailScreenState extends ConsumerState<TeacherDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(status, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teacherAsync = ref.watch(teacherDetailProvider(widget.teacherId));
    final sessionsAsync = ref.watch(teacherSessionsProvider(widget.teacherId));
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        shadowColor: AppColors.border,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: AppColors.brandDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: teacherAsync.when(
          data: (t) => Text(t?.name ?? 'Teacher Details', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textStrong)),
          loading: () => const Text('Loading Teacher...', style: TextStyle(fontSize: 16)),
          error: (_, __) => const Text('Teacher Details', style: TextStyle(fontSize: 16)),
        ),
        actions: [
          if (teacherAsync.valueOrNull != null) ...[
            IconButton(
              icon: const Icon(LucideIcons.edit3, size: 18, color: AppColors.brandDark),
              tooltip: 'Edit Teacher',
              onPressed: () => EditTeacherDialog.show(context, teacherAsync.valueOrNull!),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: teacherAsync.when(
        data: (teacher) {
          if (teacher == null) {
            return const Center(child: Text('Teacher record not found.'));
          }

          final auditAsync = ref.watch(teacherAuditHistoryProvider((teacherId: teacher.id, userId: teacher.userId)));

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Profile Header Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: AppColors.brandTint,
                            child: Text(
                              teacher.name.isNotEmpty ? teacher.name.substring(0, 1).toUpperCase() : 'T',
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.brandDark),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        teacher.name,
                                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                                      ),
                                    ),
                                    _buildStatusChip(teacher.effectiveStatus),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 6,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(LucideIcons.atSign, size: 14, color: AppColors.textMuted),
                                        const SizedBox(width: 4),
                                        Text(teacher.loginUsername, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      ],
                                    ),
                                    if (teacher.phone != null && teacher.phone!.isNotEmpty) ...[
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(LucideIcons.phone, size: 14, color: AppColors.textMuted),
                                          const SizedBox(width: 4),
                                          Text(teacher.phone!, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                                        ],
                                      ),
                                    ],
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(LucideIcons.mail, size: 14, color: AppColors.textMuted),
                                        const SizedBox(width: 4),
                                        Text('${teacher.loginUsername}@teachers.mips.invalid', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Quick Stats Row
                      Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: [
                          _buildStatItem('Last Login', _formatDateTime(teacher.lastLoginAt), LucideIcons.logIn),
                          _buildStatItem('Sessions Marked', '${teacher.sessionsMarkedCount} sessions', LucideIcons.calendarCheck),
                          _buildStatItem('Failed Attempts', '${teacher.failedAttempts}', LucideIcons.alertCircle),
                          _buildStatItem('Account Created', _formatDateTime(teacher.createdAt), LucideIcons.clock),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Action Buttons Row
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.brandDark,
                              side: const BorderSide(color: AppColors.border),
                            ),
                            icon: const Icon(LucideIcons.edit3, size: 15),
                            label: const Text('Edit Teacher'),
                            onPressed: () => EditTeacherDialog.show(context, teacher),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.brandDark,
                              side: const BorderSide(color: AppColors.border),
                            ),
                            icon: const Icon(LucideIcons.rotateCcw, size: 15),
                            label: const Text('Reset to First Login'),
                            onPressed: () => TeacherActionDialogs.confirmResetToFirstLogin(context, ref, teacher),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
                            icon: const Icon(LucideIcons.keyRound, size: 15),
                            label: const Text('Set Temporary Password'),
                            onPressed: () => TeacherActionDialogs.showResetPassword(context, ref, teacher),
                          ),
                          if (teacher.isLocked) ...[
                            FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                              icon: const Icon(LucideIcons.unlock, size: 15),
                              label: const Text('Unlock Account'),
                              onPressed: () => TeacherActionDialogs.confirmUnlock(context, ref, teacher),
                            ),
                          ],
                          if (teacher.effectiveStatus == 'Active') ...[
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFDC2626),
                                side: const BorderSide(color: Color(0xFFFCA5A5)),
                              ),
                              icon: const Icon(LucideIcons.userX, size: 15),
                              label: const Text('Deactivate'),
                              onPressed: () => TeacherActionDialogs.confirmDeactivate(context, ref, teacher),
                            ),
                          ] else if (teacher.effectiveStatus == 'Inactive') ...[
                            FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                              icon: const Icon(LucideIcons.userCheck, size: 15),
                              label: const Text('Reactivate'),
                              onPressed: () => TeacherActionDialogs.confirmReactivate(context, ref, teacher),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Tab Bar for Sessions & History
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppColors.brandDark,
                    unselectedLabelColor: AppColors.textMuted,
                    indicatorColor: AppColors.brand,
                    indicatorWeight: 3,
                    tabs: const [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.calendarCheck, size: 16),
                            SizedBox(width: 8),
                            Text('Recent Sessions Marked', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.history, size: 16),
                            SizedBox(width: 8),
                            Text('Account Audit History', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Tab View
                Container(
                  constraints: const BoxConstraints(minHeight: 320),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: [
                    // Tab 1: Recent Sessions Marked
                    sessionsAsync.when(
                      data: (sessions) {
                        if (sessions.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(LucideIcons.calendarX, size: 36, color: AppColors.textMuted),
                                  SizedBox(height: 8),
                                  Text('No attendance sessions marked yet.', style: TextStyle(color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: sessions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final s = sessions[idx];
                            final dateParsed = DateTime.tryParse(s['date']?.toString() ?? '');
                            final dateFormatted = dateParsed != null ? DateFormat('EEE, MMM d, yyyy').format(dateParsed) : (s['date'] ?? 'N/A');
                            final period = (s['period'] ?? 'Morning').toString().toUpperCase();

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: period.contains('MORNING') ? Colors.amber.shade50 : Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  period.contains('MORNING') ? LucideIcons.sun : LucideIcons.moon,
                                  size: 18,
                                  color: period.contains('MORNING') ? Colors.amber.shade800 : Colors.indigo.shade800,
                                ),
                              ),
                              title: Text(
                                '${s['batch_name']} • ${s['subject_name']}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppColors.textStrong),
                              ),
                              subtitle: Text(
                                '$dateFormatted • Slot: $period',
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFA7F3D0)),
                                ),
                                child: Text(
                                  (s['status'] ?? 'submitted').toString().toUpperCase(),
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                                ),
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
                      error: (err, _) => Center(child: Text('Error loading sessions: $err')),
                    ),

                    // Tab 2: Account Audit History
                    auditAsync.when(
                      data: (history) {
                        if (history.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(LucideIcons.shieldCheck, size: 36, color: AppColors.textMuted),
                                  SizedBox(height: 8),
                                  Text('No administrative audit logs recorded.', style: TextStyle(color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: history.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final h = history[idx];
                            final dt = DateTime.tryParse(h['created_at']?.toString() ?? '');
                            final dtStr = dt != null ? DateFormat('MMM d, yyyy • h:mm a').format(dt.toLocal()) : (h['created_at'] ?? '');
                            final action = (h['action'] ?? '').toString();

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _getAuditColor(action).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(_getAuditIcon(action), size: 18, color: _getAuditColor(action)),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      action.replaceAll('_', ' '),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textStrong),
                                    ),
                                  ),
                                  Text(dtStr, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Actor: ${h['actor'] ?? "Admin"}${h['details'] != null && h['details'] is Map && (h['details'] as Map).isNotEmpty ? " • ${h['details']}" : ""}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
                      error: (err, _) => Center(child: Text('Error loading audit history: $err')),
                    ),
                  ][_tabController.index],
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading teacher: $err')),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.brand),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
          ],
        ),
      ],
    );
  }

  Color _getAuditColor(String action) {
    if (action.contains('CREATE')) return const Color(0xFF059669);
    if (action.contains('RESET')) return const Color(0xFFD97706);
    if (action.contains('DEACTIVATE') || action.contains('LOCKED')) return const Color(0xFFDC2626);
    if (action.contains('UNLOCK') || action.contains('REACTIVATE')) return const Color(0xFF2563EB);
    return AppColors.brand;
  }

  IconData _getAuditIcon(String action) {
    if (action.contains('CREATE')) return LucideIcons.userPlus;
    if (action.contains('RESET')) return LucideIcons.keyRound;
    if (action.contains('DEACTIVATE')) return LucideIcons.userX;
    if (action.contains('LOCKED')) return LucideIcons.lock;
    if (action.contains('UNLOCK')) return LucideIcons.unlock;
    if (action.contains('REACTIVATE')) return LucideIcons.userCheck;
    return LucideIcons.activity;
  }
}
