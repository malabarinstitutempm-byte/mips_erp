import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/models/student.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/section_card.dart';
import '../teachers/one_time_password_dialog.dart';
import 'student_account_provider.dart';
import '../../core/services/supabase_service.dart';

class StudentAccountTab extends ConsumerWidget {
  final Student student;
  final VoidCallback? onUpdated;

  const StudentAccountTab({
    super.key,
    required this.student,
    this.onUpdated,
  });

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Never';
    return DateFormat('MMM d, yyyy • h:mm a').format(dt.toLocal());
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (status) {
      case 'Active':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        icon = LucideIcons.checkCircle;
        label = 'Active';
        break;
      case 'Locked':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        icon = LucideIcons.lock;
        label = 'Locked';
        break;
      case 'Inactive':
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475569);
        icon = LucideIcons.userX;
        label = 'Inactive';
        break;
      case 'Not activated yet':
      default:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        icon = LucideIcons.clock;
        label = 'Not activated yet';
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
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(studentAccountInfoProvider(student));

    return accountAsync.when(
      data: (info) => _buildContent(context, ref, info),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error loading account info: $err')),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, StudentAccountInfo info) {
    final isLocked = info.isLocked;
    final isActive = info.active;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Account Summary Card
          SectionCard(
            title: 'Student Portal Login & Credentials',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.brandTint,
                      child: const Icon(LucideIcons.shieldCheck, color: AppColors.brand, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                student.name,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                              ),
                              const SizedBox(width: 12),
                              _buildStatusBadge(info.displayStatus),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Students sign in to the portal using their unique Register / Admission Number and password.',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 14),

                // Credentials Details Grid
                Wrap(
                  spacing: 28,
                  runSpacing: 16,
                  children: [
                    _buildMetaItem(
                      label: 'Register Number (Login ID)',
                      value: info.loginIdentifier,
                      icon: LucideIcons.badgeCheck,
                      highlight: true,
                    ),
                    _buildMetaItem(
                      label: 'Account Status',
                      value: info.displayStatus,
                      icon: LucideIcons.info,
                    ),
                    _buildMetaItem(
                      label: 'Last Login',
                      value: _formatDateTime(info.lastLoginAt),
                      icon: LucideIcons.logIn,
                    ),
                    _buildMetaItem(
                      label: 'Failed Login Attempts',
                      value: '${info.failedAttempts} / 5',
                      icon: LucideIcons.alertTriangle,
                      isWarning: info.failedAttempts > 0,
                    ),
                    _buildMetaItem(
                      label: 'Activated On',
                      value: info.activatedOn != null ? DateFormat('MMM d, yyyy').format(info.activatedOn!) : 'Not activated yet',
                      icon: LucideIcons.calendar,
                    ),
                    if (info.accessUntil != null || student.status == 'completed') ...[
                      _buildMetaItem(
                        label: 'Login Access Valid Until',
                        value: info.accessUntil != null
                            ? DateFormat('MMM d, yyyy').format(info.accessUntil!)
                            : 'Indefinite',
                        icon: LucideIcons.calendarClock,
                        isWarning: info.isAccessExpired,
                        highlight: !info.isAccessExpired && (info.daysUntilAccessExpires != null && info.daysUntilAccessExpires! <= 30),
                      ),
                      if (info.accessUntil != null)
                        _buildMetaItem(
                          label: 'Access Window State',
                          value: info.isAccessExpired
                              ? 'Access Expired'
                              : '${info.daysUntilAccessExpires ?? 0} days remaining',
                          icon: LucideIcons.hourglass,
                          isWarning: info.isAccessExpired || (info.daysUntilAccessExpires != null && info.daysUntilAccessExpires! <= 7),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // 2. Strict Password Governance Alert Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.shieldAlert, color: Color(0xFF2563EB), size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Password Privacy Governance',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Student passwords are protected by one-way cryptographic hashing and are never viewable by anyone, including administrators.\n\nExisting passwords cannot be decrypted or revealed. If a student forgets their password, you can either replace it with a temporary password or reset their account to first-time DOB verification.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // 3. Administrative Actions Section
          SectionCard(
            title: 'Administrative Security Actions',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // Action A: Reset to First Login (DOB Verification)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandDark,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  icon: const Icon(LucideIcons.rotateCcw, size: 16),
                  label: const Text('Reset to First Login'),
                  onPressed: () => _confirmResetToFirstLogin(context, ref),
                ),

                // Action B: Set Temporary Password
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  icon: const Icon(LucideIcons.keyRound, size: 16),
                  label: const Text('Set Temporary Password'),
                  onPressed: () => _showSetTempPasswordDialog(context, ref),
                ),

                // Action C: Unlock Account (if locked)
                if (isLocked) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(LucideIcons.unlock, size: 16),
                    label: const Text('Unlock Account'),
                    onPressed: () => _confirmUnlockAccount(context, ref),
                  ),
                ],

                // Action D: Deactivate / Reactivate Login
                if (isActive) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(LucideIcons.userX, size: 16),
                    label: const Text('Deactivate Login'),
                    onPressed: () => _confirmToggleActive(context, ref, false),
                  ),
                ] else ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(LucideIcons.userCheck, size: 16),
                    label: const Text('Reactivate Login'),
                    onPressed: () => _confirmToggleActive(context, ref, true),
                  ),
                ],

                // Action E: Close Login Now (Phase 9E)
                if (isActive) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB91C1C),
                      side: const BorderSide(color: Color(0xFFF87171)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(LucideIcons.ban, size: 16),
                    label: const Text('Close Login Now'),
                    onPressed: () => _confirmCloseLogin(context, ref),
                  ),
                ],

                // Action F: Extend Access / Reopen Login (Phase 9E)
                if (info.accessUntil != null || student.status == 'completed' || !isActive) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(LucideIcons.calendarPlus, size: 16),
                    label: Text(info.isAccessExpired || !isActive ? 'Reopen Login' : 'Extend Access'),
                    onPressed: () => _showExtendOrReopenDialog(context, ref, info),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaItem({
    required String label,
    required String value,
    required IconData icon,
    bool highlight = false,
    bool isWarning = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: isWarning ? Colors.redAccent : (highlight ? AppColors.brand : AppColors.textMuted)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
                color: isWarning ? Colors.red.shade700 : (highlight ? AppColors.brandDark : AppColors.textStrong),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 1. Confirmation: Reset to First Login
  Future<void> _confirmResetToFirstLogin(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(
          children: const [
            Icon(LucideIcons.rotateCcw, color: AppColors.brand, size: 22),
            SizedBox(width: 10),
            Text('Reset to First Login', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Invalidate login password for "${student.name}"?',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textStrong),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                ),
                child: const Text(
                  '• The student\'s current password will be immediately invalidated.\n• All active portal sessions will be logged out.\n• On their next login attempt, the student must verify their identity using their Date of Birth and set a new password.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E), height: 1.35),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
            icon: const Icon(LucideIcons.check, size: 16),
            label: const Text('Confirm Reset'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await StudentAccountActions.resetToFirstLogin(student, ref);
        onUpdated?.call();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account reset to first login. Student will verify with Date of Birth.'),
              backgroundColor: Color(0xFF0F766E),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to reset account: $e'), backgroundColor: Colors.red.shade700),
          );
        }
      }
    }
  }

  /// 2. Dialog: Set Temporary Password
  Future<void> _showSetTempPasswordDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({String mode, String? tempPassword})?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _StudentTempPasswordDialog(student: student),
    );

    if (result != null && context.mounted) {
      try {
        final generatedPassword = await StudentAccountActions.setTemporaryPassword(
          student: student,
          ref: ref,
          mode: result.mode,
          tempPassword: result.tempPassword,
        );

        onUpdated?.call();

        if (context.mounted) {
          await OneTimePasswordDialog.show(
            context,
            title: 'Temporary Password Issued',
            recipientName: student.name,
            usernameOrIdentifier: student.registrationNumber ?? student.admissionNumber ?? 'Student ID',
            temporaryPassword: generatedPassword,
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to issue temporary password: $e'), backgroundColor: Colors.red.shade700),
          );
        }
      }
    }
  }

  /// 3. Confirmation: Unlock Account
  Future<void> _confirmUnlockAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(
          children: const [
            Icon(LucideIcons.unlock, color: Color(0xFF2563EB), size: 22),
            SizedBox(width: 10),
            Text('Unlock Student Account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Unlock portal login for "${student.name}"?\n\nThis resets all consecutive failed login attempts to 0 and lifts the lockout immediately.',
          style: const TextStyle(fontSize: 13.5, color: AppColors.textStrong),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
            icon: const Icon(LucideIcons.unlock, size: 16),
            label: const Text('Unlock Account'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await StudentAccountActions.unlockAccount(student, ref);
        onUpdated?.call();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Student account unlocked successfully.'), backgroundColor: Color(0xFF2563EB)),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to unlock account: $e'), backgroundColor: Colors.red.shade700),
          );
        }
      }
    }
  }

  /// 4. Confirmation: Toggle Active / Inactive
  Future<void> _confirmToggleActive(BuildContext context, WidgetRef ref, bool active) async {
    final actionName = active ? 'Reactivate' : 'Deactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(
          children: [
            Icon(active ? LucideIcons.userCheck : LucideIcons.userX,
                color: active ? const Color(0xFF059669) : const Color(0xFFDC2626), size: 22),
            const SizedBox(width: 10),
            Text('$actionName Student Login', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          active
              ? 'Reactivate login access for "${student.name}"?\n\nThe student will be able to log in to the portal with their credentials.'
              : 'Deactivate login access for "${student.name}"?\n\nThis student will be blocked from signing in to the portal and active sessions will be terminated immediately. (Use for discontinued or suspended students).',
          style: const TextStyle(fontSize: 13.5, color: AppColors.textStrong),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: active ? const Color(0xFF059669) : const Color(0xFFDC2626),
            ),
            icon: Icon(active ? LucideIcons.userCheck : LucideIcons.userX, size: 16),
            label: Text('$actionName Account'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await StudentAccountActions.setStudentActive(student: student, active: active, ref: ref);
        onUpdated?.call();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Student login ${active ? "reactivated" : "deactivated"}.'),
              backgroundColor: active ? const Color(0xFF059669) : const Color(0xFF334155),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update student state: $e'), backgroundColor: Colors.red.shade700),
          );
        }
      }
    }
  }

  /// 5. Confirmation: Close Login Now (Phase 9E with pending fee balance warning)
  Future<void> _confirmCloseLogin(BuildContext context, WidgetRef ref) async {
    double pendingAmount = 0.0;
    if (student.id != null) {
      try {
        final client = SupabaseService.instance.client;
        final feeData = await client.from('fees').select('pending_amount_paise').eq('student_id', student.id!).maybeSingle();
        if (feeData != null && feeData['pending_amount_paise'] != null) {
          final paise = int.tryParse(feeData['pending_amount_paise'].toString()) ?? 0;
          pendingAmount = paise / 100.0;
        }
      } catch (_) {}
    }

    if (!context.mounted) return;

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
            Text('Close Student Login Immediately', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to close portal login access for "${student.name}" immediately?',
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textStrong),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Closing login will immediately revoke active sessions and block further sign-in attempts. No student records, marks, or financial data will be deleted.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                if (pendingAmount > 0) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(LucideIcons.alertTriangle, color: Color(0xFFDC2626), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Warning: This student has an outstanding fee balance of ₹${pendingAmount.toStringAsFixed(2)}. Closing login access will prevent them from reviewing pending dues or downloading fee receipts from the student portal.',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B), height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason for Closing Login *',
                    hintText: 'e.g. Course completed, 3-month window elapsed, or administrative closure',
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
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

    if (confirmed == true && context.mounted) {
      try {
        await StudentAccountActions.closeLogin(
          student: student,
          reason: reasonController.text.trim(),
          ref: ref,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Login closed for ${student.name}.'),
              backgroundColor: const Color(0xFF0F766E),
            ),
          );
          onUpdated?.call();
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error closing login: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// 6. Dialog: Extend Access / Reopen Login (Phase 9E)
  Future<void> _showExtendOrReopenDialog(BuildContext context, WidgetRef ref, StudentAccountInfo info) async {
    final isReopen = info.isAccessExpired || !info.active;
    final selectedDate = (info.accessUntil != null && info.accessUntil!.isAfter(DateTime.now()))
        ? info.accessUntil!.add(const Duration(days: 30))
        : DateTime.now().add(const Duration(days: 90));

    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      helpText: isReopen ? 'Select Reopen Access End Date' : 'Select New Extended Access Date',
    );

    if (picked != null && context.mounted) {
      try {
        if (isReopen) {
          await StudentAccountActions.reopenLogin(
            student: student,
            newDate: picked,
            ref: ref,
          );
        } else {
          await StudentAccountActions.extendAccess(
            student: student,
            newDate: picked,
            ref: ref,
          );
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Login access for ${student.name} set until ${DateFormat("MMM d, yyyy").format(picked)}.'),
              backgroundColor: const Color(0xFF0F766E),
            ),
          );
          onUpdated?.call();
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating access window: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

class _StudentTempPasswordDialog extends StatefulWidget {
  final Student student;

  const _StudentTempPasswordDialog({required this.student});

  @override
  State<_StudentTempPasswordDialog> createState() => _StudentTempPasswordDialogState();
}

class _StudentTempPasswordDialogState extends State<_StudentTempPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _isAutoGenerate = true;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
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

  String? _validatePassword(String? val) {
    if (_isAutoGenerate) return null;
    if (val == null || val.isEmpty) return 'Please enter a temporary password.';
    if (val.length < 8) return 'Password must be at least 8 characters long.';
    if (!RegExp(r'[A-Z]').hasMatch(val)) return 'Must contain at least one uppercase letter.';
    if (!RegExp(r'[a-z]').hasMatch(val)) return 'Must contain at least one lowercase letter.';
    if (!RegExp(r'[0-9]').hasMatch(val)) return 'Must contain at least one number.';
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(val)) return 'Must contain at least one symbol.';
    final regNo = (widget.student.registrationNumber ?? widget.student.admissionNumber ?? '').toLowerCase();
    if (regNo.isNotEmpty && val.toLowerCase().contains(regNo)) {
      return 'Password cannot contain the student register number.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      title: Row(
        children: const [
          Icon(LucideIcons.keyRound, color: AppColors.brand, size: 22),
          SizedBox(width: 10),
          Text('Set Student Temporary Password', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Issuing temporary credentials for "${widget.student.name}". The student will be forced to change this password on their next login.',
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        value: true,
                        groupValue: _isAutoGenerate,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Auto-generate', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Secure 12-char random string', style: TextStyle(fontSize: 11.5)),
                        onChanged: (val) => setState(() => _isAutoGenerate = val ?? true),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        value: false,
                        groupValue: _isAutoGenerate,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Type custom', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Enter manual temporary key', style: TextStyle(fontSize: 11.5)),
                        onChanged: (val) => setState(() => _isAutoGenerate = val ?? false),
                      ),
                    ),
                  ],
                ),
                if (!_isAutoGenerate) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Custom Temporary Password *',
                      prefixIcon: const Icon(LucideIcons.key, size: 18),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(_obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _passwordController.text = _generatePassword();
                                _obscurePassword = false;
                              });
                            },
                            child: const Text('Generate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    validator: _validatePassword,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
          icon: const Icon(LucideIcons.check, size: 16),
          label: const Text('Set Password'),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop((
                mode: _isAutoGenerate ? 'generate' : 'custom',
                tempPassword: _isAutoGenerate ? null : _passwordController.text.trim(),
              ));
            }
          },
        ),
      ],
    );
  }
}
