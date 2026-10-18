import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/kpi_card.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/search_field.dart';

import 'result_provider.dart';

class ResultsScreen extends ConsumerWidget {
  final int examId;
  final String examName;
  const ResultsScreen({super.key, required this.examId, required this.examName});

  Future<void> _printMasterSheet(BuildContext context, List<Map<String, dynamic>> results) async {
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No results available to print for this exam. Please enter marks first.')),
      );
      return;
    }

    try {
      final doc = pw.Document();

      // Resolve fonts safely using offline assets
      pw.Font fontRegular = pw.Font.helvetica();
      pw.Font fontBold = pw.Font.helveticaBold();
      try {
        fontRegular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
        fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
      } catch (_) {
        fontRegular = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
      }

      final passedCount = results.where((r) => r['status'] == 'Pass').length;
      final failedCount = results.where((r) => r['status'] == 'Fail').length;
      final evaluatedCount = passedCount + failedCount;
      final passPercentage = evaluatedCount > 0 ? (passedCount / evaluatedCount) * 100 : 0.0;

      // Load logo
      pw.MemoryImage? logoImage;
      try {
        final logoBytes = await rootBundle.load('assets/images/mips_logo.png');
        logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
      } catch (_) {}

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
          header: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logoImage != null) ...[
                      pw.Container(
                        width: 42,
                        height: 42,
                        child: pw.Image(logoImage),
                      ),
                      pw.SizedBox(width: 12),
                    ],
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'MALABAR INSTITUTE OF PARAMEDICAL SCIENCE',
                            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'CH Centre, Malappuram, Kerala - 676519',
                            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'EXAMINATION RESULT SHEET',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Date: ${DateTime.now().toString().substring(0, 10)}',
                          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Container(height: 1.5, color: PdfColors.blue900),
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          'EXAM: $examName',
                          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                        ),
                      ),
                      pw.Text(
                        'TOTAL STUDENTS: ${results.length}',
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
              ],
            );
          },
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
              ),
            );
          },
          build: (pw.Context context) {
            return [
              pw.TableHelper.fromTextArray(
                headers: const ['RANK', 'ADM NO', 'STUDENT NAME', 'TOTAL MARKS', 'PERCENTAGE', 'GRADE', 'STATUS'],
                data: results.map((r) => [
                  r['rank']?.toString() ?? '-',
                  r['admission_number']?.toString() ?? 'N/A',
                  r['student_name']?.toString() ?? 'Unknown',
                  r['total_marks'] != null ? (r['total_marks'] as num).toStringAsFixed(1) : '0.0',
                  r['percentage'] != null ? '${(r['percentage'] as num).toStringAsFixed(1)}%' : '0.0%',
                  r['grade']?.toString() ?? '-',
                  r['status']?.toString() ?? 'Pending',
                ]).toList(),
                border: pw.TableBorder.all(color: PdfColors.grey300),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8.5),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
                headerPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                columnWidths: const {
                  0: pw.FixedColumnWidth(34),
                  1: pw.FixedColumnWidth(92),
                  2: pw.FlexColumnWidth(2.5),
                  3: pw.FixedColumnWidth(68),
                  4: pw.FixedColumnWidth(62),
                  5: pw.FixedColumnWidth(44),
                  6: pw.FixedColumnWidth(55),
                },
                headerAlignments: const {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.center,
                  6: pw.Alignment.center,
                },
                cellAlignments: const {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.center,
                  6: pw.Alignment.center,
                },
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Candidates: ${results.length}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                    pw.Text('Passed: $passedCount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.green800)),
                    pw.Text('Failed: $failedCount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.red800)),
                    pw.Text('Pass %: ${passPercentage.toStringAsFixed(1)}%', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.blue900)),
                  ],
                ),
              ),
              pw.SizedBox(height: 32),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(width: 100, height: 1, color: PdfColors.black),
                        pw.SizedBox(height: 4),
                        pw.Text('Prepared By', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(width: 100, height: 1, color: PdfColors.black),
                        pw.SizedBox(height: 4),
                        pw.Text('Verified By', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(width: 140, height: 1, color: PdfColors.black),
                        pw.SizedBox(height: 4),
                        pw.Text('Principal / Controller of Exams', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                      ],
                    ),
                  ),
                ],
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => doc.save(),
        name: 'MIPS_Master_Sheet_${examName.replaceAll(" ", "_")}.pdf',
        format: PdfPageFormat.a4,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error printing master sheet: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(examResultsProvider(examId));
    final resultsList = resultsAsync.valueOrNull ?? [];
    final isLoading = resultsAsync.isLoading;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(examName, style: const TextStyle(fontSize: 16)),
        backgroundColor: AppColors.surface,
        centerTitle: false,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        actions: [
          ElevatedButton.icon(
            onPressed: isLoading ? null : () => _printMasterSheet(context, resultsList),
            icon: const Icon(LucideIcons.printer, size: 16),
            label: Text(isLoading ? 'Loading...' : 'Print Master Sheet'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.exams.base,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xl),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(LucideIcons.arrowLeft, size: 16),
              label: const Text('Back to Exams'),
            ),
          ),
        ],
      ),
      body: resultsAsync.when(
        data: (results) {
          final total = results.length;
          final passed = results.where((r) => r['status'] == 'Pass').length;
          final failed = total - passed;
          final passPct = total > 0 ? (passed / total) * 100 : 0.0;
          
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: KpiCard(title: 'Passed', value: passed.toString(), icon: LucideIcons.checkCircle, baseColor: AppColors.success.base, tintColor: AppColors.success.tint)),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: KpiCard(title: 'Failed', value: failed.toString(), icon: LucideIcons.alertCircle, baseColor: AppColors.danger.base, tintColor: AppColors.danger.tint)),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: KpiCard(title: 'Pass Rate', value: '${passPct.toStringAsFixed(1)}%', icon: LucideIcons.trendingUp, baseColor: AppColors.info.base, tintColor: AppColors.info.tint)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                
                Expanded(
                  child: SectionCard(
                    title: 'Student Results Board',
                    padding: EdgeInsets.zero,
                    trailing: SizedBox(
                      width: 300,
                      child: SearchField(hint: 'Search by Name / Rank / Adm No...'),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border)), color: AppColors.bg),
                          child: Row(
                            children: const [
                              Expanded(flex: 1, child: Text('RANK', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted))),
                              Expanded(flex: 3, child: Text('STUDENT', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted))),
                              Expanded(flex: 2, child: Text('TOTAL MARKS', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted))),
                              Expanded(flex: 1, child: Text('PERCENTAGE', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted))),
                              Expanded(flex: 1, child: Text('GRADE', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted))),
                              Expanded(flex: 1, child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted))),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final r = results[index];
                              final isPass = r['status'] == 'Pass';
                              
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 1, 
                                      child: Text(
                                        r['rank']?.toString() ?? '-', 
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong)
                                      )
                                    ),
                                    Expanded(
                                      flex: 3, 
                                      child: Row(
                                        children: [
                                          AppAvatar(name: r['student_name'] ?? 'Unknown', radius: 14),
                                          const SizedBox(width: AppSpacing.md),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(r['student_name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textStrong)),
                                                Text(r['admission_number'] ?? 'N/A', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    ),
                                    Expanded(flex: 2, child: Text('${r['total_marks']?.toStringAsFixed(1) ?? '0'}')),
                                    Expanded(flex: 1, child: Text('${r['percentage']?.toStringAsFixed(1) ?? '0.0'}%')),
                                    Expanded(flex: 1, child: Text(r['grade'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))),
                                    Expanded(
                                      flex: 1, 
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: StatusBadge(
                                          text: r['status'] ?? 'Pending', 
                                          status: isPass ? BadgeStatus.success : (r['status'] == 'Fail' ? BadgeStatus.danger : BadgeStatus.warning)
                                        ),
                                      )
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
