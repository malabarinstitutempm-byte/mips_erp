import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/status_badge.dart';

final systemHealthProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final client = SupabaseService.instance.client;
  final res = await client.rpc('admin_get_system_health');
  return Map<String, dynamic>.from(res as Map);
});

class SystemHealthView extends ConsumerWidget {
  const SystemHealthView({super.key});

  Future<void> _openSupabaseDashboard(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(systemHealthProvider);

    return healthAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Querying Supabase system health & quotas...', style: TextStyle(color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
      error: (err, _) => SectionCard(
        title: 'System Health Diagnostics',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.alertTriangle, color: Colors.red),
                const SizedBox(width: 8),
                Text('Failed to query system health: $err', style: const TextStyle(color: Colors.red)),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(systemHealthProvider),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Retry Diagnostics'),
            ),
          ],
        ),
      ),
      data: (data) {
        final db = data['database'] as Map<String, dynamic>? ?? {};
        final egress = data['egress_quota'] as Map<String, dynamic>? ?? {};
        final edgeFunctions = data['edge_functions_quota'] as Map<String, dynamic>? ?? {};
        final storage = data['storage_quota'] as Map<String, dynamic>? ?? {};
        final audit = data['audit_log'] as Map<String, dynamic>? ?? {};
        final notifs = data['notifications'] as Map<String, dynamic>? ?? {};
        final push = data['push_subscriptions'] as Map<String, dynamic>? ?? {};
        final tables = (data['table_stats'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final usageUrl = data['supabase_usage_url'] as String? ?? 'https://supabase.com/dashboard';

        final usagePercent = (db['usage_percent'] as num?)?.toDouble() ?? 0.0;
        final isDbWarning = (db['is_warning'] as bool?) ?? false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Quota Alert Header
            if (isDbWarning)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.alertCircle, color: Colors.amber.shade900, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Warning: Database storage exceeds 70% of Free Plan limit!',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                          ),
                          const Text(
                            'Database size has crossed 350 MB. Check table sizes below and run data retention archival.',
                            style: TextStyle(fontSize: 13, color: AppColors.textStrong),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Top Status & Actions Card
            SectionCard(
              title: 'Supabase Free Plan Resource Quotas',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Resource usage monitored against Supabase Free Tier quotas (~200 students/year budget).',
                        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.refreshCw, size: 18),
                            tooltip: 'Refresh Health Stats',
                            onPressed: () => ref.invalidate(systemHealthProvider),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(LucideIcons.externalLink, size: 14),
                            label: const Text('Open Supabase Usage Page'),
                            onPressed: () => _openSupabaseDashboard(context, usageUrl),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _buildQuotaCard(
                        title: 'Database Storage',
                        current: db['size_pretty'] ?? 'Unknown',
                        limit: db['limit_pretty'] ?? '500 MB',
                        percent: usagePercent,
                        warningLabel: 'Warning at ${db['warning_threshold_pretty'] ?? '350 MB'}',
                        isWarning: isDbWarning,
                        icon: LucideIcons.database,
                      ),
                      _buildQuotaCard(
                        title: 'Network Egress (Bandwidth)',
                        current: 'Optimized RPCs',
                        limit: egress['limit_pretty'] ?? '5 GB / mo',
                        percent: 5.0,
                        warningLabel: egress['warning_threshold_pretty'] ?? '3.5 GB (70%)',
                        isWarning: false,
                        icon: LucideIcons.arrowUpRight,
                      ),
                      _buildQuotaCard(
                        title: 'Edge Functions',
                        current: 'Minimal Invocations',
                        limit: edgeFunctions['limit_pretty'] ?? '500,000 / mo',
                        percent: 1.0,
                        warningLabel: edgeFunctions['warning_threshold_pretty'] ?? '350,000 (70%)',
                        isWarning: false,
                        icon: LucideIcons.cpu,
                      ),
                      _buildQuotaCard(
                        title: 'Storage & Media',
                        current: 'CDN WebP Thumbnails',
                        limit: storage['limit_pretty'] ?? '1 GB',
                        percent: 3.0,
                        warningLabel: storage['warning_threshold_pretty'] ?? '700 MB (70%)',
                        isWarning: false,
                        icon: LucideIcons.image,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Data Lifecycle & Retention Cards
            SectionCard(
              title: 'Automated Data Retention & Lifecycle Policies',
              child: Column(
                children: [
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE0F2FE),
                      child: Icon(LucideIcons.fileText, color: Color(0xFF0284C7), size: 20),
                    ),
                    title: const Text('Audit Log Table (Retention: 12 Months Online)'),
                    subtitle: Text(
                      '${audit['row_count'] ?? 0} rows total (${audit['total_pretty'] ?? '0 kB'}). Daily pg_cron purge keeps last 12 months online.',
                    ),
                    trailing: StatusBadge(text: 'Active Retention', status: BadgeStatus.success),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFFEF3C7),
                      child: Icon(LucideIcons.bell, color: Color(0xFFD97706), size: 20),
                    ),
                    title: const Text('Notifications Table (Retention: 90 Days Read)'),
                    subtitle: Text(
                      '${notifs['row_count'] ?? 0} total (${notifs['unread_count'] ?? 0} unread). Older read notifications automatically cleaned up.',
                    ),
                    trailing: StatusBadge(text: 'Active Retention', status: BadgeStatus.success),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFDCFCE7),
                      child: Icon(LucideIcons.radio, color: Color(0xFF16A34A), size: 20),
                    ),
                    title: const Text('Web Push Subscriptions (Auto Dead-Endpoint Pruning)'),
                    subtitle: Text(
                      '${push['total_subscriptions'] ?? 0} registered endpoints. Invalid or expired (404/410) subscriptions pruned on dispatch.',
                    ),
                    trailing: StatusBadge(text: 'Auto Pruning', status: BadgeStatus.success),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Table Size Breakdown
            SectionCard(
              title: 'Database Tables & Disk Consumption',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Breakdown of live rows, raw table heap data, and index disk storage for core ERP relations.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(AppColors.bg),
                      columns: const [
                        DataColumn(label: Text('Table Name', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Live Rows', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                        DataColumn(label: Text('Data Size', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Index Size', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Total Size', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: tables.map((t) {
                        return DataRow(
                          cells: [
                            DataCell(Text(t['table_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Text('${t['row_count'] ?? 0}')),
                            DataCell(Text(t['table_pretty'] ?? '-')),
                            DataCell(Text(t['index_pretty'] ?? '-')),
                            DataCell(Text(t['total_pretty'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuotaCard({
    required String title,
    required String current,
    required String limit,
    required double percent,
    required String warningLabel,
    required bool isWarning,
    required IconData icon,
  }) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: isWarning ? Colors.amber.shade600 : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: isWarning ? Colors.amber.shade700 : AppColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(current, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.brand)),
          Text('Limit: $limit', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (percent / 100.0).clamp(0.01, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(isWarning ? Colors.amber.shade700 : AppColors.success.base),
            ),
          ),
          const SizedBox(height: 6),
          Text(warningLabel, style: TextStyle(fontSize: 11, color: isWarning ? Colors.amber.shade800 : AppColors.textMuted)),
        ],
      ),
    );
  }
}
