import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

class OneTimePasswordDialog extends StatelessWidget {
  final String title;
  final String recipientName;
  final String usernameOrIdentifier;
  final String temporaryPassword;

  const OneTimePasswordDialog({
    super.key,
    required this.title,
    required this.recipientName,
    required this.usernameOrIdentifier,
    required this.temporaryPassword,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String recipientName,
    required String usernameOrIdentifier,
    required String temporaryPassword,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => OneTimePasswordDialog(
        title: title,
        recipientName: recipientName,
        usernameOrIdentifier: usernameOrIdentifier,
        temporaryPassword: temporaryPassword,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.brandTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.keyRound, color: AppColors.brand, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(LucideIcons.alertTriangle, color: Color(0xFFD97706), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The teacher must change this at first login.\nThis temporary password cannot be viewed again once this dialog is closed.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Account Credentials for $recipientName:',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textStrong),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Text('Login Username: ', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  Text(
                    usernameOrIdentifier,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Temporary Password:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textStrong),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      temporaryPassword,
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(LucideIcons.copy, size: 14),
                    label: const Text('Copy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: temporaryPassword));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Temporary password copied to clipboard!'),
                          backgroundColor: Color(0xFF0F766E),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandDark,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
