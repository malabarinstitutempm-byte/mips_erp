import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../../core/models/student.dart';
import '../../core/models/document_template.dart';
import '../../core/models/course.dart';
import '../../core/repositories/supabase/supabase_course_repository.dart';

class DocumentGenerator {
  static Future<String> replaceVariables(
    String content,
    Student student,
    String documentNumber, {
    String? overrideGender,
  }) async {
    final courseRepo = SupabaseCourseRepository();
    final courses = await courseRepo.getCourses();
    final course = courses.firstWhere((c) => c.id == student.courseId, orElse: () => Course(name: 'Unknown', code: ''));

    final effectiveGender = (overrideGender != null && overrideGender.isNotEmpty)
        ? overrideGender
        : (student.gender ?? 'Male');
    final isFemale = effectiveGender.trim().toLowerCase() == 'female';

    final heShe = isFemale ? 'She' : 'He';
    final heSheLower = isFemale ? 'she' : 'he';
    final hisHer = isFemale ? 'Her' : 'His';
    final hisHerLower = isFemale ? 'her' : 'his';
    final himHer = isFemale ? 'Her' : 'Him';
    final himHerLower = isFemale ? 'her' : 'him';
    final sonDaughter = isFemale ? 'Daughter' : 'Son';
    final sonDaughterLower = isFemale ? 'daughter' : 'son';
    final title = isFemale ? 'Ms.' : 'Mr.';
    final soDo = isFemale ? 'D/o' : 'S/o';
    final sonOfDaughterOf = isFemale ? 'daughter of' : 'son of';
    final SonOfDaughterOf = isFemale ? 'Daughter of' : 'Son of';

    String replaced = content;
    replaced = replaced.replaceAll('{{student_name}}', student.name);
    replaced = replaced.replaceAll('{{admission_number}}', student.admissionNumber ?? '');
    replaced = replaced.replaceAll('{{registration_number}}', student.registrationNumber ?? '');
    replaced = replaced.replaceAll('{{course}}', course.name);
    replaced = replaced.replaceAll('{{batch}}', '2026 Batch');
    replaced = replaced.replaceAll('{{document_number}}', documentNumber);
    replaced = replaced.replaceAll('{{date}}', DateTime.now().toString().substring(0, 10));
    final completionDateStr = (student.completedOn != null && student.completedOn!.isNotEmpty)
        ? student.completedOn!
        : DateTime.now().toIso8601String().substring(0, 10);
    replaced = replaced.replaceAll('{{completion_date}}', completionDateStr);

    // Pronouns & Gender Variables
    replaced = replaced.replaceAll('{{gender}}', effectiveGender);
    replaced = replaced.replaceAll('{{title}}', title);
    replaced = replaced.replaceAll('{{Title}}', title);
    replaced = replaced.replaceAll('{{mr_ms}}', title);
    replaced = replaced.replaceAll('{{Mr_Ms}}', title);
    replaced = replaced.replaceAll('{{mr/ms}}', title);
    replaced = replaced.replaceAll('{{Mr/Ms}}', title);
    replaced = replaced.replaceAll('{{Mr/Ms.}}', title);

    replaced = replaced.replaceAll('{{he_she}}', heSheLower);
    replaced = replaced.replaceAll('{{He_She}}', heShe);
    replaced = replaced.replaceAll('{{he/she}}', heSheLower);
    replaced = replaced.replaceAll('{{He/She}}', heShe);

    replaced = replaced.replaceAll('{{his_her}}', hisHerLower);
    replaced = replaced.replaceAll('{{His_Her}}', hisHer);
    replaced = replaced.replaceAll('{{his/her}}', hisHerLower);
    replaced = replaced.replaceAll('{{His/Her}}', hisHer);

    replaced = replaced.replaceAll('{{him_her}}', himHerLower);
    replaced = replaced.replaceAll('{{Him_Her}}', himHer);
    replaced = replaced.replaceAll('{{him/her}}', himHerLower);
    replaced = replaced.replaceAll('{{Him/Her}}', himHer);

    replaced = replaced.replaceAll('{{son_daughter}}', sonDaughterLower);
    replaced = replaced.replaceAll('{{Son_Daughter}}', sonDaughter);
    replaced = replaced.replaceAll('{{son/daughter}}', sonDaughterLower);
    replaced = replaced.replaceAll('{{Son/Daughter}}', sonDaughter);

    replaced = replaced.replaceAll('{{so_do}}', soDo);
    replaced = replaced.replaceAll('{{So_Do}}', soDo);
    replaced = replaced.replaceAll('{{s/o_d/o}}', soDo);
    replaced = replaced.replaceAll('{{S/o_D/o}}', soDo);
    replaced = replaced.replaceAll('{{S/O_D/O}}', soDo);

    replaced = replaced.replaceAll('{{son_of_daughter_of}}', sonOfDaughterOf);
    replaced = replaced.replaceAll('{{Son_of_Daughter_of}}', SonOfDaughterOf);
    replaced = replaced.replaceAll('{{Son_Of_Daughter_Of}}', SonOfDaughterOf);

    // Literal replacements for pre-existing or standard text patterns
    replaced = replaced.replaceAll('Mr/Ms.', title);
    replaced = replaced.replaceAll('Mr/Ms', title);
    replaced = replaced.replaceAll('Mr / Ms.', title);
    replaced = replaced.replaceAll('Mr / Ms', title);
    replaced = replaced.replaceAll('He/She', heShe);
    replaced = replaced.replaceAll('he/she', heSheLower);
    replaced = replaced.replaceAll('He / She', heShe);
    replaced = replaced.replaceAll('he / she', heSheLower);
    replaced = replaced.replaceAll('His/Her', hisHer);
    replaced = replaced.replaceAll('his/her', hisHerLower);
    replaced = replaced.replaceAll('His / Her', hisHer);
    replaced = replaced.replaceAll('his / her', hisHerLower);
    replaced = replaced.replaceAll('Him/Her', himHer);
    replaced = replaced.replaceAll('him/her', himHerLower);
    replaced = replaced.replaceAll('Son/Daughter', sonDaughter);
    replaced = replaced.replaceAll('son/daughter', sonDaughterLower);
    replaced = replaced.replaceAll('Son / Daughter', sonDaughter);
    replaced = replaced.replaceAll('son / daughter', sonDaughterLower);
    replaced = replaced.replaceAll('S/o / D/o', soDo);
    replaced = replaced.replaceAll('S/o/D/o', soDo);

    return replaced;
  }

