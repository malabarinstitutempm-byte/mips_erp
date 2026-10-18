import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../core/models/payment.dart';
import '../../core/models/receipt.dart';
import '../../core/models/student.dart';

class ReceiptPdfGenerator {
  static Future<pw.Document> buildReceiptDocument({
    required Student student,
    required Payment payment,
    required String receiptNumber,
    required Map<String, String> settings,
    String? courseName,
  }) async {
    final pdf = pw.Document();

    final institutionName = (settings['institution_name']?.trim().isNotEmpty ?? false)
        ? settings['institution_name']!
        : 'MALABAR INSTITUTE OF PARAMEDICAL SCIENCE';
    final institutionAddress = (settings['institution_address']?.trim().isNotEmpty ?? false)
        ? settings['institution_address']!
        : 'CH Centre, Malappuram, Kerala - 676519';
    final institutionPhone = (settings['institution_phone']?.trim().isNotEmpty ?? false)
        ? settings['institution_phone']!
        : '';

    // Load fonts
    pw.Font fontRegular = pw.Font.helvetica();
    pw.Font fontBold = pw.Font.helveticaBold();
    try {
      fontRegular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    } catch (_) {
      fontRegular = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
    }

    // Load logo
    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('assets/images/mips_logo.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}

    final paidAmount = payment.amountPaise > 0 ? (payment.amountPaise / 100.0) : payment.amount;
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ');
    final formattedAmount = currencyFormat.format(paidAmount);
    final dateStr = payment.date.length >= 10 ? payment.date.substring(0, 10) : payment.date;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header with Logo
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoImage != null) ...[
                    pw.Container(
                      width: 54,
                      height: 54,
                      child: pw.Image(logoImage),
                    ),
                    pw.SizedBox(width: 16),
                  ],
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          institutionName.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          institutionAddress,
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                        if (institutionPhone.isNotEmpty)
                          pw.Text(
                            'Contact: $institutionPhone',
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Container(height: 1.5, color: PdfColors.blue900),
              pw.SizedBox(height: 12),

              // Title Ribbon
              pw.Container(
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.symmetric(vertical: 6),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'FEE PAYMENT RECEIPT',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.2,
                    color: PdfColors.blue900,
                  ),
                ),
              ),
              pw.SizedBox(height: 16),

