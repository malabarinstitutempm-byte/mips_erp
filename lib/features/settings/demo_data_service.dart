import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/database/database_helper.dart';

class DemoDataService {
  static Future<void> seedDatabase() async {
    final db = await DatabaseHelper.instance.database;

    await db.transaction((txn) async {
      // 1. Settings
      await txn.insert('settings', {'key': 'institution_name', 'value': 'Malabar Institute of Paramedical Science'}, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('settings', {'key': 'institution_address', 'value': 'CH Centre, Malappuram, Kerala - 676519'}, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('settings', {'key': 'receipt_prefix', 'value': 'REC-'}, conflictAlgorithm: ConflictAlgorithm.replace);

      // 2. University
      final uniId = await txn.insert('universities', {'name': 'BSS / Kerala University of Health Sciences'});

      // 3. Courses
      final course1 = await txn.insert('courses', {'university_id': uniId, 'name': 'Diploma in Medical Laboratory Technology (DMLT)', 'code': 'DMLT', 'duration': '2 Years', 'total_fee': 45000.0});
      final course2 = await txn.insert('courses', {'university_id': uniId, 'name': 'Diploma in X-Ray Technology', 'code': 'DXT', 'duration': '2 Years', 'total_fee': 40000.0});

      // 4. Academic Year
      final ayId = await txn.insert('academic_years', {'year_name': '2026-2027', 'is_current': 1});

      // 5. Batches
      final batch1 = await txn.insert('batches', {'course_id': course1, 'batch_name': 'DMLT Batch A', 'start_date': '2026-06-01', 'end_date': '2027-05-31'});
      final batch2 = await txn.insert('batches', {'course_id': course2, 'batch_name': 'DXT Batch A', 'start_date': '2026-06-01', 'end_date': '2027-05-31'});

      // 6. Students
      final students = [
        {'name': 'Mohammed Shafi', 'phone': '9876543210', 'course': course1, 'batch': batch1},
        {'name': 'Fathima Sana', 'phone': '9876543211', 'course': course1, 'batch': batch1},
        {'name': 'Rahul Krishna', 'phone': '9876543212', 'course': course1, 'batch': batch1},
        {'name': 'Aisha Nida', 'phone': '9876543213', 'course': course2, 'batch': batch2},
        {'name': 'Vishnu Prasad', 'phone': '9876543214', 'course': course2, 'batch': batch2},
      ];

      int admCount = 1;
      for (var s in students) {
        final stId = await txn.insert('students', {
          'course_id': s['course'],
          'batch_id': s['batch'],
          'university_id': uniId,
          'academic_year_id': ayId,
          'admission_number': 'ADM-2026-${admCount.toString().padLeft(4, '0')}',
          'name': s['name'],
          'dob': '2005-05-15',
          'phone': s['phone'],
          'address': 'Malappuram, Kerala',
          'admission_date': '2026-06-05',
          'status': 'Active'
        });

        // 7. Fees
        await txn.insert('fees', {
          'student_id': stId,
          'total_fee': s['course'] == course1 ? 45000.0 : 40000.0,
          'paid_amount': 10000.0,
          'pending_amount': s['course'] == course1 ? 35000.0 : 30000.0,
        });

        // Add a mock payment
        await txn.insert('payments', {
          'student_id': stId,
          'amount': 10000.0,
          'date': '2026-06-10',
          'payment_mode': 'Cash',
          'reference_number': 'CASH-1',
          'remarks': 'First Installment'
        });

        admCount++;
      }
      
      // 8. Add Document Template
      await txn.insert('document_templates', {
        'name': 'Bonafide Certificate',
        'content': 'This is to certify that {{he_she}} {{student_name}} (Adm No: {{admission_number}}) is a bonafide student of {{course}}.',
      });
    });
  }
}
