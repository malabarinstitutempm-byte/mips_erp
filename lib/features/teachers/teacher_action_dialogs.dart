import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/models/teacher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'one_time_password_dialog.dart';
import 'teacher_provider.dart';

class TeacherActionDialogs {
  /// 1. Deactivate Teacher Dialog
  static Future<void> confirmDeactivate(BuildContext context, WidgetRef ref, Teacher teacher) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(
          children: const [
            Icon(LucideIcons.userX, color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 10),
            Text('Deactivate Teacher Account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to deactivate "${teacher.name}" (@${teacher.loginUsername})?',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textStrong),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('• The teacher will be immediately blocked from signing in.', style: TextStyle(fontSize: 12.5, color: Color(0xFF991B1B))),
                    SizedBox(height: 4),
                    Text('• All active user sessions are revoked immediately.', style: TextStyle(fontSize: 12.5, color: Color(0xFF991B1B))),
                    SizedBox(height: 4),
                    Text('• Past attendance sessions marked by them remain permanently intact.', style: TextStyle(fontSize: 12.5, color: Color(0xFF991B1B))),
                  ],
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
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(LucideIcons.userX, size: 16),
            label: const Text('Deactivate Immediately'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final repo = ref.read(teacherAdminRepositoryProvider);
        await repo.setTeacherActive(teacherId: teacher.id, active: false);
        ref.invalidate(teachersListProvider);
        ref.invalidate(teacherDetailProvider(teacher.id));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Teacher "${teacher.name}" has been deactivated.'),
              backgroundColor: const Color(0xFF334155),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to deactivate teacher: $e'), backgroundColor: Colors.red.shade700),
          );
        }
      }
    }
  }

  /// 2. Reactivate Teacher Dialog
  static Future<void> confirmReactivate(BuildContext context, WidgetRef ref, Teacher teacher) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(
          children: const [
            Icon(LucideIcons.userCheck, color: Color(0xFF059669), size: 22),
            SizedBox(width: 10),
            Text('Reactivate Teacher Account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Reactivate account for "${teacher.name}" (@${teacher.loginUsername})?\n\nThis will restore their ability to log in with their current credentials and mark attendance.',
          style: const TextStyle(fontSize: 13.5, color: AppColors.textStrong),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
            icon: const Icon(LucideIcons.userCheck, size: 16),
            label: const Text('Reactivate Account'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final repo = ref.read(teacherAdminRepositoryProvider);
        await repo.setTeacherActive(teacherId: teacher.id, active: true);
        ref.invalidate(teachersListProvider);
        ref.invalidate(teacherDetailProvider(teacher.id));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Teacher "${teacher.name}" is now reactivated.'),
              backgroundColor: const Color(0xFF059669),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to reactivate: $e'), backgroundColor: Colors.red.shade700),
          );
        }
      }
    }
  }

  /// 3. Reset Password Dialog (Generate or Custom)
  static Future<void> showResetPassword(BuildContext context, WidgetRef ref, Teacher teacher) async {
    final userId = teacher.userId ?? teacher.id.toString();

    final result = await showDialog<({String mode, String? tempPassword})?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TeacherResetPasswordDialog(teacher: teacher),
    );

    if (result != null && context.mounted) {
      try {
        final repo = ref.read(teacherAdminRepositoryProvider);
        final res = await repo.resetTeacherPassword(
          userId: userId,
          mode: result.mode,
          tempPassword: result.tempPassword,
          username: teacher.loginUsername,
        );

        final returnedPassword = res['temporary_password']?.toString() ??
            result.tempPassword ??
            'MipsReset@${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}!';

        ref.invalidate(teachersListProvider);
        ref.invalidate(teacherDetailProvider(teacher.id));

        if (context.mounted) {
          await OneTimePasswordDialog.show(
            context,
            title: 'Password Reset Successful',
            recipientName: teacher.name,
            usernameOrIdentifier: teacher.loginUsername,
            temporaryPassword: returnedPassword,
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to reset password: $e'), backgroundColor: Colors.red.shade700),
          );
        }
      }
    }
  }

  /// 3B. Reset to First-Time Login (Mobile Verification)
  static Future<void> confirmResetToFirstLogin(BuildContext context, WidgetRef ref, Teacher teacher) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(
          children: const [
            Icon(LucideIcons.rotateCcw, color: AppColors.brand, size: 22),
            SizedBox(width: 10),
            Text('Reset to First-Time Login', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Invalidate login password for "${teacher.name}" (@${teacher.loginUsername})?',
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
                child: Text(
                  '• The teacher\'s current password will be immediately invalidated.\n'
                  '• All active portal sessions will be logged out.\n'
                  '• On their next login attempt, the teacher must verify their identity using their Staff Username (@${teacher.loginUsername}) and Registered Mobile Number (${teacher.phone ?? 'N/A'}) to set a new password.',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E), height: 1.35),
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
        final repo = ref.read(teacherAdminRepositoryProvider);
        await repo.resetTeacherToFirstLogin(teacher);
        ref.invalidate(teachersListProvider);
        ref.invalidate(teacherDetailProvider(teacher.id));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Account for "${teacher.name}" reset to first-time login. Teacher will verify with mobile number.'),
              backgroundColor: const Color(0xFF0F766E),
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

  /// 4. Unlock Account Dialog
  static Future<void> confirmUnlock(BuildContext context, WidgetRef ref, Teacher teacher) async {
    final userId = teacher.userId ?? teacher.id.toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(
          children: const [
            Icon(LucideIcons.unlock, color: Color(0xFF2563EB), size: 22),
            SizedBox(width: 10),
            Text('Unlock Account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Unlock the login account for "${teacher.name}" (@${teacher.loginUsername})?\n\nThis will clear all failed login attempt counters and lift the temporary lockout immediately.',
          style: const TextStyle(fontSize: 13.5, color: AppColors.textStrong),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
            icon: const Icon(LucideIcons.unlock, size: 16),
            label: const Text('Unlock Account'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final repo = ref.read(teacherAdminRepositoryProvider);
        await repo.unlockAccount(userId);
        ref.invalidate(teachersListProvider);
        ref.invalidate(teacherDetailProvider(teacher.id));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Account for "${teacher.name}" has been unlocked.'),
              backgroundColor: const Color(0xFF2563EB),
            ),
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
}

class _TeacherResetPasswordDialog extends StatefulWidget {
  final Teacher teacher;

  const _TeacherResetPasswordDialog({required this.teacher});

  @override
  State<_TeacherResetPasswordDialog> createState() => _TeacherResetPasswordDialogState();
}

class _TeacherResetPasswordDialogState extends State<_TeacherResetPasswordDialog> {
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
    if (val.toLowerCase().contains(widget.teacher.loginUsername.toLowerCase())) {
      return 'Password cannot contain the teacher username.';
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
          Text('Reset Teacher Password', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                  'Issuing a new password for "${widget.teacher.name}". The teacher will be forced to choose a new password upon their next login.',
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
                        subtitle: const Text('Random 12-char secure string', style: TextStyle(fontSize: 11.5)),
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
                      labelText: 'New Temporary Password *',
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
          label: const Text('Reset Password'),
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
