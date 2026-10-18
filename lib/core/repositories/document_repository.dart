import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../database/database_helper.dart';
import '../../core/models/document_template.dart';
import '../../core/models/generated_document.dart';

class DocumentRepository {
  SupabaseClient get _supabase => SupabaseConfig.client;

  static final List<DocumentTemplate> _fallbackTemplates = [
    DocumentTemplate(
      id: 1,
      name: 'Bonafide Certificate',
      content: 'This is to certify that Mr/Ms. {{student_name}} (Adm No: {{admission_number}}) is a bonafide student of {{university}} during the academic session 2024-2026 pursuing {{course}} (Batch: {{batch}}). This certificate is issued upon the student\'s request for educational purposes.',
    ),
    DocumentTemplate(
      id: 2,
      name: 'Fee Certificate',
      content: 'This is to certify that Mr/Ms. {{student_name}}, admitted under {{course}} (Batch: {{batch}}), has cleared all prescribed tuition fees for the current term. Admission Number: {{admission_number}}.',
    ),
    DocumentTemplate(
      id: 3,
      name: 'Transfer Certificate',
      content: 'Transfer Certificate for Mr/Ms. {{student_name}}, Admission Number: {{admission_number}}. The student has successfully completed the coursework in {{course}} with satisfactory conduct.',
    ),
    DocumentTemplate(
      id: 4,
      name: 'Study Certificate',
      content: 'This is to certify that Mr/Ms. {{student_name}}, is a regular full-time student of this institution actively studying in {{course}} (Batch: {{batch}}).',
    ),
    DocumentTemplate(
      id: 5,
      name: 'Conduct Certificate',
      content: 'This is to certify that Mr/Ms. {{student_name}} (Adm No: {{admission_number}}) has borne exemplary moral character and disciplined conduct during {{his_her}} tenure at this institution.',
    ),
  ];

  static final List<GeneratedDocument> _fallbackGeneratedDocs = [];

  // ===========================================================================
  // Templates
  // ===========================================================================

  Future<List<DocumentTemplate>> getTemplates() async {
    try {
      final res = await _supabase
          .from('document_templates')
          .select()
          .isFilter('deleted_at', null)
          .order('name');

      final list = (res as List).map((e) => DocumentTemplate.fromMap(e as Map<String, dynamic>)).toList();
      if (list.isNotEmpty) return list;
    } catch (_) {
      if (!kIsWeb) {
        try {
          final db = await DatabaseHelper.instance.database;
          final maps = await db.query('document_templates', orderBy: 'name');
          if (maps.isNotEmpty) {
            return maps.map((e) => DocumentTemplate.fromMap(e)).toList();
          }
        } catch (_) {}
      }
    }

    return List.from(_fallbackTemplates);
  }

  Future<DocumentTemplate?> getTemplateById(int id) async {
    try {
      final res = await _supabase
          .from('document_templates')
          .select()
          .eq('id', id)
          .isFilter('deleted_at', null)
          .maybeSingle();

      if (res != null) {
        return DocumentTemplate.fromMap(res);
      }
    } catch (_) {
      if (!kIsWeb) {
        try {
          final db = await DatabaseHelper.instance.database;
          final maps = await db.query('document_templates', where: 'id = ?', whereArgs: [id]);
          if (maps.isNotEmpty) return DocumentTemplate.fromMap(maps.first);
        } catch (_) {}
      }
    }

    final match = _fallbackTemplates.where((t) => t.id == id).toList();
    return match.isNotEmpty ? match.first : null;
  }

  Future<int> addTemplate(DocumentTemplate template) async {
    final payload = {
      'name': template.name.trim(),
      'content': template.content,
    };

    try {
      final res = await _supabase
          .from('document_templates')
          .insert(payload)
          .select('id')
          .single();

      final newId = res['id'] as int;

      if (!kIsWeb) {
        try {
          final localDb = await DatabaseHelper.instance.database;
          final map = template.toMap();
          map['id'] = newId;
          await localDb.insert('document_templates', map, conflictAlgorithm: ConflictAlgorithm.replace);
        } catch (_) {}
      }

      final created = DocumentTemplate(id: newId, name: template.name, content: template.content);
      _fallbackTemplates.add(created);
      return newId;
    } catch (_) {
      final newId = DateTime.now().millisecondsSinceEpoch % 100000;
      final created = DocumentTemplate(id: newId, name: template.name, content: template.content);
      _fallbackTemplates.add(created);

      if (!kIsWeb) {
        try {
          final db = await DatabaseHelper.instance.database;
          return await db.insert('document_templates', template.toMap());
        } catch (_) {}
      }
      return newId;
    }
  }

