import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/database/database_helper.dart';

class SupabaseSyncService {
  final _storage = const FlutterSecureStorage();

  Future<void> saveCredentials(String url, String serviceKey) async {
    final cleanUrl = formatSupabaseUrl(url);
    final cleanKey = serviceKey.trim();
    try {
      await _storage.write(key: 'supabase_url', value: cleanUrl);
      await _storage.write(key: 'supabase_service_key', value: cleanKey);
    } catch (_) {}

    try {
      final db = await DatabaseHelper.instance.database;
      await db.insert('settings', {'key': 'supabase_url', 'value': cleanUrl}, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('settings', {'key': 'supabase_service_key', 'value': cleanKey}, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
  }

  Future<Map<String, String?>> getCredentials() async {
    String? url;
    String? key;
    try {
      url = await _storage.read(key: 'supabase_url');
      key = await _storage.read(key: 'supabase_service_key');
    } catch (_) {}

    if ((url == null || url.trim().isEmpty) || (key == null || key.trim().isEmpty)) {
      try {
        final db = await DatabaseHelper.instance.database;
        final res = await db.query(
          'settings',
          where: "key IN ('supabase_url', 'supabase_service_key')",
        );
        for (var row in res) {
          if (row['key'] == 'supabase_url') {
            final val = row['value'] as String?;
            if (val != null && val.trim().isNotEmpty) url = val.trim();
          }
          if (row['key'] == 'supabase_service_key') {
            final val = row['value'] as String?;
            if (val != null && val.trim().isNotEmpty) key = val.trim();
          }
        }
        // Write back to storage for fast access
        if (url != null && url.isNotEmpty) {
          try { await _storage.write(key: 'supabase_url', value: url); } catch (_) {}
        }
        if (key != null && key.isNotEmpty) {
          try { await _storage.write(key: 'supabase_service_key', value: key); } catch (_) {}
        }
      } catch (_) {}
    }

    return {
      'url': url?.trim(),
      'key': key?.trim(),
    };
  }

  Future<bool> hasCredentials() async {
    final creds = await getCredentials();
    return creds['url'] != null && creds['url']!.isNotEmpty && creds['key'] != null && creds['key']!.isNotEmpty;
  }

  static String formatSupabaseUrl(String input) {
    var url = input.trim();
    // Convert dashboard URLs like https://supabase.com/dashboard/project/abcdefgh/... to https://abcdefgh.supabase.co
    final dashboardMatch = RegExp(r'supabase\.com/dashboard/project/([a-z0-9_-]+)', caseSensitive: false).firstMatch(url);
    if (dashboardMatch != null) {
      final ref = dashboardMatch.group(1);
      return 'https://$ref.supabase.co';
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - 8);
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url;
  }

  Map<String, String> _buildHeaders(String key, {String? contentType, String? prefer}) {
    final cleanKey = key.trim();
    final headers = <String, String>{
      'apikey': cleanKey,
    };
    // Legacy JWTs start with eyJ and require Authorization: Bearer
    // New Supabase keys start with sb_secret_ and only require apikey (Bearer causes Invalid JWT error)
    if (cleanKey.startsWith('eyJ')) {
      headers['Authorization'] = 'Bearer $cleanKey';
    }
    if (contentType != null) {
      headers['Content-Type'] = contentType;
    }
    if (prefer != null) {
      headers['Prefer'] = prefer;
    }
    return headers;
  }

  Future<Map<String, dynamic>> testConnection({String? testUrl, String? testKey}) async {
    String? url = testUrl;
    String? key = testKey;
    if (url == null || key == null || url.trim().isEmpty || key.trim().isEmpty) {
      final creds = await getCredentials();
      url = creds['url'];
      key = creds['key'];
    }
    if (url == null || url.trim().isEmpty || key == null || key.trim().isEmpty) {
      return {'success': false, 'message': 'Supabase Project URL and Service Key are required.'};
    }
    try {
      final cleanUrl = formatSupabaseUrl(url);
      final cleanKey = key.trim();

      // Query published_results table with limit=1 to verify connection, authentication, and schema
      final uri = Uri.parse('$cleanUrl/rest/v1/published_results?select=id&limit=1');
      final response = await http.get(
        uri,
        headers: _buildHeaders(cleanKey),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {
          'success': true, 
          'message': 'Connected to Supabase successfully! Table "published_results" is verified and ready.'
        };
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return {
          'success': false, 
          'message': 'Authentication failed (${response.statusCode}): Invalid Service Role Key. Make sure you pasted the "service_role" secret key, not the anon key.'
        };
      } else if (response.statusCode == 404) {
        final body = response.body.toLowerCase();
        if (body.contains('pgrst204') || body.contains('could not find') || body.contains('schema cache')) {
          return {
            'success': false,
            'message': 'Connected to Supabase, but "published_results" table is missing! Please run the setup.sql script in Supabase SQL Editor.'
          };
        } else {
          return {
            'success': false,
            'message': 'HTTP 404: Supabase endpoint not found at $cleanUrl. Please verify your Project URL.'
          };
        }
      } else {
        return {
          'success': false, 
          'message': 'Supabase responded with HTTP ${response.statusCode}: ${response.body}'
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: ${e.toString().replaceAll("Exception: ", "")}'};
    }
  }

  Future<Map<String, dynamic>> publishExam(int examId) async {
    final creds = await getCredentials();
    if (!await hasCredentials()) throw Exception("Supabase credentials not configured in Settings.");
    
    final db = await DatabaseHelper.instance.database;
    
    // Fetch results
    final results = await db.rawQuery('''
      SELECT r.exam_id, e.name as exam_name, c.name as course, b.start_date as batch,
             s.id as student_id,
             COALESCE(NULLIF(TRIM(s.admission_number), ''), s.registration_number, '') as register_no,
             s.name as student_name, s.dob,
             r.total_marks, r.percentage, r.grade, r.status as result_status,
             'MIPS-' || e.id || '-' || s.id as result_code
      FROM results r
      JOIN exams e ON r.exam_id = e.id
      JOIN students s ON r.student_id = s.id
      JOIN courses c ON s.course_id = c.id
      JOIN batches b ON s.batch_id = b.id
      WHERE r.exam_id = ?
    ''', [examId]);

    if (results.isEmpty) throw Exception("No results found to publish.");

    // Validation: Ensure all students have a valid admission/register number
    final missingReg = results.where((r) => (r['register_no']?.toString().trim() ?? '').isEmpty).toList();
    if (missingReg.isNotEmpty) {
      final names = missingReg.take(3).map((s) => s['student_name']).join(', ');
      throw Exception('Cannot publish: Students ($names) do not have an Admission Number.');
    }

    // Validation: Ensure all students have Date of Birth
    final missingDob = results.where((r) => (r['dob']?.toString().trim() ?? '').isEmpty).toList();
    if (missingDob.isNotEmpty) {
      final names = missingDob.take(3).map((s) => s['student_name']).join(', ');
      final more = missingDob.length > 3 ? ' and ${missingDob.length - 3} more' : '';
      throw Exception('Cannot publish: Students ($names$more) are missing Date of Birth. Please edit their profile and enter DOB (YYYY-MM-DD) so they can log into the portal.');
    }

    final List<Map<String, dynamic>> payload = [];
    for (var r in results) {
      // Get subject marks using student_id directly
      final subjects = await db.rawQuery('''
        SELECT s.name, s.max_marks as max, m.marks_obtained as obtained, m.status
        FROM marks m
        JOIN subjects s ON m.subject_id = s.id
        WHERE m.exam_id = ? AND m.student_id = ?
        ORDER BY s.display_order ASC, s.id ASC
      ''', [examId, r['student_id']]);

      payload.add({
        'exam_id': r['exam_id'],
        'exam_name': r['exam_name'],
        'course': r['course'],
        'batch': r['batch'],
        'register_no': r['register_no'].toString().trim().toUpperCase(),
        'student_name': r['student_name'],
        'dob': r['dob'].toString().trim(), // Passed to backend, backend hashes it immediately
        'subjects_json': subjects,
        'total': r['total_marks'],
        'percentage': r['percentage'],
        'grade': r['grade'],
        'result_status': r['result_status'],
        'result_code': r['result_code']
      });
    }

    // Call RPC
    final cleanUrl = formatSupabaseUrl(creds['url']!);
    final uri = Uri.parse('$cleanUrl/rest/v1/rpc/publish_results');
    final response = await http.post(
      uri,
      headers: _buildHeaders(
        creds['key']!,
        contentType: 'application/json',
        prefer: 'return=representation',
      ),
      body: jsonEncode({'payload': payload}),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final jsonResponse = jsonDecode(response.body);
      
      // Audit log
      await db.insert('audit_log', {
        'action': 'PUBLISH',
        'table_name': 'exams',
        'record_id': examId.toString(),
        'created_at': DateTime.now().toIso8601String()
      });

      // Update sync status locally
      await db.update('exams', {
        'sync_status': 'Published, ${payload.length} students, synced ${DateTime.now().toString().substring(0, 16)}',
        'is_published': 1,
      }, where: 'id = ?', whereArgs: [examId]);

      return {'success': true, 'processed': jsonResponse['processed'] ?? payload.length};
    } else {
      throw Exception('Failed to publish: ${response.body}');
    }
  }

  Future<void> unpublishExam(int examId) async {
    final creds = await getCredentials();
    if (!await hasCredentials()) throw Exception("Supabase credentials not configured.");
    
    final db = await DatabaseHelper.instance.database;
    final cleanUrl = formatSupabaseUrl(creds['url']!);
    final uri = Uri.parse('$cleanUrl/rest/v1/rpc/unpublish_exam');
    
    final response = await http.post(
      uri,
      headers: _buildHeaders(
        creds['key']!,
        contentType: 'application/json',
        prefer: 'return=representation',
      ),
      body: jsonEncode({'p_exam_id': examId}),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      await db.insert('audit_log', {
        'action': 'UNPUBLISH',
        'table_name': 'exams',
        'record_id': examId.toString(),
        'created_at': DateTime.now().toIso8601String()
      });

      await db.update('exams', {
        'sync_status': null,
        'is_published': 0,
      }, where: 'id = ?', whereArgs: [examId]);
    } else {
      throw Exception('Failed to unpublish: ${response.body}');
    }
  }
}
