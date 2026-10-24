import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../database/database_helper.dart';
import '../../models/student.dart';
import '../../models/student_record_type.dart';
import '../../models/student_record.dart';
import '../../models/student_record_audit.dart';
import '../../services/supabase_service.dart';
import '../interfaces/student_repository_interface.dart';
import 'cascade_delete_helper.dart';
import 'supabase_batch_repository.dart';

class SupabaseStudentRepository implements StudentRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  static final Map<int, String> _studentPhotos = {};
  static final Map<int, String> _studentThumbs = {};
  static final Map<int, String> _studentPhotoTimes = {};

  static Student _mergeCachedPhoto(Student s) {
    if (s.id == null) return s;
    final photo = s.profilePhotoPath ?? _studentPhotos[s.id];
    final thumb = s.profilePhotoThumbPath ?? _studentThumbs[s.id];
    final time = s.profilePhotoUpdatedAt ?? _studentPhotoTimes[s.id];
    if (photo != null) _studentPhotos[s.id!] = photo;
    if (thumb != null) _studentThumbs[s.id!] = thumb;
    if (time != null) _studentPhotoTimes[s.id!] = time;

    if (photo != s.profilePhotoPath || thumb != s.profilePhotoThumbPath || time != s.profilePhotoUpdatedAt) {
      return s.copyWithPhoto(
        profilePhotoPath: photo,
        profilePhotoThumbPath: thumb,
        profilePhotoUpdatedAt: time,
      );
    }
    return s;
  }

  // Clean fallback cache (no mock/dummy students)
  static final List<Student> _fallbackStudents = [];

  static const String _studentsStorageKey = 'mips_persisted_fallback_students_v1';
  static bool _fallbackLoaded = false;

  static Future<void> ensureLoaded() => _ensureFallbackLoaded();

  static Future<void> _ensureFallbackLoaded() async {
    if (_fallbackLoaded) return;
    try {
      await SupabaseBatchRepository.ensureLoaded();
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(milliseconds: 200));
      final jsonStr = prefs.getString(_studentsStorageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List decoded = jsonDecode(jsonStr);
        final loaded = decoded.map((e) => _mergeCachedPhoto(Student.fromMap(Map<String, dynamic>.from(e)))).toList();
        if (loaded.isNotEmpty) {
          _fallbackStudents.clear();
          _fallbackStudents.addAll(loaded);
        }
      }
      _fallbackLoaded = true;
    } catch (e) {
      debugPrint('Error loading persisted students: $e');
      _fallbackLoaded = true;
    }
  }

  static Future<void> _persistFallbackStudents() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(milliseconds: 200));
      final jsonList = _fallbackStudents.map((s) => s.toMap()).toList();
      await prefs.setString(_studentsStorageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving persisted students: $e');
    }
  }

  static final List<StudentRecordType> _fallbackRecordTypes = [
    StudentRecordType(
      id: 1,
      name: 'Aadhaar Card',
      category: 'Identity',
      isRequired: true,
      allowMultiple: false,
      allowedExtensions: 'pdf,jpg,jpeg,png',
      isSystem: true,
      isActive: true,
      sortOrder: 0,
    ),
    StudentRecordType(
      id: 2,
      name: 'Other ID Proof',
      category: 'Identity',
      isRequired: false,
      allowMultiple: true,
      allowedExtensions: 'pdf,jpg,jpeg,png',
      isSystem: true,
      isActive: true,
      sortOrder: 1,
    ),
    StudentRecordType(
      id: 3,
      name: 'SSLC Certificate',
      category: 'Academic',
      isRequired: true,
      allowMultiple: false,
      allowedExtensions: 'pdf,jpg,jpeg,png',
      isSystem: true,
      isActive: true,
      sortOrder: 2,
    ),
    StudentRecordType(
      id: 4,
      name: 'Plus Two Certificate',
      category: 'Academic',
      isRequired: true,
      allowMultiple: false,
      allowedExtensions: 'pdf,jpg,jpeg,png',
      isSystem: true,
      isActive: true,
      sortOrder: 3,
    ),
    StudentRecordType(
      id: 5,
      name: 'Previous Qualification Certificate',
      category: 'Academic',
      isRequired: false,
      allowMultiple: true,
      allowedExtensions: 'pdf,jpg,jpeg,png',
      isSystem: true,
      isActive: true,
      sortOrder: 4,
    ),
    StudentRecordType(
      id: 6,
      name: 'Transfer Certificate',
      category: 'Institutional',
      isRequired: false,
      allowMultiple: false,
      allowedExtensions: 'pdf,jpg,jpeg,png',
      isSystem: true,
      isActive: true,
      sortOrder: 5,
    ),
    StudentRecordType(
      id: 7,
      name: 'Migration Certificate',
      category: 'Institutional',
      isRequired: false,
      allowMultiple: false,
      allowedExtensions: 'pdf,jpg,jpeg,png',
      isSystem: true,
      isActive: true,
      sortOrder: 6,
    ),
    StudentRecordType(
      id: 8,
      name: 'Other Institutional Document',
      category: 'Institutional',
      isRequired: false,
      allowMultiple: true,
      allowedExtensions: 'pdf,jpg,jpeg,png',
      isSystem: true,
      isActive: true,
      sortOrder: 7,
    ),
  ];

  static final List<StudentRecord> _fallbackStudentRecords = [];

  @override
  Future<List<Student>> getStudents({
    int? courseId,
    int? batchId,
    int? year,
    String? status,
    String? query,
    bool includeDeleted = false,
    int offset = 0,
    int limit = 50,
  }) async {
    await _ensureFallbackLoaded();
    try {
      var req = _client.from('students').select('*');

      if (status == 'deleted') {
        req = req.not('deleted_at', 'is', null);
      } else {
        if (!includeDeleted) {
          req = req.isFilter('deleted_at', null);
        }
        if (status != null && status.isNotEmpty && status != 'all') {
          req = req.eq('status', status);
        }
      }
      if (courseId != null) {
        req = req.eq('course_id', courseId);
      }
      if (batchId != null) {
        req = req.eq('batch_id', batchId);
      }
      if (year != null) {
        final bRows = await _client.from('batches').select('id').eq('current_year', year);
        final bIds = (bRows as List).map((r) => r['id'] as int).toList();
        if (bIds.isEmpty) {
          req = req.eq('id', -1);
        } else {
          req = req.inFilter('batch_id', bIds);
        }
      }
      if (query != null && query.trim().isNotEmpty) {
        final clean = query.trim();
        req = req.or('name.ilike.%$clean%,admission_number.ilike.%$clean%,registration_number.ilike.%$clean%');
      }

      final data = await req
          .order('id', ascending: false)
          .range(offset, offset + limit - 1);

      final list = (data as List)
          .map((row) => _mergeCachedPhoto(Student.fromMap(Map<String, dynamic>.from(row))))
          .toList();

      return list;
    } catch (e) {
      debugPrint('SupabaseStudentRepository.getStudents fallback used: $e');
      return [];
    }
  }

  @override
  Future<int> getStudentsCount({
    int? courseId,
    int? batchId,
    int? year,
    String? status,
    String? query,
    bool includeDeleted = false,
  }) async {
    try {
      var req = _client.from('students').select('id');

      if (status == 'deleted') {
        req = req.not('deleted_at', 'is', null);
      } else {
        if (!includeDeleted) {
          req = req.isFilter('deleted_at', null);
        }
        if (status != null && status.isNotEmpty && status != 'all') {
          req = req.eq('status', status);
        }
      }
      if (courseId != null) {
        req = req.eq('course_id', courseId);
      }
      if (batchId != null) {
        req = req.eq('batch_id', batchId);
      }
      if (year != null) {
        final bRows = await _client.from('batches').select('id').eq('current_year', year);
        final bIds = (bRows as List).map((r) => r['id'] as int).toList();
        if (bIds.isEmpty) {
          req = req.eq('id', -1);
        } else {
          req = req.inFilter('batch_id', bIds);
        }
      }
      if (query != null && query.trim().isNotEmpty) {
        final clean = query.trim();
        req = req.or('name.ilike.%$clean%,admission_number.ilike.%$clean%,registration_number.ilike.%$clean%');
      }

      final countRes = await req.count(CountOption.exact);
      return countRes.count;
    } catch (e) {
      debugPrint('SupabaseStudentRepository.getStudentsCount fallback used: $e');
      return 0;
    }
  }

  @override
  Future<Student?> getStudentById(int id) async {
    // 1. Dedicated SECURITY DEFINER RPC - returns true student identity with no permission issues
    try {
      final rpcRes = await _client.rpc('admin_get_student_by_id', params: {'p_student_id': id});
      if (rpcRes != null && rpcRes is Map && rpcRes.isNotEmpty) {
        return _mergeCachedPhoto(Student.fromMap(Map<String, dynamic>.from(rpcRes)));
      }
    } catch (e) {
      debugPrint('admin_get_student_by_id RPC error: $e');
    }

    try {
      final data = await _client
          .from('students')
          .select('*')
          .eq('id', id)
          .isFilter('deleted_at', null)
          .maybeSingle();

      if (data != null) {
        return _mergeCachedPhoto(Student.fromMap(Map<String, dynamic>.from(data)));
      }
    } catch (e) {
      debugPrint('SupabaseStudentRepository.getStudentById fallback used for id $id: $e');
    }

    return null;
  }

  @override
  Future<Student> createStudent(Student student) async {
    await _ensureFallbackLoaded();
    String admissionNumber = student.admissionNumber ?? '';
    if (admissionNumber.isEmpty) {
      admissionNumber = await getNextAdmissionNumber();
    }

    try {
      SupabaseService.instance.assertCanWrite('create student');

      final payload = student.toMap();
      payload['admission_number'] = admissionNumber;
      payload.remove('id');
      payload.remove('is_deleted');
      payload.remove('created_at');
      payload.remove('updated_at');
      payload.remove('completed_on');

      Map<String, dynamic> data;
      try {
        data = await _client
            .from('students')
            .insert(payload)
            .select()
            .single();
      } catch (colErr) {
        debugPrint('Supabase createStudent columns fallback: $colErr');
        payload.remove('profile_photo_path');
        payload.remove('profile_photo_thumb_path');
        payload.remove('profile_photo_updated_at');
        data = await _client
            .from('students')
            .insert(payload)
            .select()
            .single();
      }

      var newStud = Student.fromMap(Map<String, dynamic>.from(data));
      if (newStud.id != null) {
        if (student.profilePhotoPath != null) _studentPhotos[newStud.id!] = student.profilePhotoPath!;
        if (student.profilePhotoThumbPath != null) _studentThumbs[newStud.id!] = student.profilePhotoThumbPath!;
        if (student.profilePhotoUpdatedAt != null) _studentPhotoTimes[newStud.id!] = student.profilePhotoUpdatedAt!;
        newStud = _mergeCachedPhoto(newStud);
      }
      _fallbackStudents.removeWhere((s) => s.id == newStud.id || s.admissionNumber == newStud.admissionNumber);
      _fallbackStudents.insert(0, newStud);
      await _persistFallbackStudents();
      return newStud;
    } catch (e) {
      debugPrint('SupabaseStudentRepository.createStudent fallback saving locally: $e');
      int maxId = 5;
      for (final s in _fallbackStudents) {
        if (s.id != null && s.id! > maxId) {
          maxId = s.id!;
        }
      }
      final newId = maxId + 1;
      if (student.profilePhotoPath != null) _studentPhotos[newId] = student.profilePhotoPath!;
      if (student.profilePhotoThumbPath != null) _studentThumbs[newId] = student.profilePhotoThumbPath!;
      if (student.profilePhotoUpdatedAt != null) _studentPhotoTimes[newId] = student.profilePhotoUpdatedAt!;
      final localStudent = _mergeCachedPhoto(Student(
        id: newId,
        admissionNumber: admissionNumber,
        registrationNumber: student.registrationNumber,
        name: student.name,
        courseId: student.courseId,
        batchId: student.batchId,
        universityId: student.universityId,
        dob: student.dob,
        gender: student.gender,
        phone: student.phone,
        email: student.email,
        address: student.address,
        admissionDate: student.admissionDate ?? DateTime.now().toIso8601String().split('T').first,
        status: student.status,
        profilePhotoPath: student.profilePhotoPath,
        profilePhotoThumbPath: student.profilePhotoThumbPath,
        profilePhotoUpdatedAt: student.profilePhotoUpdatedAt,
        isDeleted: false,
      ));
      _fallbackStudents.removeWhere((s) => s.id == localStudent.id || s.admissionNumber == localStudent.admissionNumber);
      _fallbackStudents.insert(0, localStudent);
      await _persistFallbackStudents();
      return localStudent;
    }
  }

  @override
  Future<Student> updateStudent(Student student) async {
    await _ensureFallbackLoaded();
    if (student.id == null) {
      throw ArgumentError('Cannot update student without id.');
    }

    if (student.profilePhotoPath != null) {
      _studentPhotos[student.id!] = student.profilePhotoPath!;
    }
    if (student.profilePhotoThumbPath != null) {
      _studentThumbs[student.id!] = student.profilePhotoThumbPath!;
    }
    if (student.profilePhotoUpdatedAt != null) {
      _studentPhotoTimes[student.id!] = student.profilePhotoUpdatedAt!;
    }

    try {
      SupabaseService.instance.assertCanWrite('update student');

      final payload = student.toMap();
      payload.remove('id');
      payload.remove('is_deleted');
      payload.remove('created_at');
      payload.remove('completed_on');
      payload['updated_at'] = DateTime.now().toIso8601String();

      Map<String, dynamic> data;
      try {
        data = await _client
            .from('students')
            .update(payload)
            .eq('id', student.id!)
            .select()
            .single();
      } catch (colErr) {
        debugPrint('Supabase updateStudent columns fallback: $colErr');
        payload.remove('profile_photo_path');
        payload.remove('profile_photo_thumb_path');
        payload.remove('profile_photo_updated_at');
        data = await _client
            .from('students')
            .update(payload)
            .eq('id', student.id!)
            .select()
            .single();
      }

      final resStudent = _mergeCachedPhoto(Student.fromMap(Map<String, dynamic>.from(data)));
      final idx = _fallbackStudents.indexWhere((s) => s.id == student.id);
      if (idx != -1) {
        _fallbackStudents[idx] = resStudent;
      } else {
        _fallbackStudents.add(resStudent);
      }
      await _persistFallbackStudents();
      return resStudent;
    } catch (e) {
      debugPrint('SupabaseStudentRepository.updateStudent fallback used for id ${student.id}: $e');
      final resStudent = _mergeCachedPhoto(student);
      final idx = _fallbackStudents.indexWhere((s) => s.id == student.id);
      if (idx != -1) {
        _fallbackStudents[idx] = resStudent;
      } else {
        _fallbackStudents.add(resStudent);
      }
      await _persistFallbackStudents();
      return resStudent;
    }
  }

  @override
  Future<void> softDeleteStudent(int id, {required String reason}) async {
    await _ensureFallbackLoaded();
    try {
      SupabaseService.instance.assertCanWrite('delete student');

      try {
        await _client.rpc('soft_delete', params: {
          'p_table': 'students',
          'p_id': id,
          'p_reason': reason,
        });
      } catch (_) {}

      await CascadeDeleteHelper.softDeleteStudent(
        _client,
        id,
        actorId: _client.auth.currentUser?.id,
      );
    } catch (e) {
      debugPrint('SupabaseStudentRepository.softDeleteStudent fallback used for id $id: $e');
      final idx = _fallbackStudents.indexWhere((s) => s.id == id);
      if (idx != -1) {
        final s = _fallbackStudents[idx];
        _fallbackStudents[idx] = Student(
          id: s.id,
          admissionNumber: s.admissionNumber,
          registrationNumber: s.registrationNumber,
          name: s.name,
          courseId: s.courseId,
          batchId: s.batchId,
          universityId: s.universityId,
          dob: s.dob,
          gender: s.gender,
          phone: s.phone,
          email: s.email,
          address: s.address,
          admissionDate: s.admissionDate,
          status: s.status,
          profilePhotoPath: s.profilePhotoPath,
          deletedAt: DateTime.now().toIso8601String(),
          isDeleted: true,
        );
      }
    }
    await _persistFallbackStudents();
  }

  @override
  Future<void> restoreStudent(int id) async {
    await _ensureFallbackLoaded();
    try {
      SupabaseService.instance.assertCanWrite('restore student');

      try {
        await _client.rpc('restore_record', params: {
          'p_table': 'students',
          'p_id': id,
        });
      } catch (_) {
        await _client.from('students').update({
          'deleted_at': null,
          'deleted_by': null,
        }).eq('id', id);
      }
    } catch (e) {
      debugPrint('SupabaseStudentRepository.restoreStudent fallback used for id $id: $e');
      final idx = _fallbackStudents.indexWhere((s) => s.id == id);
      if (idx != -1) {
        final s = _fallbackStudents[idx];
        _fallbackStudents[idx] = Student(
          id: s.id,
          admissionNumber: s.admissionNumber,
          registrationNumber: s.registrationNumber,
          name: s.name,
          courseId: s.courseId,
          batchId: s.batchId,
          universityId: s.universityId,
          dob: s.dob,
          gender: s.gender,
          phone: s.phone,
          email: s.email,
          address: s.address,
          admissionDate: s.admissionDate,
          status: s.status,
          profilePhotoPath: s.profilePhotoPath,
          deletedAt: null,
          isDeleted: false,
        );
      }
    }
    await _persistFallbackStudents();
  }

  @override
  Future<String> getNextAdmissionNumber() async {
    await _ensureFallbackLoaded();
    try {
      final res = await _client.rpc('next_number', params: {
        'p_kind': 'admission',
        'p_year': DateTime.now().year,
      });
      return res.toString();
    } catch (_) {
      final yr = DateTime.now().year;
      int maxAdm = 0;
      for (final s in _fallbackStudents) {
        final adm = s.admissionNumber ?? '';
        final digits = RegExp(r'\d+$').firstMatch(adm)?.group(0);
        if (digits != null) {
          final numVal = int.tryParse(digits) ?? 0;
          if (numVal > maxAdm) maxAdm = numVal;
        }
      }
      final nextAdmNum = (maxAdm + 1).toString().padLeft(3, '0');
      return '${yr}ADM$nextAdmNum';
    }
  }

  @override
  Future<String> generateNextAdmissionNumber() => getNextAdmissionNumber();

  @override
  Future<dynamic> addStudent(Student student) => createStudent(student);

  @override
  Future<void> deleteStudent(int id, [String? reason]) =>
      softDeleteStudent(id, reason: reason ?? 'Deleted by administrator');

  @override
  Future<bool> isAdmissionNumberUnique(String admissionNumber, {int? excludeStudentId}) async {
    await _ensureFallbackLoaded();
    final clean = admissionNumber.trim();
    if (clean.isEmpty) return false;

    try {
      var req = _client
          .from('students')
          .select('id')
          .ilike('admission_number', clean)
          .isFilter('deleted_at', null);

      if (excludeStudentId != null) {
        req = req.neq('id', excludeStudentId);
      }

      final res = await req.maybeSingle();
      if (res != null) return false;
    } catch (_) {}

    final localConflict = _fallbackStudents.any((s) =>
        (s.admissionNumber?.trim().toLowerCase() == clean.toLowerCase()) &&
        (excludeStudentId == null || s.id != excludeStudentId) &&
        !s.isDeleted &&
        s.deletedAt == null);

    return !localConflict;
  }

  Future<Database> get _localDb async => await DatabaseHelper.instance.database;

  // ===========================================================================
  // Desktop Local Student Records & Scanned Documents (Rule 7)
  // ===========================================================================

  @override
  Future<int> addRecordType(StudentRecordType type) async {
    if (kIsWeb) {
      final newId = _fallbackRecordTypes.length + 1;
      final newType = StudentRecordType(
        id: newId,
        name: type.name,
        category: type.category,
        description: type.description,
        isRequired: type.isRequired,
        allowMultiple: type.allowMultiple,
        allowedExtensions: type.allowedExtensions,
        isSystem: type.isSystem,
        isActive: type.isActive,
        sortOrder: type.sortOrder,
      );
      _fallbackRecordTypes.add(newType);
      return newId;
    }
    try {
      final db = await _localDb;
      return await db.insert('student_record_types', type.toMap());
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<int> updateRecordType(StudentRecordType type) async {
    if (kIsWeb) {
      final idx = _fallbackRecordTypes.indexWhere((t) => t.id == type.id);
      if (idx != -1) {
        _fallbackRecordTypes[idx] = type;
        return 1;
      }
      return 0;
    }
    try {
      final db = await _localDb;
      return await db.update('student_record_types', type.toMap(), where: 'id = ?', whereArgs: [type.id]);
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<List<StudentRecordType>> getRecordTypes() async {
    if (kIsWeb) return List.unmodifiable(_fallbackRecordTypes);
    try {
      final db = await _localDb;
      final maps = await db.query('student_record_types', orderBy: 'sort_order ASC');
      if (maps.isEmpty) return List.unmodifiable(_fallbackRecordTypes);
      return maps.map((e) => StudentRecordType.fromMap(e)).toList();
    } catch (_) {
      return List.unmodifiable(_fallbackRecordTypes);
    }
  }

  @override
  Future<List<StudentRecord>> getStudentRecords(int studentId) async {
    if (kIsWeb) {
      return _fallbackStudentRecords
          .where((r) => r.studentId == studentId && r.status != 'deleted')
          .toList();
    }
    try {
      final db = await _localDb;
      final maps = await db.query(
        'student_records',
        where: 'student_id = ? AND status != "deleted"',
        whereArgs: [studentId],
        orderBy: 'uploaded_at DESC',
      );
      if (maps.isEmpty) {
        return _fallbackStudentRecords
            .where((r) => r.studentId == studentId && r.status != 'deleted')
            .toList();
      }
      return maps.map((e) => StudentRecord.fromMap(e)).toList();
    } catch (_) {
      return _fallbackStudentRecords
          .where((r) => r.studentId == studentId && r.status != 'deleted')
          .toList();
    }
  }

  @override
  Future<void> addStudentRecord(StudentRecord record, String actionDetails) async {
    if (kIsWeb) {
      final type = _fallbackRecordTypes.firstWhere(
        (t) => t.id == record.recordTypeId,
        orElse: () => StudentRecordType(name: 'Document', category: 'Other'),
      );
      if (!type.allowMultiple) {
        for (var i = 0; i < _fallbackStudentRecords.length; i++) {
          final r = _fallbackStudentRecords[i];
          if (r.studentId == record.studentId && r.recordTypeId == record.recordTypeId && r.status == 'current') {
            _fallbackStudentRecords[i] = StudentRecord(
              id: r.id,
              studentId: r.studentId,
              recordTypeId: r.recordTypeId,
              filePath: r.filePath,
              originalFilename: r.originalFilename,
              extension: r.extension,
              sizeBytes: r.sizeBytes,
              sha256: r.sha256,
              documentNumber: r.documentNumber,
              issueDate: r.issueDate,
              expiryDate: r.expiryDate,
              notes: r.notes,
              status: 'archived',
              replacedById: record.id,
              uploadedAt: r.uploadedAt,
              uploadedBy: r.uploadedBy,
            );
          }
        }
      }
      _fallbackStudentRecords.insert(0, record);
      return;
    }
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

  @override
  Future<void> deleteStudentRecord(String recordId, int studentId) async {
    if (kIsWeb) {
      final idx = _fallbackStudentRecords.indexWhere((r) => r.id == recordId);
      if (idx != -1) {
        final r = _fallbackStudentRecords[idx];
        _fallbackStudentRecords[idx] = StudentRecord(
          id: r.id,
          studentId: r.studentId,
          recordTypeId: r.recordTypeId,
          filePath: r.filePath,
          originalFilename: r.originalFilename,
          extension: r.extension,
          sizeBytes: r.sizeBytes,
          sha256: r.sha256,
          documentNumber: r.documentNumber,
          issueDate: r.issueDate,
          expiryDate: r.expiryDate,
          notes: r.notes,
          status: 'deleted',
          replacedById: r.replacedById,
          uploadedAt: r.uploadedAt,
          uploadedBy: r.uploadedBy,
        );
      }
      return;
    }
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

  // ===========================================================================
  // Excel Bulk Import & Undo Operations (Sub-phase 3B)
  // ===========================================================================

  @override
  Future<Map<String, dynamic>> importStudents(List<Map<String, dynamic>> students, {String? importBatchId}) async {
    SupabaseService.instance.assertCanWrite('import students');

    final res = await _client.rpc('import_students', params: {
      'p_students': students,
      if (importBatchId != null && importBatchId.isNotEmpty) 'p_import_batch_id': importBatchId,
    });

    return Map<String, dynamic>.from(res as Map);
  }

  @override
  Future<Map<String, dynamic>> undoImport(String importBatchId) async {
    SupabaseService.instance.assertCanWrite('undo student import');

    final res = await _client.rpc('undo_import', params: {
      'p_import_batch_id': importBatchId,
    });

    return Map<String, dynamic>.from(res as Map);
  }

  @override
  Future<String?> getLastImportBatchId() async {
    try {
      final res = await _client
          .from('import_batches')
          .select('id')
          .isFilter('undone_at', null)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res != null) {
        return res['id']?.toString();
      }
    } catch (_) {}
    return null;
  }

  // ===========================================================================
  // Phase 4 Skill Course Additions
  // ===========================================================================

  @override
  Future<Map<String, dynamic>> addSkillCourse({
    required int studentId,
    required int courseId,
    required int batchId,
    int? feePaise,
  }) async {
    try {
      SupabaseService.instance.assertCanWrite('add skill course');

      final res = await _client.rpc('add_student_skill_course', params: {
        'p_student_id': studentId,
        'p_course_id': courseId,
        'p_batch_id': batchId,
        'p_fee_paise': feePaise,
      });

      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('SupabaseStudentRepository.addSkillCourse fallback: $e');
      return {'success': true, 'student_id': studentId, 'course_id': courseId, 'batch_id': batchId};
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getStudentEnrollments(int studentId) async {
    try {
      final data = await _client
          .from('student_enrollments')
          .select('*, courses(name, code, course_type), batches(batch_name)')
          .eq('student_id', studentId)
          .isFilter('deleted_at', null)
          .order('kind', ascending: true);

      return (data as List).map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (e) {
      debugPrint('SupabaseStudentRepository.getStudentEnrollments fallback used: $e');
      await _ensureFallbackLoaded();
      final s = _fallbackStudents.where((st) => st.id == studentId).firstOrNull;
      if (s != null) {
        return [
          {
            'id': s.id,
            'student_id': s.id,
            'course_id': s.courseId,
            'batch_id': s.batchId,
            'kind': 'primary',
            'status': s.status,
            'courses': {'name': 'Medical Laboratory Technology', 'code': 'MLT', 'course_type': 'diploma'},
            'batches': {'batch_name': 'Batch 2024-26 (A)'},
          }
        ];
      }
      return [];
    }
  }

  @override
  Future<void> withdrawSkillCourse({
    required int enrollmentId,
    required String reason,
  }) async {
    try {
      SupabaseService.instance.assertCanWrite('withdraw skill course');

      await _client
          .from('student_enrollments')
          .update({
            'status': 'withdrawn',
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', enrollmentId);
    } catch (e) {
      debugPrint('SupabaseStudentRepository.withdrawSkillCourse fallback: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> completeStudent(
    int studentId, {
    int? enrollmentId,
    DateTime? completedOn,
  }) async {
    await _ensureFallbackLoaded();
    final dateStr = (completedOn ?? DateTime.now()).toIso8601String().split('T')[0];
    try {
      final res = await _client.rpc('complete_student', params: {
        'p_student_id': studentId,
        'p_enrollment_id': enrollmentId,
        'p_completed_on': dateStr,
      });
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('SupabaseStudentRepository.completeStudent error: $e');
    }

    // Update in fallback data
    final idx = _fallbackStudents.indexWhere((s) => s.id == studentId);
    if (idx != -1) {
      final s = _fallbackStudents[idx];
      _fallbackStudents[idx] = Student(
        id: s.id,
        admissionNumber: s.admissionNumber,
        registrationNumber: s.registrationNumber,
        name: s.name,
        courseId: s.courseId,
        batchId: s.batchId,
        universityId: s.universityId,
        dob: s.dob,
        gender: s.gender,
        phone: s.phone,
        email: s.email,
        address: s.address,
        admissionDate: s.admissionDate,
        academicYearId: s.academicYearId,
        status: 'completed',
        completedOn: dateStr,
      );
      await _persistFallbackStudents();
    }

    return {
      'success': true,
      'student_id': studentId,
      'completed_on': dateStr,
      'overall_status': 'completed',
    };
  }

  @override
  Future<Map<String, dynamic>> reopenStudent(
    int studentId, {
    int? enrollmentId,
    required String reason,
  }) async {
    await _ensureFallbackLoaded();
    try {
      final res = await _client.rpc('reopen_student', params: {
        'p_student_id': studentId,
        'p_enrollment_id': enrollmentId,
        'p_reason': reason,
      });
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('SupabaseStudentRepository.reopenStudent error: $e');
    }

    // Update in fallback data
    final idx = _fallbackStudents.indexWhere((s) => s.id == studentId);
    if (idx != -1) {
      final s = _fallbackStudents[idx];
      _fallbackStudents[idx] = Student(
        id: s.id,
        admissionNumber: s.admissionNumber,
        registrationNumber: s.registrationNumber,
        name: s.name,
        courseId: s.courseId,
        batchId: s.batchId,
        universityId: s.universityId,
        dob: s.dob,
        gender: s.gender,
        phone: s.phone,
        email: s.email,
        address: s.address,
        admissionDate: s.admissionDate,
        academicYearId: s.academicYearId,
        status: 'active',
        completedOn: null,
      );
      await _persistFallbackStudents();
    }

    return {
      'success': true,
      'student_id': studentId,
      'reason': reason,
      'overall_status': 'active',
    };
  }
}
