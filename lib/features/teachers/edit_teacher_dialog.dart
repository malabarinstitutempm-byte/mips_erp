import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/models/teacher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'teacher_provider.dart';

class EditTeacherDialog extends ConsumerStatefulWidget {
  final Teacher teacher;

  const EditTeacherDialog({super.key, required this.teacher});

  static Future<bool?> show(BuildContext context, Teacher teacher) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EditTeacherDialog(teacher: teacher),
    );
  }

  @override
  ConsumerState<EditTeacherDialog> createState() => _EditTeacherDialogState();
}

class _EditTeacherDialogState extends ConsumerState<EditTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _usernameController;

  bool _isSubmitting = false;
  String? _usernameError;
  bool _usernameChanged = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.teacher.name);
    _phoneController = TextEditingController(text: widget.teacher.phone ?? '');
    _usernameController = TextEditingController(text: widget.teacher.loginUsername);

    _usernameController.addListener(() {
      final current = _usernameController.text.trim().toLowerCase();
      final original = widget.teacher.loginUsername.toLowerCase();
      if (_usernameChanged != (current != original)) {
        setState(() {
          _usernameChanged = (current != original);
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _usernameError = null;
    });

    if (!_formKey.currentState!.validate()) return;

    final cleanUsername = _usernameController.text.trim().toLowerCase();

    // If username changed, verify uniqueness
    if (_usernameChanged) {
      final teachers = ref.read(teachersListProvider).valueOrNull ?? [];
      final isTaken = teachers.any((t) => t.id != widget.teacher.id && t.loginUsername.toLowerCase() == cleanUsername);
      if (isTaken) {
        setState(() {
          _usernameError = "Username '$cleanUsername' is already taken by another teacher.";
        });
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final repo = ref.read(teacherAdminRepositoryProvider);
      await repo.updateTeacher(
        teacherId: widget.teacher.id,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        username: cleanUsername,
      );

      ref.invalidate(teachersListProvider);
      ref.invalidate(teacherDetailProvider(widget.teacher.id));

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Teacher profile updated successfully.'),
            backgroundColor: Color(0xFF0F766E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update teacher: $e'),
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
          Icon(LucideIcons.edit3, color: AppColors.brand, size: 22),
          SizedBox(width: 10),
          Text('Edit Teacher Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                const SizedBox(height: 8),

                // Warning when username is modified
                if (_usernameChanged) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(LucideIcons.alertTriangle, color: Color(0xFFD97706), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Warning: Changing the username modifies the teacher\'s login identity! The teacher must use the new username to sign in. Their password remains unchanged.',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E), height: 1.35, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Teacher Name *',
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
                    labelText: 'Phone Number',
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
                    prefixIcon: const Icon(LucideIcons.atSign, size: 18),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: _usernameError,
                    helperText: 'Login handle used by teacher.',
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
          label: Text(_isSubmitting ? 'Saving...' : 'Save Changes'),
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
    );
  }
}
