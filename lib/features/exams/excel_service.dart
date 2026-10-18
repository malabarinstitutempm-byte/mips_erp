import 'dart:io';
import 'package:excel/excel.dart';
import '../../core/models/student.dart';
import '../../core/models/subject.dart';
import '../../core/models/mark.dart';
import '../../core/models/exam.dart';

class ExcelService {
  
  /// Generates an Excel template with Student ADM NO, Name, and columns for each subject
  static Future<void> generateTemplate(String filePath, Exam exam, List<Subject> subjects, List<Student> students) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Marks Template'];
    
    // Header Row
    List<CellValue> headers = [
      TextCellValue('Admission Number'),
      TextCellValue('Student Name'),
    ];
    
    // Add subjects as headers
    for (var sub in subjects) {
      headers.add(TextCellValue('${sub.name} (Max: ${sub.maxMarks})'));
    }
    
    sheetObject.appendRow(headers);
    
    // Add student rows
    for (var student in students) {
      List<CellValue> row = [
        TextCellValue(student.admissionNumber ?? ''),
        TextCellValue(student.name),
      ];
      // Empty cells for marks
      for (int i = 0; i < subjects.length; i++) {
        row.add(TextCellValue(''));
      }
      sheetObject.appendRow(row);
    }
    
    // Delete default sheet
    if (excel.getDefaultSheet() != 'Marks Template') {
      excel.delete('Sheet1');
    }

    final fileBytes = excel.save();
    if (fileBytes != null) {
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes);
    }
  }

  /// Parses the uploaded Excel template and returns a list of Mark objects
  static Future<List<Mark>> parseMarksTemplate(String filePath, Exam exam, List<Subject> subjects, List<Student> students) async {
    var bytes = File(filePath).readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);
    
    List<Mark> parsedMarks = [];
    
    // Assume we're using the first sheet
    final sheet = excel.tables.values.first;
    
    // Start from row 1 (index 1) to skip headers
    for (int rowIndex = 1; rowIndex < sheet.maxRows; rowIndex++) {
      final row = sheet.row(rowIndex);
      if (row.isEmpty || row[0] == null) continue;
      
      final admNo = row[0]?.value.toString() ?? '';
      if (admNo.isEmpty) continue;
      
      // Find matching student
      final student = students.where((s) => s.admissionNumber == admNo).firstOrNull;
      if (student == null) continue; // Skip if student not found
      
      // Process marks
      for (int i = 0; i < subjects.length; i++) {
        final colIndex = 2 + i; // Subject marks start at column 2 (0-indexed)
        if (colIndex >= row.length) break;
        
        final cellValue = row[colIndex]?.value;
        if (cellValue != null) {
          final markStr = cellValue.toString();
          if (markStr.isNotEmpty) {
            final doubleMark = double.tryParse(markStr);
            if (doubleMark != null) {
              final subject = subjects[i];
              
              // Validate max marks
              if (doubleMark <= subject.maxMarks) {
                 parsedMarks.add(Mark(
                   examId: exam.id!,
                   subjectId: subject.id!,
                   studentId: student.id!,
                   marksObtained: doubleMark,
                   status: doubleMark >= subject.passMarks ? 'Pass' : 'Fail',
                 ));
              }
            }
          }
        }
      }
    }
    
    return parsedMarks;
  }
}
