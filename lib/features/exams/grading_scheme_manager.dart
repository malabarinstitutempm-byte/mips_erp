import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/models/grading_scheme.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/status_badge.dart';
import 'grading_provider.dart';

class GradingSchemeManagerView extends ConsumerStatefulWidget {
  final bool isEmbeddedInDialog;
  const GradingSchemeManagerView({super.key, this.isEmbeddedInDialog = false});

  @override
  ConsumerState<GradingSchemeManagerView> createState() => _GradingSchemeManagerViewState();
}

class _GradingSchemeManagerViewState extends ConsumerState<GradingSchemeManagerView> {
  final _testPercentageCtrl = TextEditingController(text: '75.0');
  double _testPct = 75.0;

  @override
  void initState() {
    super.initState();
    _testPercentageCtrl.addListener(() {
      final parsed = double.tryParse(_testPercentageCtrl.text);
      if (parsed != null && parsed != _testPct) {
        setState(() => _testPct = parsed);
      }
    });
  }

  @override
  void dispose() {
    _testPercentageCtrl.dispose();
    super.dispose();
  }

  void _showAddEditTierDialog({GradingScheme? existingScheme}) {
    final isEditing = existingScheme != null;
    final gradeCtrl = TextEditingController(text: existingScheme?.grade ?? '');
    final minCtrl = TextEditingController(
      text: existingScheme != null ? existingScheme.minPercent.toString() : '',
    );
    final maxCtrl = TextEditingController(
      text: existingScheme != null ? existingScheme.maxPercent.toString() : '',
    );
    bool isPass = existingScheme?.isPass ?? true;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
            title: Row(
              children: [
                Icon(
                  isEditing ? LucideIcons.edit3 : LucideIcons.plusCircle,
                  color: AppColors.exams.base,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  isEditing ? 'Edit Grade Tier' : 'Add New Grade Tier',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: gradeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Grade Label *',
                        hintText: 'e.g. A+, Distinction, Excellent',
                        prefixIcon: Icon(LucideIcons.award, size: 18),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Please enter a grade label';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: minCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Min Percentage (%) *',
                              hintText: 'e.g. 80.0',
                              suffixText: '%',
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Required';
                              final val = double.tryParse(v);
                              if (val == null || val < 0 || val > 100) return '0 - 100';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: maxCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Max Percentage (%) *',
                              hintText: 'e.g. 89.99',
                              suffixText: '%',
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Required';
                              final val = double.tryParse(v);
                              if (val == null || val < 0 || val > 100) return '0 - 100';
                              final minV = double.tryParse(minCtrl.text);
                              if (minV != null && val <= minV) return '> Min %';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isPass ? AppColors.success.tint : AppColors.danger.tint,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(
                          color: (isPass ? AppColors.success.base : AppColors.danger.base).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isPass ? LucideIcons.checkCircle2 : LucideIcons.xCircle,
                            size: 18,
                            color: isPass ? AppColors.success.base : AppColors.danger.base,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isPass ? 'Qualifying / Passing Grade' : 'Failing / Backlog Grade',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isPass ? AppColors.success.base : AppColors.danger.base,
                              ),
                            ),
                          ),
                          Switch(
                            value: isPass,
                            activeThumbColor: AppColors.success.base,
                            onChanged: (val) {
                              setDialogState(() => isPass = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  if (formKey.currentState?.validate() ?? false) {
                    final minP = double.parse(minCtrl.text.trim());
                    final maxP = double.parse(maxCtrl.text.trim());
                    final grade = gradeCtrl.text.trim();

                    final newScheme = GradingScheme(
                      id: existingScheme?.id,
                      minPercent: minP,
                      maxPercent: maxP,
                      grade: grade,
                      isPass: isPass,
                    );

                    await ref.read(gradingSchemesProvider.notifier).saveScheme(newScheme);
                    if (context.mounted) {
                      Navigator.pop(dialogCtx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Grade "$grade" saved successfully!')),
                      );
                    }
                  }
                },
                icon: const Icon(LucideIcons.check, size: 16),
                label: Text(isEditing ? 'Update Tier' : 'Add Tier'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.exams.base,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(GradingScheme scheme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Grade Tier?'),
        content: Text('Are you sure you want to delete grade "${scheme.grade}" (${scheme.minPercent}% - ${scheme.maxPercent}%)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger.base, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              if (scheme.id != null) {
                await ref.read(gradingSchemesProvider.notifier).deleteScheme(scheme.id!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Grade "${scheme.grade}" deleted.')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmResetDefaults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to Default Grading Scheme?'),
        content: const Text('This will reset your grading scale to the standard 7-tier scale (A+ to F). Any custom thresholds will be overwritten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning.base, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(gradingSchemesProvider.notifier).resetToDefaults();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Grading scheme reset to standard defaults.')),
                );
              }
            },
            child: const Text('Reset Defaults'),
          ),
        ],
      ),
    );
  }

  void _applyPreset(GradingSchemePreset preset) async {
    await ref.read(gradingSchemesProvider.notifier).applyPreset(preset);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Applied "${preset.name}" preset.')),
      );
    }
  }

  Color _getGradeColor(String grade, bool isPass) {
    if (!isPass) return AppColors.danger.base;
    final upper = grade.toUpperCase();
    if (upper.contains('A') || upper.contains('DISTINCTION')) return const Color(0xFF0D9488);
    if (upper.contains('B') || upper.contains('FIRST')) return const Color(0xFF2563EB);
    if (upper.contains('C') || upper.contains('SECOND')) return const Color(0xFFD97706);
    return const Color(0xFF475569);
  }

  @override
  Widget build(BuildContext context) {
    final schemesAsync = ref.watch(gradingSchemesProvider);

    return schemesAsync.when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
      error: (e, st) => Center(child: Text('Error loading grading schemes: $e')),
      data: (schemes) {
        final sorted = List<GradingScheme>.from(schemes)
          ..sort((a, b) => b.minPercent.compareTo(a.minPercent));

        // Evaluate test percentage
        final testEvaluation = GradingSchemeRepository.evaluate(
          percentage: _testPct,
          schemes: sorted,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Action Bar
            SectionCard(
              title: 'Grading Scheme & Percentage Thresholds',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<GradingSchemePreset>(
                    tooltip: 'Select a Preset Scheme',
                    onSelected: _applyPreset,
                    itemBuilder: (ctx) => GradingPresets.all.map((p) {
                      return PopupMenuItem<GradingSchemePreset>(
                        value: p,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(p.description, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      );
                    }).toList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.listFilter, size: 14, color: AppColors.textStrong),
                          SizedBox(width: 6),
                          Text('Presets', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          SizedBox(width: 4),
                          Icon(LucideIcons.chevronDown, size: 14, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _confirmResetDefaults,
                    icon: const Icon(LucideIcons.rotateCcw, size: 14),
                    label: const Text('Reset', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditTierDialog(),
                    icon: const Icon(LucideIcons.plus, size: 14),
                    label: const Text('Add Tier', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.exams.base,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Define the percentage range required for each grade. When marks are entered or published, students are automatically assigned grades and ranks according to these thresholds.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),

                  // Interactive Live Calculator / Tester
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.calculator, size: 20, color: AppColors.brand),
                        const SizedBox(width: 10),
                        const Text(
                          'Test Calculator:',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 80,
                          height: 34,
                          child: TextFormField(
                            controller: _testPercentageCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              suffixText: '%',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(LucideIcons.arrowRight, size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 16),
                        const Text('Resulting Grade: ', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getGradeColor(testEvaluation.grade, testEvaluation.isPass).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _getGradeColor(testEvaluation.grade, testEvaluation.isPass).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            testEvaluation.grade,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _getGradeColor(testEvaluation.grade, testEvaluation.isPass),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        StatusBadge(
                          text: testEvaluation.isPass ? 'Pass' : 'Fail',
                          status: testEvaluation.isPass ? BadgeStatus.success : BadgeStatus.danger,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Grading Tiers List
                  if (sorted.isEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('No grade tiers configured. Click "Reset" or "Add Tier" to create tiers.'),
                      ),
                    ),
                  ] else ...[
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Column(
                        children: [
                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.control)),
                              border: Border(bottom: BorderSide(color: AppColors.border)),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(width: 90, child: Text('GRADE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textMuted))),
                                SizedBox(width: 140, child: Text('RANGE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textMuted))),
                                Expanded(child: Text('DISTRIBUTION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textMuted))),
                                SizedBox(width: 90, child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textMuted))),
                                SizedBox(width: 80, child: Text('ACTIONS', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textMuted))),
                              ],
                            ),
                          ),
                          // Rows
                          ...sorted.map((s) {
                            final gradeColor = _getGradeColor(s.grade, s.isPass);
                            final span = (s.maxPercent - s.minPercent).clamp(0.0, 100.0);

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(color: AppColors.border)),
                              ),
                              child: Row(
                                children: [
                                  // Grade Badge
                                  SizedBox(
                                    width: 90,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: gradeColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: gradeColor.withValues(alpha: 0.35)),
                                        ),
                                        child: Text(
                                          s.grade,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: gradeColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Percentage range
                                  SizedBox(
                                    width: 140,
                                    child: Text(
                                      '${s.minPercent.toStringAsFixed(1)}% – ${s.maxPercent.toStringAsFixed(1)}%',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                  // Mini bar representation
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 24),
                                      child: Stack(
                                        children: [
                                          Container(
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                          Positioned(
                                            left: (s.minPercent / 100.0) * 200, // scaled visual
                                            child: Container(
                                              width: ((span / 100.0) * 200).clamp(4.0, 200.0),
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: gradeColor,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Pass/Fail status
                                  SizedBox(
                                    width: 90,
                                    child: StatusBadge(
                                      text: s.isPass ? 'Pass' : 'Fail',
                                      status: s.isPass ? BadgeStatus.success : BadgeStatus.danger,
                                    ),
                                  ),
                                  // Edit & Delete actions
                                  SizedBox(
                                    width: 80,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          icon: const Icon(LucideIcons.edit2, size: 15, color: AppColors.textMuted),
                                          tooltip: 'Edit Tier',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _showAddEditTierDialog(existingScheme: s),
                                        ),
                                        const SizedBox(width: 12),
                                        IconButton(
                                          icon: Icon(LucideIcons.trash2, size: 15, color: AppColors.danger.base),
                                          tooltip: 'Delete Tier',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _confirmDelete(s),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
