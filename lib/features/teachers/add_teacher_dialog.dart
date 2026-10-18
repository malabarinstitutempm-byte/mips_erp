import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'one_time_password_dialog.dart';
import 'teacher_provider.dart';

class AddTeacherDialog extends ConsumerStatefulWidget {
  const AddTeacherDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AddTeacherDialog(),
    );
  }

  @override
  ConsumerState<AddTeacherDialog> createState() => _AddTeacherDialogState();
}

class _AddTeacherDialogState extends ConsumerState<AddTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isAutoGenerate = true;
  bool _isSubmitting = false;
  String? _usernameError;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_updateSyntheticEmail);
    _nameController.addListener(() {
      if (_usernameController.text.isEmpty && _nameController.text.isNotEmpty) {
        final slug = _nameController.text
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '_')
            .replaceAll(RegExp(r'_+'), '_');
        _usernameController.text = slug;
      }
    });
  }

  void _updateSyntheticEmail() {
    final u = _usernameController.text.trim().toLowerCase();
    if (u.isNotEmpty) {
      _emailController.text = '$u@teachers.mips.invalid';
    } else {
      _emailController.text = '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
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
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(val)) return 'Must contain at least one symbol (!@#\$%^&*).';

    final username = _usernameController.text.trim().toLowerCase();
    if (username.length >= 3 && val.toLowerCase().contains(username)) {
      return 'Password cannot contain the username.';
    }

    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _usernameError = null;
    });

    if (!_formKey.currentState!.validate()) return;

    final teachers = ref.read(teachersListProvider).valueOrNull ?? [];
    final cleanUsername = _usernameController.text.trim().toLowerCase();

    // Live Uniqueness Check
    final isTaken = teachers.any((t) => t.loginUsername.toLowerCase() == cleanUsername);
    if (isTaken) {
      setState(() {
        _usernameError = "Username '$cleanUsername' is already taken by another teacher.";
      });
      return;
    }

    final tempPassword = _isAutoGenerate ? _generatePassword() : _passwordController.text.trim();

    setState(() {
      _isSubmitting = true;
    });

    try {
      final repo = ref.read(teacherAdminRepositoryProvider);
      final res = await repo.createTeacher(
        name: _nameController.text.trim(),
        username: cleanUsername,
        phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        tempPassword: tempPassword,
      );

      final returnedPassword = (res['teacher'] is Map && res['teacher']['temporary_password'] != null)
          ? res['teacher']['temporary_password'].toString()
          : tempPassword;

      ref.invalidate(teachersListProvider);

      if (mounted) {
        Navigator.of(context).pop(true);

        await OneTimePasswordDialog.show(
          context,
          title: 'Teacher Provisioned Successfully',
          recipientName: _nameController.text.trim(),
          usernameOrIdentifier: cleanUsername,
          temporaryPassword: returnedPassword,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add teacher: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      title: Row(
        children: const [
          Icon(LucideIcons.userPlus, color: AppColors.brand, size: 22),
          SizedBox(width: 10),
          Text('Add New Teacher', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Text(
                  'Provision an administrative faculty account. Every teacher can mark attendance for any course.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Teacher Full Name *',
                    hintText: 'e.g. Prof. Tariq Jameel',
                    prefixIcon: Icon(LucideIcons.user, size: 18),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Teacher name is required.';
                    if (val.trim().length < 2) return 'Name must be at least 2 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Phone
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Contact Phone Number (Optional)',
                    hintText: 'e.g. 9876543210',
                    prefixIcon: Icon(LucideIcons.phone, size: 18),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),

                // Username
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Login Username *',
                    hintText: 'e.g. tariq_j',
                    prefixIcon: const Icon(LucideIcons.atSign, size: 18),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: _usernameError,
                    helperText: 'Unique identifier used to sign in.',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Username is required.';
                    final clean = val.trim().toLowerCase();
                    if (clean.length < 3) return 'Username must be at least 3 characters.';
                    if (!RegExp(r'^[a-z0-9_.-]+$').hasMatch(clean)) {
                      return 'Only lowercase letters, numbers, underscores, dots, or dashes.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Synthetic Email (Read only info)
                TextFormField(
                  controller: _emailController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'System Email (Generated)',
                    prefixIcon: Icon(LucideIcons.mail, size: 18),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFFF8FAFC),
                    isDense: true,
                    helperText: 'Internal auth identifier created automatically.',
                  ),
                ),
                const SizedBox(height: 18),

                // Temporary Password Configuration
                const Text(
                  'Initial Temporary Password',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        value: true,
                        groupValue: _isAutoGenerate,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Auto-generate', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Cryptographically secure 12-char', style: TextStyle(fontSize: 11.5)),
                        onChanged: (val) {
                          setState(() {
                            _isAutoGenerate = val ?? true;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        value: false,
                        groupValue: _isAutoGenerate,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Custom password', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Specify temporary credentials', style: TextStyle(fontSize: 11.5)),
                        onChanged: (val) {
                          setState(() {
                            _isAutoGenerate = val ?? false;
                          });
                        },
                      ),
                    ),
                  ],
                ),

                if (!_isAutoGenerate) ...[
                  const SizedBox(height: 8),
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
                            icon: Icon(
                              _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                              size: 18,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                            icon: const Icon(LucideIcons.sparkles, size: 14, color: AppColors.brand),
                            label: const Text('Generate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              setState(() {
                                _passwordController.text = _generatePassword();
                                _obscurePassword = false;
                              });
                            },
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Password Policy Rules:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text('• Minimum 8 characters\n• At least 1 uppercase and 1 lowercase letter\n• At least 1 number and 1 symbol (!@#\$%^&*)\n• Cannot match or contain username',
                            style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.3)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          icon: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(LucideIcons.check, size: 16),
          label: Text(_isSubmitting ? 'Provisioning...' : 'Provision Teacher'),
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
    );
  }
}
