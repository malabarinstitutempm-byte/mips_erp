import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/kpi_card.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/progress_bar.dart';

import 'collect_payment_dialog.dart';
import 'fees_provider.dart';
import 'package:intl/intl.dart';
import '../students/student_provider.dart';

class FeesScreen extends ConsumerStatefulWidget {
  const FeesScreen({super.key});

  @override
  ConsumerState<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends ConsumerState<FeesScreen> {
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
  int _mobileTab = 0; // 0 = Pending Dues, 1 = Recent Payments

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingFeesProvider);
    final recentAsync = ref.watch(recentPaymentsProvider);
    final metricsAsync = ref.watch(feeMetricsProvider);
    final isMobile = MediaQuery.of(context).size.width < 800;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'Fee Collection',
          subtitle: 'Manage payments, track dues, and generate receipts',
        ),
        
        // KPI Section
        metricsAsync.when(
          data: (metrics) {
            final kpi1 = KpiCard(
              title: 'Total Receivable',
              value: _currencyFormat.format(metrics['total'] ?? 0.0),
              icon: LucideIcons.layers,
              baseColor: AppColors.info.base,
              tintColor: AppColors.info.tint,
            );
            final kpi2 = KpiCard(
              title: 'Collected This Month',
              value: _currencyFormat.format(metrics['collected'] ?? 0.0),
              icon: LucideIcons.indianRupee,
              baseColor: AppColors.success.base,
              tintColor: AppColors.success.tint,
            );
            final kpi3 = KpiCard(
              title: 'Overdue Dues',
              value: _currencyFormat.format(metrics['pending'] ?? 0.0),
              icon: LucideIcons.alertTriangle,
              baseColor: AppColors.danger.base,
              tintColor: AppColors.danger.tint,
            );

            if (isMobile) {
              return SizedBox(
                height: 105,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    SizedBox(width: 220, child: kpi1),
                    const SizedBox(width: 10),
                    SizedBox(width: 220, child: kpi2),
                    const SizedBox(width: 10),
                    SizedBox(width: 220, child: kpi3),
                  ],
                ),
              );
            }

            return Row(
              children: [
                Expanded(child: kpi1),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: kpi2),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: kpi3),
              ],
            );
          },
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
          error: (_,__) => const Text('Error loading metrics'),
        ),
        
        const SizedBox(height: AppSpacing.lg),

        // Mobile Tab Switcher
        if (isMobile) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(LucideIcons.alertTriangle, size: 14),
                    label: Text('Pending Dues', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(LucideIcons.history, size: 14),
                    label: Text('Recent Payments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
                selected: {_mobileTab},
                onSelectionChanged: (val) => setState(() => _mobileTab = val.first),
              ),
            ),
          ),
        ],
        
        // Main Content
        Expanded(
          child: isMobile
              ? Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: _mobileTab == 0
                      // Mobile View 0: Pending Dues Cards
                      ? pendingAsync.when(
                          data: (pendingStudents) {
                            if (pendingStudents.isEmpty) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('No pending dues found.', style: TextStyle(color: AppColors.textMuted)),
                                ),
                              );
                            }
                            return ListView.separated(
                              itemCount: pendingStudents.length,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final s = pendingStudents[index];
                                final total = (s['total'] as num);
                                final progress = total > 0 ? (s['paid'] as num) / total : 0.0;

                                return Container(
                                  padding: const EdgeInsets.all(12),
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
                                          AppAvatar(name: s['name'], radius: 18),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  s['name']?.toString() ?? 'Unknown',
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textStrong),
                                                ),
                                                Text(
                                                  'Adm: ${s['adm']} • ${s['course'] ?? ""}',
                                                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            _currencyFormat.format(s['pending']),
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.danger.base),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Paid: ${_currencyFormat.format(s['paid'])}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                                          Text('Total: ${_currencyFormat.format(s['total'])}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      ProgressBar(progress: progress.toDouble(), height: 6),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.brand,
                                            side: const BorderSide(color: AppColors.brand),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                          onPressed: () async {
                                            final studentRepo = ref.read(studentRepositoryProvider);
                                            final student = await studentRepo.getStudentById(s['id']);
                                            if (student != null && context.mounted) {
                                              showDialog(
                                                context: context,
                                                builder: (_) => CollectPaymentDialog(
                                                  student: student,
                                                  pendingAmount: (s['pending'] as num).toDouble(),
                                                ),
                                              );
                                            }
                                          },
                                          icon: const Icon(LucideIcons.receipt, size: 14),
                                          label: const Text('Collect Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (_, __) => const Center(child: Text('Error loading pending dues')),
                        )
                      // Mobile View 1: Recent Payments
                      : recentAsync.when(
                          data: (recentPayments) {
                            if (recentPayments.isEmpty) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('No recent payments found.', style: TextStyle(color: AppColors.textMuted)),
                                ),
                              );
                            }
                            return ListView.separated(
                              itemCount: recentPayments.length,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final p = recentPayments[index];
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(AppRadius.card),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.fees.tint,
                                          borderRadius: BorderRadius.circular(AppRadius.control),
                                        ),
                                        child: Icon(LucideIcons.indianRupee, size: 16, color: AppColors.fees.dark),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(p['name']?.toString() ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                            Text('${p['date']} • ${p['mode']}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('+ ${_currencyFormat.format(p['amount'])}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.success.base)),
                                          Text(p['receipt']?.toString() ?? 'No Receipt', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (_, __) => const Center(child: Text('Error loading recent payments')),
                        ),
                )
              // Desktop View: Side by Side
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pending Fees List
                    Expanded(
                      flex: 2,
                      child: Container(
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: AppColors.border)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Text('Pending Dues (Highest First)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                            const Divider(height: 1),
                            // Header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                              child: const Row(
                                children: [
                                  Expanded(flex: 2, child: Text('STUDENT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                                  Expanded(flex: 1, child: Text('COURSE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                                  Expanded(flex: 2, child: Text('PROGRESS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                                  Expanded(flex: 1, child: Text('PENDING', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                                  Expanded(flex: 1, child: SizedBox()), // Action
                                ],
                              ),
                            ),
                            
                            // List
                            Expanded(
                              child: pendingAsync.when(
                                data: (pendingStudents) => ListView.builder(
                                  itemCount: pendingStudents.length,
                                  itemBuilder: (context, index) {
                                    final s = pendingStudents[index];
                                    final total = (s['total'] as num);
                                    final progress = total > 0 ? (s['paid'] as num) / total : 0.0;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: Row(
                                              children: [
                                                AppAvatar(name: s['name'], radius: 16),
                                                const SizedBox(width: AppSpacing.md),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(s['name']?.toString() ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textStrong)),
                                                      Text(s['adm']?.toString() ?? 'N/A', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text(s['course']?.toString() ?? '', style: const TextStyle(color: AppColors.textBody)),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Padding(
                                              padding: const EdgeInsets.only(right: AppSpacing.xl),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(_currencyFormat.format(s['paid']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textStrong)),
                                                      Text(_currencyFormat.format(s['total']), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  ProgressBar(progress: progress.toDouble(), height: 6),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text(_currencyFormat.format(s['pending']), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.danger.base)),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: OutlinedButton(
                                                onPressed: () async {
                                                  final studentRepo = ref.read(studentRepositoryProvider);
                                                  final student = await studentRepo.getStudentById(s['id']);
                                                  if (student != null && context.mounted) {
                                                    showDialog(
                                                      context: context,
                                                      builder: (_) => CollectPaymentDialog(student: student, pendingAmount: (s['pending'] as num).toDouble()),
                                                    );
                                                  }
                                                },
                                                child: const Text('Collect'),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                loading: () => const Center(child: CircularProgressIndicator()),
                                error: (_,__) => const Center(child: Text('Error loading pending fees')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: AppSpacing.xl),
                    
                    // Recent Payments
                    Expanded(
                      flex: 1,
                      child: Container(
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: AppColors.border)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Text('Recent Payments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                            const Divider(height: 1),
                            Expanded(
                              child: recentAsync.when(
                                data: (recentPayments) => ListView.builder(
                                  itemCount: recentPayments.length,
                                  itemBuilder: (context, index) {
                                    final p = recentPayments[index];
                                    return Container(
                                      padding: const EdgeInsets.all(AppSpacing.lg),
                                      decoration: const BoxDecoration(
                                        border: Border(bottom: BorderSide(color: AppColors.border)),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(AppSpacing.sm),
                                            decoration: BoxDecoration(
                                              color: AppColors.fees.tint,
                                              borderRadius: BorderRadius.circular(AppRadius.control),
                                            ),
                                            child: Icon(LucideIcons.indianRupee, size: 18, color: AppColors.fees.dark),
                                          ),
                                          const SizedBox(width: AppSpacing.md),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(p['name']?.toString() ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600)),
                                                Text('${p['date']} • ${p['mode']}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text('+ ${_currencyFormat.format(p['amount'])}', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.success.base)),
                                              Text(p['receipt']?.toString() ?? 'No Receipt', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                loading: () => const Center(child: CircularProgressIndicator()),
                                error: (_,__) => const Center(child: Text('Error loading recent payments')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

