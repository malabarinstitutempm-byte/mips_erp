// lib/features/timetable/timetable_pdf_generator.dart

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/models/timetable.dart';

class TimetablePdfGenerator {
  static const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  static Future<void> exportAndPrint({
    required Timetable timetable,
    required List<TimetableEntry> entries,
    String? batchName,
    String? courseName,
  }) async {
    final pdf = pw.Document();

    final fontRegular = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'MALABAR INSTITUTE OF PARAMEDICAL SCIENCE',
                        style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.blue900),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Weekly Class Schedule: ${timetable.title}',
                        style: pw.TextStyle(font: fontBold, fontSize: 13),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Batch: ${batchName ?? timetable.batchName ?? "N/A"}  |  Course: ${courseName ?? timetable.courseName ?? "N/A"}  |  Effective From: ${timetable.effectiveFrom}',
                        style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: timetable.isPublished ? PdfColors.green100 : PdfColors.amber100,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      timetable.status.toUpperCase(),
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 10,
                        color: timetable.isPublished ? PdfColors.green900 : PdfColors.amber900,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 12),

              // Weekly Grid Table
              pw.Expanded(
                child: pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(80), // Day
                    1: const pw.FlexColumnWidth(1),   // Morning Block
                    2: const pw.FlexColumnWidth(1),   // Evening Block
                  },
                  children: [
                    // Header Row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _buildCell('Day', fontBold, isHeader: true),
                        _buildCell('Morning Slot (09:00 - 13:00)', fontBold, isHeader: true),
                        _buildCell('Evening Slot (13:30 - 17:00)', fontBold, isHeader: true),
                      ],
                    ),
                    // Weekday Rows
                    ...List.generate(6, (dayIndex) {
                      final dayNum = dayIndex + 1;
                      final dayName = weekdays[dayIndex];

                      final morningEntries = entries.where((e) => e.weekday == dayNum && e.slot == 'morning').toList();
                      final eveningEntries = entries.where((e) => e.weekday == dayNum && e.slot == 'evening').toList();

                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(dayName, style: pw.TextStyle(font: fontBold, fontSize: 10)),
                          ),
                          _buildSlotCell(morningEntries, fontRegular, fontBold),
                          _buildSlotCell(eveningEntries, fontRegular, fontBold),
                        ],
                      );
                    }),
                  ],
                ),
              ),

              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Generated by MIPS ERP on ${DateTime.now().toString().split(' ')[0]}', style: pw.TextStyle(font: fontRegular, fontSize: 8, color: PdfColors.grey600)),
                  pw.Text('Authorized College Signature', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Timetable_${timetable.title.replaceAll(' ', '_')}.pdf',
    );
  }

  static pw.Widget _buildCell(String text, pw.Font font, {bool isHeader = false}) {
    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: isHeader ? 10 : 9, color: isHeader ? PdfColors.black : PdfColors.grey900),
      ),
    );
  }

  static pw.Widget _buildSlotCell(List<TimetableEntry> slotEntries, pw.Font fontRegular, pw.Font fontBold) {
    if (slotEntries.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text('No class', style: pw.TextStyle(font: fontRegular, fontSize: 8, color: PdfColors.grey500)),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: slotEntries.map((e) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 3),
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(3),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(e.subjectName ?? 'Subject', style: pw.TextStyle(font: fontBold, fontSize: 8)),
                      pw.Text(e.teacherName ?? 'Teacher', style: pw.TextStyle(font: fontRegular, fontSize: 7, color: PdfColors.grey700)),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('${e.startTime.substring(0, 5)} - ${e.endTime.substring(0, 5)}', style: pw.TextStyle(font: fontRegular, fontSize: 7, color: PdfColors.blue800)),
                    if (e.room != null && e.room!.isNotEmpty)
                      pw.Text(e.room!, style: pw.TextStyle(font: fontRegular, fontSize: 6, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
