import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/services/supabase_service.dart';
import '../../core/repositories/supabase/supabase_student_repository.dart';

class ExcelImportService {
  static Future<String> generateTemplate() async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Students'];
    excel.setDefaultSheet('Students');
    
    List<String> headers = ['Name', 'Admission Number', 'Registration Number', 'DOB (YYYY-MM-DD)', 'Gender', 'Phone', 'Email', 'Address', 'Course', 'Batch'];
    sheetObject.appendRow(headers.map((h) => TextCellValue(h)).toList());
    
    var fileBytes = excel.save();
    var dir = await getDownloadsDirectory();
    var path = '${dir!.path}/mips_student_import_template.xlsx';
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(fileBytes!);
      
    return path;
  }

  static Future<List<Map<String, dynamic>>> previewImport(String filePath) async {
    var bytes = File(filePath).readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);
    var sheet = excel.tables.keys.first;
    var rows = excel.tables[sheet]!.rows;

    if (rows.length <= 1) throw Exception('Excel file is empty or only contains headers.');

    final client = SupabaseService.instance.client;

    // Fetch existing courses, batches, and student identifiers from Supabase
    final coursesData = await client
        .from('courses')
        .select('id, name, code')
        .isFilter('deleted_at', null);
    final coursesMap = <String, int>{};
    for (var c in coursesData) {
      if (c['name'] != null) coursesMap[c['name'].toString().trim().toLowerCase()] = (c['id'] as num).toInt();
      if (c['code'] != null) coursesMap[c['code'].toString().trim().toLowerCase()] = (c['id'] as num).toInt();
    }

    final batchesData = await client
        .from('batches')
        .select('id, batch_name, course_id')
        .isFilter('deleted_at', null);
    final batchesMap = <String, int>{};
    for (var b in batchesData) {
      final name = (b['batch_name'] ?? '').toString().trim().toLowerCase();
      final courseId = b['course_id'];
      if (name.isNotEmpty) {
        batchesMap['${courseId}_$name'] = (b['id'] as num).toInt();
        batchesMap[name] = (b['id'] as num).toInt();
      }
    }

    final studentsData = await client
        .from('students')
        .select('admission_number, registration_number')
        .isFilter('deleted_at', null);
    final existAdmissions = <String>{};
    final existReg = <String>{};
    for (var s in studentsData) {
      if (s['admission_number'] != null && s['admission_number'].toString().isNotEmpty) {
        existAdmissions.add(s['admission_number'].toString().trim().toLowerCase());
      }
      if (s['registration_number'] != null && s['registration_number'].toString().isNotEmpty) {
        existReg.add(s['registration_number'].toString().trim().toLowerCase());
      }
    }

    List<Map<String, dynamic>> previewRows = [];

    // Skip header row 0
    for (int i = 1; i < rows.length; i++) {
      var row = rows[i];
      if (row.isEmpty || row[0]?.value == null) continue;

      String name = row[0]?.value.toString().trim() ?? '';
      String admissionNo = row.length > 1 ? (row[1]?.value.toString().trim() ?? '') : '';
      String regNo = row.length > 2 ? (row[2]?.value.toString().trim() ?? '') : '';
      String dob = row.length > 3 ? (row[3]?.value.toString().trim() ?? '') : '';
      String gender = row.length > 4 ? (row[4]?.value.toString().trim() ?? '') : '';
      String phone = row.length > 5 ? (row[5]?.value.toString().trim() ?? '') : '';
      String email = row.length > 6 ? (row[6]?.value.toString().trim() ?? '') : '';
      String address = row.length > 7 ? (row[7]?.value.toString().trim() ?? '') : '';
      String courseName = row.length > 8 ? (row[8]?.value.toString().trim() ?? '') : '';
      String batchName = row.length > 9 ? (row[9]?.value.toString().trim() ?? '') : '';

      List<String> errors = [];

      if (name.isEmpty) errors.add('Name is required');
      if (courseName.isEmpty) errors.add('Course is required');
      if (batchName.isEmpty) errors.add('Batch is required');

      if (admissionNo.isNotEmpty && existAdmissions.contains(admissionNo.toLowerCase())) {
        errors.add('Admission number already exists');
      }
      if (regNo.isNotEmpty && existReg.contains(regNo.toLowerCase())) {
        errors.add('Registration number already exists');
      }

      int? courseId = coursesMap[courseName.toLowerCase()];
      if (courseId == null && courseName.isNotEmpty) {
        errors.add('Course "$courseName" not found');
      }

      int? batchId;
      if (courseId != null) {
        batchId = batchesMap['${courseId}_${batchName.toLowerCase()}'] ?? batchesMap[batchName.toLowerCase()];
      } else {
        batchId = batchesMap[batchName.toLowerCase()];
      }

      if (batchId == null && batchName.isNotEmpty) {
        errors.add('Batch "$batchName" not found');
      }

      // Gender normalization
      if (gender.isNotEmpty) {
        final gLower = gender.toLowerCase();
        if (gLower.startsWith('f')) {
          gender = 'Female';
        } else if (gLower.startsWith('o')) {
          gender = 'Other';
        } else {
          gender = 'Male';
        }
      } else {
        gender = 'Male';
      }

      previewRows.add({
        'row': i + 1,
        'name': name,
        'admission_number': admissionNo,
        'registration_number': regNo,
        'dob': dob,
        'gender': gender,
        'phone': phone,
        'email': email,
        'address': address,
        'course': courseName,
        'batch': batchName,
        'course_id': courseId,
        'batch_id': batchId,
        'is_valid': errors.isEmpty,
        'errors': errors,
      });
    }

    return previewRows;
  }

  static Future<Map<String, dynamic>> executeImport(
    List<Map<String, dynamic>> validRows, {
    String? importBatchId,
  }) async {
    final payload = validRows.where((r) => r['is_valid'] == true).map((r) => {
      'name': r['name'],
      'admission_number': (r['admission_number'] ?? '').toString().trim().isEmpty ? null : r['admission_number'],
      'registration_number': (r['registration_number'] ?? '').toString().trim().isEmpty ? null : r['registration_number'],
      'dob': (r['dob'] ?? '').toString().trim().isEmpty ? null : r['dob'],
      'gender': r['gender'],
      'phone': (r['phone'] ?? '').toString().trim().isEmpty ? null : r['phone'],
      'email': (r['email'] ?? '').toString().trim().isEmpty ? null : r['email'],
      'address': (r['address'] ?? '').toString().trim().isEmpty ? null : r['address'],
      'course_id': r['course_id'],
      'batch_id': r['batch_id'],
    }).toList();

    final repo = SupabaseStudentRepository();
    return await repo.importStudents(payload, importBatchId: importBatchId);
  }

  static Future<String> downloadErrorReport(List<Map<String, dynamic>> allRows) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Errors'];
    excel.setDefaultSheet('Errors');
    
    List<String> headers = ['Row', 'Status', 'Errors', 'Name', 'Admission Number', 'Registration Number', 'Course', 'Batch'];
    sheetObject.appendRow(headers.map((h) => TextCellValue(h)).toList());
    
    for (var r in allRows) {
      sheetObject.appendRow([
        TextCellValue(r['row'].toString()),
        TextCellValue(r['is_valid'] ? 'Valid' : 'Invalid'),
        TextCellValue((r['errors'] as List).join('; ')),
        TextCellValue(r['name']),
        TextCellValue(r['admission_number']),
        TextCellValue(r['registration_number']),
        TextCellValue(r['course']),
        TextCellValue(r['batch']),
      ]);
    }
    
    var fileBytes = excel.save();
    var dir = await getDownloadsDirectory();
    var path = '${dir!.path}/mips_import_error_report_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(fileBytes!);
      
    return path;
  }

  static Future<Map<String, dynamic>> undoImport(String importBatchId) async {
    final repo = SupabaseStudentRepository();
    return await repo.undoImport(importBatchId);
  }
}
