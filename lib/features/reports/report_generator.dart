import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

class ReportGenerator {
  static Future<String> generateExcel(String title, List<String> headers, List<List<dynamic>> rows) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel[title];
    excel.setDefaultSheet(title);
    
    sheetObject.appendRow(headers.map((h) => TextCellValue(h)).toList());
    
    for (var r in rows) {
      sheetObject.appendRow(r.map((v) => TextCellValue(v?.toString() ?? '')).toList());
    }
    
    var fileBytes = excel.save();
    if (fileBytes == null) throw Exception('Failed to generate Excel file.');

    final sanitizedTitle = title.replaceAll(' ', '_').toLowerCase();
    final fileName = '${sanitizedTitle}_${DateTime.now().millisecondsSinceEpoch}.xlsx';

    if (kIsWeb) {
      await Printing.sharePdf(
        bytes: Uint8List.fromList(fileBytes),
        filename: fileName,
      );
      return fileName;
    }

    var dir = await getDownloadsDirectory();
    var path = '${dir?.path ?? "."}/$fileName';
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(fileBytes);
      
    return path;
  }

  static Future<String> generatePdf(String title, List<String> headers, List<List<dynamic>> rows) async {
    final pdf = pw.Document();

    pw.Font fontRegular = pw.Font.helvetica();
    pw.Font fontBold = pw.Font.helveticaBold();
    try {
      fontRegular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    } catch (_) {
      fontRegular = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        header: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
              pw.SizedBox(height: 4),
              pw.Text('Generated on: ${DateTime.now().toString().substring(0, 16)}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.SizedBox(height: 16),
            ]
          );
        },
        build: (pw.Context context) {
          return [
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows.map((row) => row.map((e) => e?.toString() ?? '').toList()).toList(),
              border: pw.TableBorder.all(color: PdfColors.grey300),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
              cellHeight: 25,
              cellAlignments: {
                for (var i = 0; i < headers.length; i++) i: pw.Alignment.centerLeft,
              },
            ),
          ];
        },
      ),
    );

    final pdfBytes = await pdf.save();
    final sanitizedTitle = title.replaceAll(' ', '_').toLowerCase();
    final fileName = '${sanitizedTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';

    if (kIsWeb) {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: fileName,
      );
      return fileName;
    }

    var dir = await getDownloadsDirectory();
    var path = '${dir?.path ?? "."}/$fileName';
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(pdfBytes);
      
    return path;
  }
}
