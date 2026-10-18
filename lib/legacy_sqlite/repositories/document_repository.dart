import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../database_helper.dart';
import '../../core/models/document_template.dart';
import '../../core/models/generated_document.dart';

class DocumentRepository {
  SupabaseClient get _supabase => SupabaseConfig.client;
  Future<Database> get _localDb async => await DatabaseHelper.instance.database;

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

      return (res as List).map((e) => DocumentTemplate.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final db = await _localDb;
      final maps = await db.query('document_templates', orderBy: 'name');
      return maps.map((e) => DocumentTemplate.fromMap(e)).toList();
    }
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
      return null;
    } catch (_) {
      final db = await _localDb;
      final maps = await db.query('document_templates', where: 'id = ?', whereArgs: [id]);
      if (maps.isNotEmpty) return DocumentTemplate.fromMap(maps.first);
      return null;
    }
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

      try {
        final localDb = await _localDb;
        final map = template.toMap();
        map['id'] = newId;
        await localDb.insert('document_templates', map, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}

      return newId;
    } catch (_) {
      final db = await _localDb;
      return await db.insert('document_templates', template.toMap());
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

      try {
        final localDb = await _localDb;
        await localDb.update('document_templates', template.toMap(), where: 'id = ?', whereArgs: [template.id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final db = await _localDb;
      return await db.update(
        'document_templates',
        template.toMap(),
        where: 'id = ?',
        whereArgs: [template.id],
      );
    }
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

      try {
        final localDb = await _localDb;
        await localDb.delete('document_templates', where: 'id = ?', whereArgs: [id]);
      } catch (_) {}

      return 1;
    } catch (_) {
      final db = await _localDb;
      return await db.delete('document_templates', where: 'id = ?', whereArgs: [id]);
    }
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

      return (res as List).map((e) => GeneratedDocument.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final db = await _localDb;
      final maps = await db.query(
        'generated_documents',
        where: 'student_id = ?',
        whereArgs: [studentId],
        orderBy: 'date DESC',
      );
      return maps.map((e) => GeneratedDocument.fromMap(e)).toList();
    }
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

      try {
        final localDb = await _localDb;
        final map = doc.toMap();
        map['id'] = newId;
        await localDb.insert('generated_documents', map, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}

      return newId;
    } catch (_) {
      final db = await _localDb;
      return await db.insert('generated_documents', doc.toMap());
    }
  }
}