  Future<int> updateTemplate(DocumentTemplate template) async {
    if (template.id == null) return 0;

    final payload = {
      'name': template.name.trim(),
      'content': template.content,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await _supabase
          .from('document_templates')
          .update(payload)
          .eq('id', template.id!);

      if (!kIsWeb) {
        try {
          final localDb = await DatabaseHelper.instance.database;
          await localDb.update('document_templates', template.toMap(), where: 'id = ?', whereArgs: [template.id]);
        } catch (_) {}
      }
    } catch (_) {
      if (!kIsWeb) {
        try {
          final db = await DatabaseHelper.instance.database;
          await db.update(
            'document_templates',
            template.toMap(),
            where: 'id = ?',
            whereArgs: [template.id],
          );
        } catch (_) {}
      }
    }

    final idx = _fallbackTemplates.indexWhere((t) => t.id == template.id);
    if (idx != -1) {
      _fallbackTemplates[idx] = template;
    }

    return 1;
  }

  Future<int> deleteTemplate(int id) async {
    try {
      await _supabase
          .from('document_templates')
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
            'deleted_by': _supabase.auth.currentUser?.id,
          })
          .eq('id', id);

      if (!kIsWeb) {
        try {
          final localDb = await DatabaseHelper.instance.database;
          await localDb.delete('document_templates', where: 'id = ?', whereArgs: [id]);
        } catch (_) {}
      }
    } catch (_) {
      if (!kIsWeb) {
        try {
          final db = await DatabaseHelper.instance.database;
          await db.delete('document_templates', where: 'id = ?', whereArgs: [id]);
        } catch (_) {}
      }
    }

    _fallbackTemplates.removeWhere((t) => t.id == id);
    return 1;
  }

  // ===========================================================================
  // Generated Documents
  // ===========================================================================

  Future<List<GeneratedDocument>> getGeneratedDocumentsByStudent(int studentId) async {
    try {
      final res = await _supabase
          .from('generated_documents')
          .select()
          .eq('student_id', studentId)
          .isFilter('deleted_at', null)
          .order('date', ascending: false);

      final list = (res as List).map((e) => GeneratedDocument.fromMap(e as Map<String, dynamic>)).toList();
      if (list.isNotEmpty) return list;
    } catch (_) {
      if (!kIsWeb) {
        try {
          final db = await DatabaseHelper.instance.database;
          final maps = await db.query(
            'generated_documents',
            where: 'student_id = ?',
            whereArgs: [studentId],
            orderBy: 'date DESC',
          );
          if (maps.isNotEmpty) {
            return maps.map((e) => GeneratedDocument.fromMap(e)).toList();
          }
        } catch (_) {}
      }
    }

    return _fallbackGeneratedDocs.where((d) => d.studentId == studentId).toList();
  }

  Future<int> addGeneratedDocument(GeneratedDocument doc) async {
    final payload = <String, dynamic>{
      'student_id': doc.studentId,
      'template_id': doc.templateId,
      'date': doc.date,
      'document_number': doc.documentNumber ?? 'DOC-${DateTime.now().millisecondsSinceEpoch}',
    };

    try {
      final res = await _supabase
          .from('generated_documents')
          .insert(payload)
          .select('id')
          .single();

      final newId = res['id'] as int;

      if (!kIsWeb) {
        try {
          final localDb = await DatabaseHelper.instance.database;
          final map = doc.toMap();
          map['id'] = newId;
          await localDb.insert('generated_documents', map, conflictAlgorithm: ConflictAlgorithm.replace);
        } catch (_) {}
      }

      _fallbackGeneratedDocs.insert(0, doc);
      return newId;
    } catch (_) {
      final newId = DateTime.now().millisecondsSinceEpoch % 100000;
      _fallbackGeneratedDocs.insert(0, doc);

      if (!kIsWeb) {
        try {
          final db = await DatabaseHelper.instance.database;
          return await db.insert('generated_documents', doc.toMap());
        } catch (_) {}
      }
      return newId;
    }
  }
}
