import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../database_helper.dart';
import '../../core/models/student.dart';
import '../../core/models/student_record_type.dart';
import '../../core/models/student_record.dart';
import '../../core/models/student_record_audit.dart';

class StudentRepository {
  SupabaseClient get _supabase => SupabaseConfig.client;
  Future<Database> get _localDb async => await DatabaseHelper.instance.database;

  // ===========================================================================
  // 1. Cloud Student Operations (Supabase Master Database)
  // ===========================================================================

  Future<Student?> getStudentById(int id) async {
    try {
      final res = await _supabase
          .from('students')
          .select()
          .eq('id', id)
          .isFilter('deleted_at', null)
          .maybeSingle();

      if (res != null) {
        return Student.fromMap(res);
      }
      return null;
    } catch (_) {
      // Fallback to local SQLite if offline
      final db = await _localDb;
      final maps = await db.query('students', where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
      if (maps.isNotEmpty) return Student.fromMap(maps.first);
      return null;
    }
  }

  Future<List<Student>> getStudents({String? query, int? courseId}) async {
    try {
      var builder = _supabase
          .from('students')
          .select()
          .isFilter('deleted_at', null);

      if (courseId != null) {
        builder = builder.eq('course_id', courseId);
      }

      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim();
        builder = builder.or('name.ilike.%$q%,admission_number.ilike.%$q%,registration_number.ilike.%$q%,phone.ilike.%$q%');
      }

      final res = await builder.order('admission_number', ascending: false);
      return (res as List).map((e) => Student.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      // Fallback to local SQLite if offline
      final db = await _localDb;
      String where = 'is_deleted = 0';
      List<dynamic> whereArgs = [];

      if (query != null && query.isNotEmpty) {
        where += ' AND (name LIKE ? OR admission_number LIKE ? OR registration_number LIKE ? OR phone LIKE ?)';
        whereArgs.addAll(['%$query%', '%$query%', '%$query%', '%$query%']);
      }

      if (courseId != null) {
        where += ' AND course_id = ?';
        whereArgs.add(courseId);
      }

      final maps = await db.query(
        'students',
        where: where.isEmpty ? null : where,
        whereArgs: whereArgs.isEmpty ? null : whereArgs,
        orderBy: 'admission_number DESC',
      );
      return maps.map((e) => Student.fromMap(e)).toList();
    }
  }

  Future<int> addStudent(Student student) async {
    // 1. Prepare payload for Supabase cloud insert
    final payload = <String, dynamic>{
      'name': student.name.trim(),
      'status': student.status.toLowerCase(),
      'gender': student.gender ?? 'Male',
    };

    if (student.admissionNumber != null && student.admissionNumber!.isNotEmpty) {
      payload['admission_number'] = student.admissionNumber!.trim();
    } else {
      payload['admission_number'] = await generateNextAdmissionNumber();
    }

    if (student.registrationNumber != null && student.registrationNumber!.isNotEmpty) {
      payload['registration_number'] = student.registrationNumber!.trim();
    }
    if (student.courseId != null) payload['course_id'] = student.courseId;
    if (student.batchId != null) payload['batch_id'] = student.batchId;
    if (student.universityId != null) payload['university_id'] = student.universityId;
    if (student.academicYearId != null) payload['academic_year_id'] = student.academicYearId;
    if (student.dob != null && student.dob!.isNotEmpty) payload['dob'] = student.dob;
    if (student.phone != null && student.phone!.isNotEmpty) payload['phone'] = student.phone!.trim();
    if (student.email != null && student.email!.isNotEmpty) payload['email'] = student.email!.trim();
    if (student.address != null && student.address!.isNotEmpty) payload['address'] = student.address!.trim();
    if (student.admissionDate != null && student.admissionDate!.isNotEmpty) payload['admission_date'] = student.admissionDate;
    if (student.importId != null) payload['import_id'] = student.importId;

    try {
      final inserted = await _supabase
          .from('students')
          .insert(payload)
          .select('id, course_id')
          .single();

      final newStudentId = inserted['id'] as int;

      // 2. Initialize fee ledger in Supabase based on course fee
      try {
        if (student.courseId != null) {
          final courseRes = await _supabase
              .from('courses')
              .select('total_fee_paise')
              .eq('id', student.courseId!)
              .maybeSingle();

          if (courseRes != null) {
            final totalFeePaise = (courseRes['total_fee_paise'] as num?)?.toInt() ?? 0;
            await _supabase.from('fees').insert({
              'student_id': newStudentId,
              'total_fee_paise': totalFeePaise,
              'paid_amount_paise': 0,
              'pending_amount_paise': totalFeePaise,
            });
          }
        }
      } catch (_) {}

      // Keep local SQLite copy synchronized for local photo / record relations
      try {
        final localDb = await _localDb;
        final localMap = student.toMap();
        localMap['id'] = newStudentId;
        localMap['admission_number'] = payload['admission_number'];
        await localDb.insert('students', localMap, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}

      return newStudentId;
    } catch (e) {
      // If cloud insert fails, fallback to local insertion
      final localDb = await _localDb;
      final map = student.toMap();
      map['created_at'] = DateTime.now().toIso8601String();
      final id = await localDb.insert('students', map);
      return id;
    }
  }

  Future<int> updateStudent(Student student) async {
    if (student.id == null) return 0;

    final payload = <String, dynamic>{
      'name': student.name.trim(),
      'status': student.status.toLowerCase(),
      'gender': student.gender ?? 'Male',
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (student.admissionNumber != null) payload['admission_number'] = student.admissionNumber!.trim();
    if (student.registrationNumber != null) payload['registration_number'] = student.registrationNumber!.trim();
    if (student.courseId != null) payload['course_id'] = student.courseId;
    if (student.batchId != null) payload['batch_id'] = student.batchId;
    if (student.universityId != null) payload['university_id'] = student.universityId;
    if (student.academicYearId != null) payload['academic_year_id'] = student.academicYearId;
    if (student.dob != null) payload['dob'] = student.dob;
    if (student.phone != null) payload['phone'] = student.phone!.trim();
    if (student.email != null) payload['email'] = student.email!.trim();
    if (student.address != null) payload['address'] = student.address!.trim();
    if (student.admissionDate != null) payload['admission_date'] = student.admissionDate;

    try {
      await _supabase
          .from('students')
          .update(payload)
          .eq('id', student.id!);

      // Update local SQLite cache
      try {
        final localDb = await _localDb;
        await localDb.update('students', student.toMap(), where: 'id = ?', whereArgs: [student.id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final localDb = await _localDb;
      return await localDb.update('students', student.toMap(), where: 'id = ?', whereArgs: [student.id]);
    }
  }

  Future<int> deleteStudent(int id) async {
    try {
      await _supabase
          .from('students')
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
            'deleted_by': _supabase.auth.currentUser?.id,
          })
          .eq('id', id);

      // Local soft delete
      try {
        final localDb = await _localDb;
        await localDb.update('students', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final localDb = await _localDb;
      return await localDb.update('students', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<String> generateNextAdmissionNumber() async {
    try {
      final currYear = DateTime.now().year;
      final res = await _supabase.rpc('next_number', params: {
        'p_kind': 'admission',
        'p_year': currYear,
      });

      if (res != null && res.toString().isNotEmpty) {
        return res.toString();
      }
    } catch (_) {}

    // Fallback: local counter
    final prefix = 'ADM';
    final year = DateTime.now().year.toString();
    final db = await _localDb;
    final maps = await db.query(
      'students',
      columns: ['admission_number'],
      where: 'admission_number LIKE ?',
      whereArgs: ['$prefix-$year-%'],
      orderBy: 'admission_number DESC',
      limit: 1,
    );

    int nextSequence = 1;
    if (maps.isNotEmpty) {
      final lastNum = maps.first['admission_number'] as String;
      final parts = lastNum.split('-');
      if (parts.length >= 3) {
        final lastSeq = int.tryParse(parts.last) ?? 0;
        nextSequence = lastSeq + 1;
      }
    }
    return '$prefix-$year-${nextSequence.toString().padLeft(4, '0')}';
  }

  Future<bool> isAdmissionNumberUnique(String admissionNumber, {int? excludeStudentId}) async {
    final clean = admissionNumber.trim();
    if (clean.isEmpty) return false;

    try {
      var builder = _supabase
          .from('students')
          .select('id')
          .ilike('admission_number', clean)
          .isFilter('deleted_at', null);

      if (excludeStudentId != null) {
        builder = builder.neq('id', excludeStudentId);
      }

      final res = await builder.maybeSingle();
      return res == null;
    } catch (_) {
      final db = await _localDb;
      final List<Map<String, dynamic>> maps;
      if (excludeStudentId != null) {
        maps = await db.query(
          'students',
          columns: ['id'],
          where: 'LOWER(admission_number) = LOWER(?) AND is_deleted = 0 AND id != ?',
          whereArgs: [clean, excludeStudentId],
          limit: 1,
        );
      } else {
        maps = await db.query(
          'students',
          columns: ['id'],
          where: 'LOWER(admission_number) = LOWER(?) AND is_deleted = 0',
          whereArgs: [clean],
          limit: 1,
        );
      }
      return maps.isEmpty;
    }
  }

  // ===========================================================================
  // 2. Desktop Local Student Records & Scanned Documents
  // (Preserved strictly on desktop SQLite; never uploaded to cloud)
  // ===========================================================================

  Future<int> addRecordType(StudentRecordType type) async {
    if (kIsWeb) return 0;
    try {
      final db = await _localDb;
      return await db.insert('student_record_types', type.toMap());
    } catch (_) {
      return 0;
    }
  }

  Future<int> updateRecordType(StudentRecordType type) async {
    if (kIsWeb) return 0;
    try {
      final db = await _localDb;
      return await db.update('student_record_types', type.toMap(), where: 'id = ?', whereArgs: [type.id]);
    } catch (_) {
      return 0;
    }
  }

  Future<List<StudentRecordType>> getRecordTypes() async {
    if (kIsWeb) return [];
    try {
      final db = await _localDb;
      final maps = await db.query('student_record_types', orderBy: 'sort_order ASC');
      return maps.map((e) => StudentRecordType.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<StudentRecord>> getStudentRecords(int studentId) async {
    if (kIsWeb) return [];
    try {
      final db = await _localDb;
      final maps = await db.query(
        'student_records',
        where: 'student_id = ? AND status != "deleted"',
        whereArgs: [studentId],
        orderBy: 'uploaded_at DESC',
      );
      return maps.map((e) => StudentRecord.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addStudentRecord(StudentRecord record, String actionDetails) async {
    if (kIsWeb) return;
    try {
      final db = await _localDb;
      await db.transaction((txn) async {
        final maps = await txn.query('student_record_types', where: 'id = ?', whereArgs: [record.recordTypeId]);
        if (maps.isNotEmpty) {
          final type = StudentRecordType.fromMap(maps.first);
          if (!type.allowMultiple) {
            await txn.update(
              'student_records',
              {'status': 'archived', 'replaced_by_id': record.id},
              where: 'student_id = ? AND record_type_id = ? AND status = "current"',
              whereArgs: [record.studentId, record.recordTypeId],
            );
          }
        }

        await txn.insert('student_records', record.toMap());

        await txn.insert('student_record_audit', StudentRecordAudit(
          studentId: record.studentId,
          recordId: record.id,
          action: 'upload',
          performedAt: DateTime.now().toIso8601String(),
          details: actionDetails,
        ).toMap());
      });
    } catch (_) {}
  }

  Future<void> deleteStudentRecord(String recordId, int studentId) async {
    if (kIsWeb) return;
    try {
      final db = await _localDb;
      await db.transaction((txn) async {
        await txn.update(
          'student_records',
          {'status': 'deleted'},
          where: 'id = ?',
          whereArgs: [recordId],
        );
        await txn.insert('student_record_audit', StudentRecordAudit(
          studentId: studentId,
          recordId: recordId,
          action: 'delete',
          performedAt: DateTime.now().toIso8601String(),
        ).toMap());
      });
    } catch (_) {}
  }
}
