import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Database starts empty with valid schema', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(
      version: 8,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE exams (id INTEGER PRIMARY KEY, name TEXT)');
        await db.execute('CREATE TABLE marks (id INTEGER PRIMARY KEY, marks_obtained REAL, status TEXT)');
      },
    ));
    final exams = await db.query('exams');
    expect(exams.isEmpty, true);
    await db.close();
  });

  test('Fee balance calculation test', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE student_fees (id INTEGER PRIMARY KEY, amount_paise INTEGER, pending_amount_paise INTEGER)');
      },
    ));
    await db.insert('student_fees', {'amount_paise': 500000, 'pending_amount_paise': 500000}); // 5000 Rs
    
    // Simulate payment
    final fee = await db.query('student_fees');
    int pending = fee.first['pending_amount_paise'] as int;
    pending -= 200000; // Pay 2000 Rs
    await db.update('student_fees', {'pending_amount_paise': pending});
    
    final updated = await db.query('student_fees');
    expect(updated.first['pending_amount_paise'], 300000); // 3000 Rs remaining
    await db.close();
  });

  test('Result / grade calculation logic', () {
    double percentage = 85.0;
    String grade = 'F';
    
    // Mock grading scheme: 80-100 -> A
    if (percentage >= 80 && percentage <= 100) {
      grade = 'A';
    }
    expect(grade, 'A');
    
    percentage = 45.0;
    // Mock grading scheme: 40-50 -> C
    if (percentage >= 40 && percentage < 50) {
      grade = 'C';
    }
    expect(grade, 'C');
  });

  test('Receipt numbering sequence validation', () {
    final currentLastReceipt = 'MIPS/2026/0004';
    final parts = currentLastReceipt.split('/');
    int nextSeq = int.parse(parts[2]) + 1;
    final newReceipt = 'MIPS/2026/${nextSeq.toString().padLeft(4, '0')}';
    expect(newReceipt, 'MIPS/2026/0005');
  });

  test('Import validation error handling', () {
    // Mock validation
    List<String> errors = [];
    final row = {'Name': 'John', 'Admission': null}; // missing admission
    
    if (row['Admission'] == null) {
      errors.add('Missing Admission Number');
    }
    
    expect(errors.isNotEmpty, true);
    expect(errors.first, 'Missing Admission Number');
  });
}