  static Future<pw.Document> generatePdfDocument(String content, String documentNumber) async {
    final pdf = pw.Document();

    pw.Font fontRegular = pw.Font.helvetica();
    pw.Font fontBold = pw.Font.helveticaBold();
    pw.Font? fontMalayalam;
    try {
      fontRegular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
      fontMalayalam = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansMalayalam-Regular.ttf'));
    } catch (_) {
      fontRegular = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(
          base: fontRegular,
          bold: fontBold,
          fontFallback: fontMalayalam != null ? [fontMalayalam] : const [],
        ),
        build: (pw.Context context) {
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
                      pw.Text('MIPS Paramedical College', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      pw.SizedBox(height: 4),
                      pw.Text('123 Education Lane, Kerala', style: const pw.TextStyle(fontSize: 12)),
                    ],
                  ),
                  // QR Code
                  pw.Container(
                    height: 60,
                    width: 60,
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: documentNumber,
                      color: PdfColors.black,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(thickness: 2, color: PdfColors.blue900),
              pw.SizedBox(height: 16),
              
              // Ref / Date
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Ref: $documentNumber', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Date: ${DateTime.now().toString().substring(0, 10)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 40),
              
              // Body Content
              pw.Text(content, style: const pw.TextStyle(fontSize: 14, lineSpacing: 5)),
              
              pw.Spacer(),
              
              // Signature Line
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.SizedBox(height: 60),
                    pw.Text('Authorized Signatory', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    return pdf;
  }
}
