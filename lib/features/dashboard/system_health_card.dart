import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/section_card.dart';
import '../backup/backup_service.dart';

class SystemHealthState {
  final BackupInfo backupInfo;
  final int failedLogins24h;
  final int lockedAccountsCount;
  final int unmarkedSessionsCount;
  final bool isLoading;

  SystemHealthState({
    required this.backupInfo,
    required this.failedLogins24h,
    required this.lockedAccountsCount,
    required this.unmarkedSessionsCount,
    this.isLoading = false,
  });

  factory SystemHealthState.initial() => SystemHealthState(
        backupInfo: BackupInfo.none(),
        failedLogins24h: 0,
        lockedAccountsCount: 0,
        unmarkedSessionsCount: 0,
        isLoading: true,
      );
}

final systemHealthProvider = FutureProvider.autoDispose<SystemHealthState>((ref) async {
  final backupInfo = await BackupService.getLastBackupInfo();

  int failedLogins = 0;
  int lockedAccounts = 0;
  int unmarkedSessions = 0;

  try {
    final client = SupabaseService.instance.client;

    // 1. Failed logins in last 24h
    final since24h = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();
    final failedRes = await client
        .from('login_attempts')
        .select('id')
        .eq('success', false)
        .gte('attempted_at', since24h);
    failedLogins = (failedRes as List).length;

    // 2. Locked accounts count
    final lockedRes = await client
        .from('profiles')
        .select('user_id')
        .not('locked_at', 'is', null);
    lockedAccounts = (lockedRes as List).length;

    // 3. Unmarked sessions today across active primary batches
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      final slotStatusRes = await client.rpc('attendance_slot_status', params: {'p_date': todayStr});
      if (slotStatusRes is List) {
        unmarkedSessions = slotStatusRes.where((s) => s['state'] == 'not_marked').length;
      }
    } catch (_) {
      // Fallback query if RPC unavailable
      final sessionsRes = await client
          .from('attendance_sessions')
          .select('id')
          .eq('date', todayStr)
          .eq('status', 'draft');
      unmarkedSessions = (sessionsRes as List).length;
    }
  } catch (_) {
    // If offline or network unavailable, gracefully present available offline indicators
  }

  return SystemHealthState(
    backupInfo: backupInfo,
    failedLogins24h: failedLogins,
    lockedAccountsCount: lockedAccounts,
    unmarkedSessionsCount: unmarkedSessions,
    isLoading: false,
  );
});

class SystemHealthCard extends ConsumerStatefulWidget {
  const SystemHealthCard({super.key});

  @override
  ConsumerState<SystemHealthCard> createState() => _SystemHealthCardState();
}

class _SystemHealthCardState extends ConsumerState<SystemHealthCard> {
  bool _isBackingUp = false;

  Future<void> _handleBackupNow() async {
    setState(() => _isBackingUp = true);
    try {
      final zipPath = await BackupService.exportCloudDatabaseBackup();
      if (mounted) {
        ref.invalidate(systemHealthProvider);
        final message = kIsWeb
            ? 'Backup archive downloaded successfully: $zipPath'
            : 'Backup created successfully: $zipPath';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.success.base,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: $e'),
            backgroundColor: AppColors.danger.base,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  Future<void> _handleCopyToUsb() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Direct folder/USB drive selection is available on Windows Desktop. On web, use "Backup Now" above to download your backup archive.',
            ),
            backgroundColor: Color(0xFF0F766E),
          ),
        );
      }
      return;
    }
    try {
      final selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select USB Flash Drive or External Backup Folder',
      );

      if (selectedDirectory == null) return;

      final targetPath = await BackupService.copyLatestBackupTo(selectedDirectory);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup copied successfully to USB: $targetPath'),
            backgroundColor: AppColors.success.base,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to copy backup: $e'),
            backgroundColor: AppColors.danger.base,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final healthAsync = ref.watch(systemHealthProvider);

    return healthAsync.when(
      data: (health) => _buildCardContent(context, health),
      loading: () => SectionCard(
        title: 'System Health & Offline Backup Status',
        child: const Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, __) => _buildCardContent(context, SystemHealthState.initial()),
    );
  }

  Widget _buildCardContent(BuildContext context, SystemHealthState state) {
    final info = state.backupInfo;
    final isStale = info.isOlderThan3Days || info.lastBackupDate == null;

    final backupDateText = info.lastBackupDate != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(info.lastBackupDate!)
        : 'Never (No backup found)';

    return SectionCard(
      title: 'Institutional System Health & Backup Checklist',
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning Banner if backup is > 3 days old
            if (isStale)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warning.tint,
                  border: Border.all(color: AppColors.warning.base),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.alertTriangle, color: AppColors.warning.base, size: 20),
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(
                      child: Text(
                        'Warning: Last offline backup was taken more than 3 days ago. Run an offline backup now to protect against data loss.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textStrong,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Health Checklist Grid
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.md,
              children: [
                _buildMetricTile(
                  icon: LucideIcons.hardDrive,
                  label: 'Last Offline Backup',
                  value: backupDateText,
                  subvalue: 'Size: ${info.formattedSize}',
                  isWarning: isStale,
                ),
                _buildMetricTile(
                  icon: LucideIcons.shieldAlert,
                  label: 'Failed Logins (24h)',
                  value: '${state.failedLogins24h} attempt(s)',
                  subvalue: state.failedLogins24h >= 5 ? 'High failure rate' : 'Normal',
                  isWarning: state.failedLogins24h >= 5,
                ),
                _buildMetricTile(
                  icon: LucideIcons.lock,
                  label: 'Locked Accounts',
                  value: '${state.lockedAccountsCount} user(s)',
                  subvalue: state.lockedAccountsCount > 0 ? 'Requires admin unlock' : 'All active',
                  isWarning: state.lockedAccountsCount > 0,
                ),
                _buildMetricTile(
                  icon: LucideIcons.calendarCheck,
                  label: 'Unmarked Sessions',
                  value: '${state.unmarkedSessionsCount} draft slot(s)',
                  subvalue: 'For today',
                  isWarning: state.unmarkedSessionsCount > 0,
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.md),

            // Action Buttons
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isBackingUp ? null : _handleBackupNow,
                  icon: _isBackingUp
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.downloadCloud, size: 16),
                  label: Text(_isBackingUp ? 'Exporting...' : 'Backup Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _handleCopyToUsb,
                  icon: const Icon(LucideIcons.usb, size: 16),
                  label: const Text('Copy backup to another folder or drive'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textStrong,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required String subvalue,
    required bool isWarning,
  }) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isWarning ? AppColors.warning.tint.withOpacity(0.4) : AppColors.surface,
        border: Border.all(color: isWarning ? AppColors.warning.base : AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: isWarning ? AppColors.warning.base : AppColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isWarning ? AppColors.danger.base : AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subvalue,
            style: TextStyle(
              fontSize: 11,
              color: isWarning ? AppColors.danger.base : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
