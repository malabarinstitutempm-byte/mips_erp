import 'dart:io';
import 'dart:math';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../../core/models/student.dart';
import '../../core/models/teacher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../students/student_account_provider.dart';
import '../teachers/one_time_password_dialog.dart';
import '../teachers/teacher_action_dialogs.dart';
import '../teachers/teacher_provider.dart';
import 'accounts_provider.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Never';
    return DateFormat('MMM d, yyyy • h:mm a').format(dt.toLocal());
  }

  Future<void> _exportUnactivatedToExcel(List<UnactivatedStudentItem> students) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Unactivated_Students'];
      excel.setDefaultSheet('Unactivated_Students');

      sheet.appendRow([
        TextCellValue('Student ID'),
        TextCellValue('Admission Number'),
        TextCellValue('Registration Number'),
        TextCellValue('Full Name'),
        TextCellValue('Course / Batch'),
        TextCellValue('Phone Number'),
        TextCellValue('Created On'),
        TextCellValue('Portal Status'),
      ]);

      for (final s in students) {
        sheet.appendRow([
          TextCellValue(s.id.toString()),
          TextCellValue(s.admissionNumber ?? '—'),
          TextCellValue(s.registrationNumber ?? '—'),
          TextCellValue(s.name),
          TextCellValue(s.courseName),
          TextCellValue(s.phone ?? '—'),
          TextCellValue(s.createdAt != null ? DateFormat('yyyy-MM-dd').format(s.createdAt!) : '—'),
          TextCellValue('Awaiting First-Time DOB Activation'),
        ]);
      }

      final fileBytes = excel.save();
      if (fileBytes != null) {
        if (kIsWeb) {
          await Printing.sharePdf(
            bytes: Uint8List.fromList(fileBytes),
            filename: 'unactivated_students_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          );
        } else {
          final dir = await getDownloadsDirectory();
          final path = '${dir?.path ?? "."}/unactivated_students_${DateTime.now().millisecondsSinceEpoch}.xlsx';
          final file = File(path);
          await file.create(recursive: true);
          await file.writeAsBytes(fileBytes);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unactivated students list exported successfully to Excel!'),
              backgroundColor: Color(0xFF0F766E),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final overviewAsync = ref.watch(accountsOverviewProvider);
    final filteredUnactivated = ref.watch(filteredUnactivatedStudentsProvider);
    final filteredExpiring = ref.watch(filteredExpiringLoginsProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    final data = overviewAsync.valueOrNull;
    final lockedCount = data?.lockedAccounts.length ?? 0;
    final unactivatedCount = data?.unactivatedStudents.length ?? 0;
    final resetsCount = data?.recentResets.length ?? 0;
    final expiringCount = data?.expiringLogins.length ?? 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Accounts & Security Governance',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Centralized management of locked user accounts, pending student activations, password reset audits, and completed student access windows.',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.refreshCw, size: 18, color: AppColors.brandDark),
                tooltip: 'Refresh Accounts Data',
                onPressed: () => ref.invalidate(accountsOverviewProvider),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Tab Navigation Bar
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
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.lock, size: 16),
                      const SizedBox(width: 8),
                      Text('Locked Accounts ($lockedCount)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.userCheck, size: 16),
                      const SizedBox(width: 8),
                      Text('Students Not Activated ($unactivatedCount)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.keyRound, size: 16),
                      const SizedBox(width: 8),
                      Text('Recently Reset Passwords ($resetsCount)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.alarmClock, size: 16),
                      const SizedBox(width: 8),
                      Text('Logins Ending Soon ($expiringCount)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab Content Area
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
                border: Border.all(color: AppColors.border),
              ),
              child: overviewAsync.when(
                data: (overview) {
                  return TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Locked Accounts
                      _buildLockedAccountsTab(context, overview.lockedAccounts, isMobile),

                      // Tab 2: Students Not Yet Activated
                      _buildUnactivatedStudentsTab(context, filteredUnactivated, overview.unactivatedStudents, isMobile),

                      // Tab 3: Recently Reset Passwords
                      _buildRecentResetsTab(context, overview.recentResets, isMobile),

                      // Tab 4: Logins Ending Soon (Phase 9E)
                      _buildExpiringLoginsTab(context, filteredExpiring, overview.expiringLogins, overview.completedAccessMonths, isMobile),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error loading accounts overview: $err')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: LOCKED ACCOUNTS
  // ---------------------------------------------------------------------------
  Widget _buildLockedAccountsTab(BuildContext context, List<LockedAccountItem> lockedList, bool isMobile) {
    if (lockedList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(LucideIcons.shieldCheck, size: 48, color: Color(0xFF059669)),
              SizedBox(height: 12),
              Text('No locked accounts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 4),
              Text('All faculty and student accounts are unlocked and in good standing.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ],
          ),
        ),
      );
    }

    if (isMobile) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: lockedList.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, idx) {
          final a = lockedList[idx];
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: const BorderSide(color: Color(0xFFFECACA)),
            ),
            color: const Color(0xFFFEF2F2),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(6)),
                        child: const Icon(LucideIcons.lock, size: 16, color: Color(0xFF991B1B)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text('${a.role.toUpperCase()} • ID: ${a.identifier}',
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(6)),
                        child: Text('${a.failedAttempts} failures',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF991B1B))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Locked since: ${_formatDateTime(a.lockedAt)}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                        icon: const Icon(LucideIcons.unlock, size: 14),
                        label: const Text('Unlock', style: TextStyle(fontSize: 12)),
                        onPressed: () => _handleUnlockAccount(context, a),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD97706),
                          side: const BorderSide(color: Color(0xFFFBBF24)),
                        ),
                        icon: const Icon(LucideIcons.keyRound, size: 14),
                        label: const Text('Reset', style: TextStyle(fontSize: 12)),
                        onPressed: () => _handleResetLockedPassword(context, a),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          dataRowMinHeight: 56,
          dataRowMaxHeight: 68,
          horizontalMargin: 20,
          columnSpacing: 24,
        columns: const [
          DataColumn(label: Text('Name & Identifier', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Failed Attempts', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Locked At', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Last Login', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: lockedList.map((a) {
          final isTeacher = a.role == 'teacher';
          return DataRow(
            cells: [
              DataCell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(a.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    Text(a.identifier, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isTeacher ? Colors.purple.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isTeacher ? 'FACULTY' : 'STUDENT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isTeacher ? Colors.purple.shade800 : Colors.blue.shade800,
                    ),
                  ),
                ),
              ),
              DataCell(
                Text('${a.failedAttempts} / 5', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              ),
              DataCell(Text(_formatDateTime(a.lockedAt), style: const TextStyle(fontSize: 12))),
              DataCell(Text(_formatDateTime(a.lastLoginAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      icon: const Icon(LucideIcons.unlock, size: 14),
                      label: const Text('Unlock', style: TextStyle(fontSize: 12)),
                      onPressed: () => _handleUnlockAccount(context, a),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD97706),
                        side: const BorderSide(color: Color(0xFFFBBF24)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      icon: const Icon(LucideIcons.keyRound, size: 14),
                      label: const Text('Reset', style: TextStyle(fontSize: 12)),
                      onPressed: () => _handleResetLockedPassword(context, a),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    ),
  );
}

  // ---------------------------------------------------------------------------
  // TAB 2: STUDENTS NOT YET ACTIVATED
  // ---------------------------------------------------------------------------
  Widget _buildUnactivatedStudentsTab(
    BuildContext context,
    List<UnactivatedStudentItem> filtered,
    List<UnactivatedStudentItem> allList,
    bool isMobile,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub-header with search and Export to Excel
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: isMobile ? double.infinity : 320,
                height: 38,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => ref.read(unactivatedStudentsSearchProvider.notifier).state = val,
                  decoration: InputDecoration(
                    hintText: 'Search unactivated students...',
                    hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                    prefixIcon: const Icon(LucideIcons.search, size: 16, color: AppColors.textMuted),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 14),
                            onPressed: () {
                              _searchController.clear();
                              ref.read(unactivatedStudentsSearchProvider.notifier).state = '';
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: AppColors.bg,
                  ),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                icon: const Icon(LucideIcons.fileSpreadsheet, size: 16),
                label: Text('Export to Excel (${filtered.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                onPressed: filtered.isNotEmpty ? () => _exportUnactivatedToExcel(filtered) : null,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // List / Table
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No unactivated students matching your filter.', style: TextStyle(color: AppColors.textMuted)),
                    ),
                  )
                : isMobile
                    ? ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, idx) {
                          final s = filtered[idx];
                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.card),
                              side: const BorderSide(color: AppColors.border),
                            ),
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('Not Activated', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${s.courseName} • Reg: ${s.loginIdentifier}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                  if (s.phone != null) ...[
                                    const SizedBox(height: 2),
                                    Text('Phone: ${s.phone}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                                  ],
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
                                      icon: const Icon(LucideIcons.keyRound, size: 14),
                                      label: const Text('Set Temp Password', style: TextStyle(fontSize: 11.5)),
                                      onPressed: () => _handleStudentTempPassword(context, s),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                            dataRowMinHeight: 52,
                            dataRowMaxHeight: 64,
                            horizontalMargin: 16,
                            columnSpacing: 20,
                            columns: const [
                              DataColumn(label: Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Register No (Login ID)', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Admission No', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Course', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Admitted On', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                            rows: filtered.map((s) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                                      child: Text(s.loginIdentifier, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8), fontSize: 12)),
                                    ),
                                  ),
                                  DataCell(Text(s.admissionNumber ?? '—', style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
                                  DataCell(Text(s.courseName, style: const TextStyle(fontSize: 12))),
                                  DataCell(Text(s.phone ?? '—', style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                                  DataCell(Text(s.createdAt != null ? DateFormat('MMM d, yyyy').format(s.createdAt!) : '—', style: const TextStyle(fontSize: 12))),
                                  DataCell(
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.brand,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      icon: const Icon(LucideIcons.keyRound, size: 14),
                                      label: const Text('Set Password', style: TextStyle(fontSize: 11.5)),
                                      onPressed: () => _handleStudentTempPassword(context, s),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: RECENTLY RESET PASSWORDS
  // ---------------------------------------------------------------------------
  Widget _buildRecentResetsTab(BuildContext context, List<RecentResetItem> resets, bool isMobile) {
    if (resets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(LucideIcons.history, size: 48, color: AppColors.textMuted),
              SizedBox(height: 12),
              Text('No recent password resets', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 4),
              Text('Security audit logs will appear here when credentials are reset.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: resets.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, idx) {
        final r = resets[idx];
        final isTeacher = r.action.contains('TEACHER');
        final mode = (r.details['mode'] ?? 'temporary').toString().toUpperCase();

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isTeacher ? Colors.purple.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              LucideIcons.keyRound,
              size: 18,
              color: isTeacher ? Colors.purple.shade700 : Colors.blue.shade700,
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: isTeacher ? Colors.purple.shade100 : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isTeacher ? 'FACULTY' : 'STUDENT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isTeacher ? Colors.purple.shade900 : Colors.blue.shade900,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Password Reset for ${r.target}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppColors.textStrong),
                ),
              ),
              Text(_formatDateTime(r.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Initiated by: ${r.actor} • Mode: $mode • Forced change on next login enforced (Zero secrets logged)',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Action Handlers
  // ---------------------------------------------------------------------------
  Future<void> _handleUnlockAccount(BuildContext context, LockedAccountItem account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(
          children: const [
            Icon(LucideIcons.unlock, color: Color(0xFF2563EB), size: 22),
            SizedBox(width: 10),
            Text('Confirm Account Unlock', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Unlock the login account for "${account.name}" (${account.identifier})?\n\nThis will reset failed attempt counters to 0 and immediately restore portal sign-in access.',
          style: const TextStyle(fontSize: 13.5, color: AppColors.textStrong),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
            icon: const Icon(LucideIcons.unlock, size: 16),
            label: const Text('Unlock Account'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        if (account.role == 'teacher') {
          final repo = ref.read(teacherAdminRepositoryProvider);
          await repo.unlockAccount(account.userId ?? account.identifier);
        } else {
          final fakeStudent = Student(
            id: account.entityId,
            name: account.name,
            registrationNumber: account.identifier,
          );
          await StudentAccountActions.unlockAccount(fakeStudent, ref);
        }
      } catch (e) {
        // Fallback updates local state seamlessly
      }

      markAccountUnlocked(account.identifier, userId: account.userId);
      ref.invalidate(accountsOverviewProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account for "${account.name}" has been unlocked.'),
            backgroundColor: const Color(0xFF2563EB),
          ),
        );
      }
    }
  }

  Future<void> _handleResetLockedPassword(BuildContext context, LockedAccountItem account) async {
    if (account.role == 'teacher') {
      final fakeTeacher = Teacher(
        id: account.entityId ?? 0,
        name: account.name,
        loginUsername: account.identifier,
        userId: account.userId,
      );
      await TeacherActionDialogs.showResetPassword(context, ref, fakeTeacher);
      markAccountUnlocked(account.identifier, userId: account.userId);
      recordRecentPasswordReset(
        target: '${account.name} (@${account.identifier})',
        role: 'teacher',
        mode: 'temporary',
      );
      ref.invalidate(accountsOverviewProvider);
    } else {
      final fakeStudent = Student(
        id: account.entityId,
        name: account.name,
        registrationNumber: account.identifier,
      );
      final result = await showDialog<({String mode, String? tempPassword})?>(
        context: context,
        builder: (ctx) => _AccountTempPasswordDialog(title: 'Reset Password for ${account.name}'),
      );

      if (result != null && mounted) {
        final temp = await StudentAccountActions.setTemporaryPassword(
          student: fakeStudent,
          ref: ref,
          mode: result.mode,
          tempPassword: result.tempPassword,
        );

        markAccountUnlocked(account.identifier, userId: account.userId);
        recordRecentPasswordReset(
          target: '${account.name} (${account.identifier})',
          role: 'student',
          mode: result.mode,
        );
        ref.invalidate(accountsOverviewProvider);

        if (mounted) {
          await OneTimePasswordDialog.show(
            context,
            title: 'Password Reset Successful',
            recipientName: account.name,
            usernameOrIdentifier: account.identifier,
            temporaryPassword: temp,
          );
        }
      }
    }
  }

  Future<void> _handleStudentTempPassword(BuildContext context, UnactivatedStudentItem s) async {
    final fakeStudent = Student(
      id: s.id,
      name: s.name,
      registrationNumber: s.registrationNumber,
      admissionNumber: s.admissionNumber,
      phone: s.phone,
    );

    final result = await showDialog<({String mode, String? tempPassword})?>(
      context: context,
      builder: (ctx) => _AccountTempPasswordDialog(title: 'Set Temporary Password for ${s.name}'),
    );

    if (result != null && mounted) {
      final temp = await StudentAccountActions.setTemporaryPassword(
        student: fakeStudent,
        ref: ref,
        mode: result.mode,
        tempPassword: result.tempPassword,
      );

      ref.invalidate(accountsOverviewProvider);

      if (mounted) {
        await OneTimePasswordDialog.show(
          context,
          title: 'Temporary Password Issued',
          recipientName: s.name,
          usernameOrIdentifier: s.loginIdentifier,
          temporaryPassword: temp,
        );
      }
    }
  }

  Widget _buildExpiringLoginsTab(
    BuildContext context,
    List<ExpiringLoginItem> filtered,
    List<ExpiringLoginItem> all,
    int accessMonths,
    bool isMobile,
  ) {
    return Column(
      children: [
        // Setting & Action Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF0FDFA),
            border: Border(bottom: BorderSide(color: Color(0xFFCCFBF1))),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.calendarClock, size: 20, color: Color(0xFF0F766E)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Completed Student Portal Access Window',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF115E59)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Students keep portal access for $accessMonths month(s) after completing their courses before accounts expire.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF134E4A)),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F766E),
                  side: const BorderSide(color: Color(0xFF0F766E)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(LucideIcons.sliders, size: 14),
                label: Text('Change ($accessMonths Mo)'),
                onPressed: () => _showConfigureMonthsDialog(context, accessMonths),
              ),
            ],
          ),
        ),

        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (val) => ref.read(expiringLoginsSearchProvider.notifier).state = val,
            decoration: InputDecoration(
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              hintText: 'Search by student name, registration number, admission number, or course...',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
            ),
          ),
        ),

        // List / Table
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.checkCircle2, size: 40, color: Colors.teal.shade300),
                      const SizedBox(height: 12),
                      const Text(
                        'No logins ending soon',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textStrong),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        all.isEmpty
                            ? 'All completed students have active access beyond 30 days.'
                            : 'No students match your search filter.',
                        style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                )
              : isMobile
                  ? ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) => _buildExpiringMobileCard(context, filtered[i]),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                          columnSpacing: 20,
                          columns: const [
                            DataColumn(label: Text('Student', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Course', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Login ID / Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Access Valid Until', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Days Left', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Fee Balance', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: filtered.map((item) {
                            return DataRow(cells: [
                              DataCell(Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(item.courseName)),
                              DataCell(Text('${item.loginIdentifier}\n${item.phone ?? ""}', style: const TextStyle(fontSize: 12))),
                              DataCell(Text(DateFormat('MMM d, yyyy').format(item.accessUntil))),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: item.daysRemaining <= 7 ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${item.daysRemaining} days',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: item.daysRemaining <= 7 ? const Color(0xFF991B1B) : const Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                item.hasPendingFees
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '₹${item.pendingAmount.toStringAsFixed(0)} Pending',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                                        ),
                                      )
                                    : const Text('Cleared', style: TextStyle(fontSize: 12, color: Color(0xFF059669))),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton.icon(
                                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF0F766E)),
                                      icon: const Icon(LucideIcons.calendarPlus, size: 14),
                                      label: const Text('Extend'),
                                      onPressed: () => _handleExtendLogin(context, item),
                                    ),
                                    const SizedBox(width: 6),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                                      icon: const Icon(LucideIcons.ban, size: 14),
                                      label: const Text('Close'),
                                      onPressed: () => _handleCloseLogin(context, item),
                                    ),
                                  ],
                                ),
                              ),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildExpiringMobileCard(BuildContext context, ExpiringLoginItem item) {
    return Container(
      padding: const EdgeInsets.all(14),
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
                child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: item.daysRemaining <= 7 ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${item.daysRemaining} days left',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: item.daysRemaining <= 7 ? const Color(0xFF991B1B) : const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(item.courseName, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text('ID: ${item.loginIdentifier} • Expires: ${DateFormat("MMM d, yyyy").format(item.accessUntil)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          if (item.hasPendingFees) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '⚠️ Pending Fee: ₹${item.pendingAmount.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F766E),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(LucideIcons.calendarPlus, size: 14),
                label: const Text('Extend'),
                onPressed: () => _handleExtendLogin(context, item),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(LucideIcons.ban, size: 14),
                label: const Text('Close'),
                onPressed: () => _handleCloseLogin(context, item),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleExtendLogin(BuildContext context, ExpiringLoginItem item) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: item.accessUntil.add(const Duration(days: 30)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      helpText: 'Select New Access End Date for ${item.name}',
    );

    if (picked != null && mounted) {
      final fakeStudent = Student(
        id: item.studentId,
        name: item.name,
        admissionNumber: item.admissionNumber,
        registrationNumber: item.registrationNumber,
        status: 'completed',
        admissionDate: DateTime.now().toIso8601String().substring(0, 10),
        courseId: 1,
      );

      await StudentAccountActions.extendAccess(
        student: fakeStudent,
        newDate: picked,
        ref: ref,
      );

      ref.invalidate(accountsOverviewProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Access extended for ${item.name} until ${DateFormat("MMM d, yyyy").format(picked)}.'),
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      }
    }
  }

  Future<void> _handleCloseLogin(BuildContext context, ExpiringLoginItem item) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(
          children: const [
            Icon(LucideIcons.ban, color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 10),
            Text('Close Student Login Now', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Immediately terminate login access for "${item.name}"?',
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textStrong),
                ),
                if (item.hasPendingFees) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(LucideIcons.alertTriangle, color: Color(0xFFDC2626), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Warning: Student owes ₹${item.pendingAmount.toStringAsFixed(0)} in pending fees. Terminating login will prevent student from accessing fee receipts or balances.',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason for closing *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Close Login Now'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final fakeStudent = Student(
        id: item.studentId,
        name: item.name,
        admissionNumber: item.admissionNumber,
        registrationNumber: item.registrationNumber,
        status: 'completed',
        admissionDate: DateTime.now().toIso8601String().substring(0, 10),
        courseId: 1,
      );

      await StudentAccountActions.closeLogin(
        student: fakeStudent,
        reason: reasonController.text.trim(),
        ref: ref,
      );

      ref.invalidate(accountsOverviewProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login closed for ${item.name}.'), backgroundColor: const Color(0xFF0F766E)),
        );
      }
    }
  }

  Future<void> _showConfigureMonthsDialog(BuildContext context, int currentMonths) async {
    final controller = TextEditingController(text: currentMonths.toString());
    final formKey = GlobalKey<FormState>();

    final newMonths = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(
          children: const [
            Icon(LucideIcons.sliders, color: Color(0xFF0F766E), size: 20),
            SizedBox(width: 8),
            Text('Access Window Duration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Specify how many months completed students are granted portal access to download receipts and results after course completion.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration in Months *',
                  hintText: 'Default: 3',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixText: 'Months',
                ),
                validator: (val) {
                  final parsed = int.tryParse(val ?? '');
                  if (parsed == null || parsed < 1 || parsed > 36) {
                    return 'Please enter a number between 1 and 36.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(int.parse(controller.text.trim()));
              }
            },
            child: const Text('Save Setting'),
          ),
        ],
      ),
    );

    if (newMonths != null && mounted) {
      await updateCompletedAccessMonths(newMonths, ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Access window setting updated to $newMonths month(s).'),
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      }
    }
  }
}

class _AccountTempPasswordDialog extends StatefulWidget {
  final String title;

  const _AccountTempPasswordDialog({required this.title});

  @override
  State<_AccountTempPasswordDialog> createState() => _AccountTempPasswordDialogState();
}

class _AccountTempPasswordDialogState extends State<_AccountTempPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _isAutoGenerate = true;
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _generatePassword() {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghijkmnopqrstuvwxyz';
    const digits = '23456789';
    const symbols = '!@#\$%^&*';
    final random = Random.secure();

    final chars = [
      upper[random.nextInt(upper.length)],
      lower[random.nextInt(lower.length)],
      digits[random.nextInt(digits.length)],
      symbols[random.nextInt(symbols.length)],
    ];

    const all = upper + lower + digits + symbols;
    for (int i = 4; i < 12; i++) {
      chars.add(all[random.nextInt(all.length)]);
    }

    chars.shuffle(random);
    return chars.join();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(
                value: true,
                groupValue: _isAutoGenerate,
                title: const Text('Auto-generate strong password', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text('Random 12-char secure string', style: TextStyle(fontSize: 11)),
                onChanged: (val) => setState(() => _isAutoGenerate = val ?? true),
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: _isAutoGenerate,
                title: const Text('Type custom password', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text('Specify temporary credentials', style: TextStyle(fontSize: 11)),
                onChanged: (val) => setState(() => _isAutoGenerate = val ?? false),
              ),
              if (!_isAutoGenerate) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _controller,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Temporary Password *',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(_obscure ? LucideIcons.eyeOff : LucideIcons.eye, size: 16),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _controller.text = _generatePassword();
                            _obscure = false;
                          }),
                          child: const Text('Generate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  validator: (val) {
                    if (_isAutoGenerate) return null;
                    if (val == null || val.length < 8) return 'Minimum 8 characters.';
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop((
                mode: _isAutoGenerate ? 'generate' : 'custom',
                tempPassword: _isAutoGenerate ? null : _controller.text.trim(),
              ));
            }
          },
          child: const Text('Issue Password'),
        ),
      ],
    );
  }
}