              // Receipt Meta & Student Details Card
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Student Info
                    pw.Expanded(
                      flex: 3,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Student Name', student.name, isBold: true),
                          pw.SizedBox(height: 6),
                          _buildDetailRow('Admission No', student.admissionNumber ?? 'N/A'),
                          pw.SizedBox(height: 6),
                          _buildDetailRow('Course', courseName ?? (student.courseId != null ? 'Course #${student.courseId}' : 'N/A')),
                        ],
                      ),
                    ),
                    pw.Container(width: 1, height: 60, color: PdfColors.grey300),
                    pw.SizedBox(width: 16),
                    // Receipt Info
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Receipt No', receiptNumber, isBold: true),
                          pw.SizedBox(height: 6),
                          _buildDetailRow('Date', dateStr),
                          pw.SizedBox(height: 6),
                          _buildDetailRow('Payment Mode', payment.paymentMode.toUpperCase()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Payment Table
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
                headerPadding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                cellStyle: const pw.TextStyle(fontSize: 10),
                columnWidths: const {
                  0: pw.FixedColumnWidth(40),
                  1: pw.FlexColumnWidth(3),
                  2: pw.FixedColumnWidth(120),
                },
                headerAlignments: const {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                },
                cellAlignments: const {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                },
                headers: ['SL', 'PARTICULARS / DESCRIPTION', 'AMOUNT'],
                data: [
                  [
                    '1',
                    'Tuition / Academic Fee Payment' +
                        ((payment.referenceNumber != null && payment.referenceNumber!.isNotEmpty)
                            ? '\nReference / Txn: ${payment.referenceNumber}'
                            : ''),
                    formattedAmount,
                  ],
                ],
              ),
              pw.SizedBox(height: 12),

              // Total Highlight Row
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL AMOUNT PAID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.blue900)),
                    pw.Text(formattedAmount, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: PdfColors.blue900)),
                  ],
                ),
              ),

              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(width: 150, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 6),
                      pw.Text('Student / Depositor', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(width: 150, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 6),
                      pw.Text('Authorized Signatory', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Text(
                  'This is a computer-generated fee receipt from MIPS ERP.',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  static pw.Widget _buildDetailRow(String label, String value, {bool isBold = false}) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: 90,
          child: pw.Text('$label:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(fontSize: 10, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
          ),
        ),
      ],
    );
  }

  static Future<pw.Document> buildThermalReceiptDocument({
    required Student student,
    required Payment payment,
    required String receiptNumber,
    required Map<String, String> settings,
    String? courseName,
  }) async {
    final pdf = pw.Document();

    final institutionName = (settings['institution_name']?.trim().isNotEmpty ?? false)
        ? settings['institution_name']!
        : 'MALABAR INSTITUTE OF PARAMEDICAL SCIENCE';
    final institutionAddress = (settings['institution_address']?.trim().isNotEmpty ?? false)
        ? settings['institution_address']!
        : 'CH Centre, Malappuram, Kerala - 676519';
    final institutionPhone = (settings['institution_phone']?.trim().isNotEmpty ?? false)
        ? settings['institution_phone']!
        : '';

    // Load fonts
    pw.Font fontRegular = pw.Font.helvetica();
    pw.Font fontBold = pw.Font.helveticaBold();
    try {
      fontRegular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    } catch (_) {
      fontRegular = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
    }

    final paidAmount = payment.amountPaise > 0 ? (payment.amountPaise / 100.0) : payment.amount;
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ');
    final formattedAmount = currencyFormat.format(paidAmount);
    final dateStr = payment.date.length >= 10 ? payment.date.substring(0, 10) : payment.date;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text(
                  institutionName.toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  institutionAddress,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ),
              if (institutionPhone.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Phone: $institutionPhone',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                  ),
                ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, color: PdfColors.grey600),
              pw.Center(
                child: pw.Text('PAYMENT RECEIPT', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.Divider(thickness: 1, color: PdfColors.grey600),
              pw.SizedBox(height: 4),

              _buildThermalRow('Receipt No', receiptNumber, isBold: true),
              _buildThermalRow('Date', dateStr),
              _buildThermalRow('Student', student.name, isBold: true),
              _buildThermalRow('Adm. No', student.admissionNumber ?? 'N/A'),
              if (courseName != null && courseName.isNotEmpty)
                _buildThermalRow('Course', courseName),
              _buildThermalRow('Mode', payment.paymentMode),
              if (payment.referenceNumber != null && payment.referenceNumber!.isNotEmpty)
                _buildThermalRow('Ref/Txn', payment.referenceNumber!),
              if (payment.remarks != null && payment.remarks!.isNotEmpty)
                _buildThermalRow('Remarks', payment.remarks!),

              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, color: PdfColors.grey600),
              pw.SizedBox(height: 2),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('AMOUNT PAID:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text(formattedAmount, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ],
              ),

              pw.SizedBox(height: 2),
              pw.Divider(thickness: 1, color: PdfColors.grey600),
              pw.SizedBox(height: 16),

              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(width: 100, height: 1, color: PdfColors.grey500),
                    pw.SizedBox(height: 2),
                    pw.Text('Cashier / Signatory', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'Thank you! MIPS ERP Generated.',
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  static pw.Widget _buildThermalRow(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 70,
            child: pw.Text('$label:', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800)),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: 8.5, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> printReceipt({
    required Student student,
    required Payment payment,
    required String receiptNumber,
    Map<String, String>? settings,
    String? courseName,
    bool isThermal = false,
  }) async {
    final pdf = isThermal
        ? await buildThermalReceiptDocument(
            student: student,
            payment: payment,
            receiptNumber: receiptNumber,
            settings: settings ?? {},
            courseName: courseName,
          )
        : await buildReceiptDocument(
            student: student,
            payment: payment,
            receiptNumber: receiptNumber,
            settings: settings ?? {},
            courseName: courseName,
          );

    final safeName = receiptNumber.replaceAll('/', '_');
    final formatLabel = isThermal ? 'Thermal' : 'A4';
    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Fee_Receipt_${formatLabel}_$safeName.pdf',
    );
  }

  static Future<File> generateReceipt(
    Student student,
    Payment payment,
    Receipt receipt,
    Map<String, String> settings, {
    String? courseName,
  }) async {
    final pdf = await buildReceiptDocument(
      student: student,
      payment: payment,
      receiptNumber: receipt.receiptNumber,
      settings: settings,
      courseName: courseName,
    );

    final dir = await getApplicationDocumentsDirectory();
    final safeName = receipt.receiptNumber.replaceAll('/', '_');
    final filePath = '${dir.path}\\MIPS_ERP_Database\\Receipts\\$safeName.pdf';
    final file = File(filePath);
    await file.create(recursive: true);
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
