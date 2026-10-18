import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('Local SQLite is disabled on Web. Supabase Cloud is master.');
    }
    if (_database != null) return _database!;
    _database = await _initDB('mips_erp.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dbDirPath = join(appDocDir.path, 'MIPS_ERP_Database');
    
    // Ensure the directory exists
    final dbDir = Directory(dbDirPath);
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    
    final path = join(dbDirPath, filePath);

    return await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: _createDB,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
        onOpen: _onOpen,
      ),
    );
  }

  Future _onConfigure(Database db) async {
    // Add support for foreign keys
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA journal_mode = WAL');
  }

  Future _onOpen(Database db) async {
    final columnsToCheck = [
      ('students', 'is_deleted', 'INTEGER NOT NULL DEFAULT 0'),
      ('courses', 'is_deleted', 'INTEGER NOT NULL DEFAULT 0'),
      ('courses', 'total_fee_paise', 'INTEGER NOT NULL DEFAULT 0'),
      ('batches', 'is_deleted', 'INTEGER NOT NULL DEFAULT 0'),
      ('payments', 'is_deleted', 'INTEGER NOT NULL DEFAULT 0'),
      ('payments', 'amount_paise', 'INTEGER NOT NULL DEFAULT 0'),
      ('payments', 'receipt_id', 'INTEGER'),
      ('payments', 'is_cancelled', 'INTEGER NOT NULL DEFAULT 0'),
      ('exams', 'is_deleted', 'INTEGER NOT NULL DEFAULT 0'),
      ('exams', 'sync_status', 'TEXT'),
      ('exams', 'semester', 'INTEGER'),
      ('fees', 'total_fee_paise', 'INTEGER NOT NULL DEFAULT 0'),
      ('fees', 'paid_amount_paise', 'INTEGER NOT NULL DEFAULT 0'),
      ('fees', 'pending_amount_paise', 'INTEGER NOT NULL DEFAULT 0'),
      ('subjects', 'display_order', 'INTEGER DEFAULT 0'),
      ('students', 'gender', 'TEXT DEFAULT "Male"'),
      ('exams', 'is_published', 'INTEGER NOT NULL DEFAULT 0'),
      ('course_subjects', 'subject_code', 'TEXT'),
    ];

    for (final col in columnsToCheck) {
      try {
        await db.execute('ALTER TABLE ${col.$1} ADD COLUMN ${col.$2} ${col.$3}');
      } catch (_) {
        // Column already exists, safe to ignore
      }
    }

    // Ensure registration_number index is non-unique (allowing multiple unassigned or same board/univ references)
    try {
      await db.execute('DROP INDEX IF EXISTS idx_student_registration');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_registration ON students(registration_number)');
    } catch (_) {}

    // Ensure official institution_address is updated in settings
    try {
      final currentAddress = await db.query('settings', where: 'key = ?', whereArgs: ['institution_address']);
      if (currentAddress.isEmpty) {
        await db.insert('settings', {'key': 'institution_address', 'value': 'CH Centre, Malappuram, Kerala - 676519'});
      } else if (currentAddress.first['value'] == 'Muttipadi, Malappuram, Kerala') {
        await db.update('settings', {'value': 'CH Centre, Malappuram, Kerala - 676519'}, where: 'key = ?', whereArgs: ['institution_address']);
      }
    } catch (_) {}

    // Ensure default grading schemes exist if empty
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS grading_schemes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          min_percent REAL NOT NULL,
          max_percent REAL NOT NULL,
          grade TEXT NOT NULL,
          is_pass INTEGER NOT NULL DEFAULT 1
        )
      ''');
      final existingSchemes = await db.query('grading_schemes');
      if (existingSchemes.isEmpty) {
        final defaultSchemes = [
          {'min_percent': 90.0, 'max_percent': 100.0, 'grade': 'A+', 'is_pass': 1},
          {'min_percent': 80.0, 'max_percent': 89.99, 'grade': 'A', 'is_pass': 1},
          {'min_percent': 70.0, 'max_percent': 79.99, 'grade': 'B+', 'is_pass': 1},
          {'min_percent': 60.0, 'max_percent': 69.99, 'grade': 'B', 'is_pass': 1},
          {'min_percent': 50.0, 'max_percent': 59.99, 'grade': 'C+', 'is_pass': 1},
          {'min_percent': 40.0, 'max_percent': 49.99, 'grade': 'C', 'is_pass': 1},
          {'min_percent': 0.0, 'max_percent': 39.99, 'grade': 'F', 'is_pass': 0},
        ];
        for (final s in defaultSchemes) {
          await db.insert('grading_schemes', s);
        }
      }
    } catch (_) {}

    // Backfill any missing student fees records based on their course fees and payment records
    try {
      final missingStudents = await db.rawQuery('''
        SELECT s.id as student_id, 
               COALESCE(c.total_fee_paise, CAST(c.total_fee * 100 AS INTEGER), 0) as total_fee_paise,
               COALESCE(c.total_fee, c.total_fee_paise / 100.0, 0) as total_fee
        FROM students s
        JOIN courses c ON s.course_id = c.id
        LEFT JOIN fees f ON f.student_id = s.id
        WHERE f.id IS NULL AND COALESCE(s.is_deleted, 0) = 0
      ''');

      for (final s in missingStudents) {
        final studentId = s['student_id'] as int;
        final totalPaise = (s['total_fee_paise'] as num?)?.toInt() ?? 0;
        final totalFee = (s['total_fee'] as num?)?.toDouble() ?? (totalPaise / 100.0);

        final paidRes = await db.rawQuery('''
          SELECT COALESCE(SUM(COALESCE(amount_paise, CAST(amount * 100 AS INTEGER), 0)), 0) as total_paid_paise
          FROM payments
          WHERE student_id = ? AND COALESCE(is_deleted, 0) = 0 AND COALESCE(is_cancelled, 0) = 0
        ''', [studentId]);

        final paidPaise = (paidRes.first['total_paid_paise'] as num?)?.toInt() ?? 0;
        final pendingPaise = totalPaise > paidPaise ? (totalPaise - paidPaise) : 0;

        await db.insert('fees', {
          'student_id': studentId,
          'total_fee': totalFee,
          'paid_amount': paidPaise / 100.0,
          'pending_amount': pendingPaise / 100.0,
          'total_fee_paise': totalPaise,
          'paid_amount_paise': paidPaise,
          'pending_amount_paise': pendingPaise,
        });
      }
    } catch (_) {}
  }

  Future<void> _safeExecute(Database db, String sql) async {
    try {
      await db.execute(sql);
    } catch (_) {}
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 1. Safety Backup
      final dbPath = db.path;
      final backupDir = Directory(join(dirname(dbPath), 'backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final backupPath = join(backupDir.path, 'auto_pre_v2_migration_$timestamp.db');
      await File(dbPath).copy(backupPath);

      // 2. Migration in Transaction
      await db.transaction((txn) async {
        // Alter students table
        await txn.execute('ALTER TABLE students ADD COLUMN profile_photo_path TEXT');
        await txn.execute('ALTER TABLE students ADD COLUMN profile_photo_thumb_path TEXT');
        await txn.execute('ALTER TABLE students ADD COLUMN profile_photo_updated_at TEXT');

        // Create new tables
        await txn.execute('''
          CREATE TABLE student_record_types (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            category TEXT NOT NULL,
            description TEXT,
            is_required INTEGER NOT NULL DEFAULT 0,
            allow_multiple INTEGER NOT NULL DEFAULT 0,
            allowed_extensions TEXT NOT NULL,
            is_system INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await txn.execute('''
          CREATE TABLE student_records (
            id TEXT PRIMARY KEY,
            student_id INTEGER NOT NULL,
            record_type_id INTEGER NOT NULL,
            file_path TEXT NOT NULL,
            original_filename TEXT NOT NULL,
            extension TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            sha256 TEXT NOT NULL,
            document_number TEXT,
            issue_date TEXT,
            expiry_date TEXT,
            notes TEXT,
            status TEXT NOT NULL DEFAULT 'current',
            replaced_by_id TEXT,
            uploaded_at TEXT NOT NULL,
            uploaded_by TEXT,
            FOREIGN KEY (student_id) REFERENCES students (id),
            FOREIGN KEY (record_type_id) REFERENCES student_record_types (id)
          )
        ''');

        await txn.execute('''
          CREATE TABLE student_record_audit (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL,
            record_id TEXT,
            action TEXT NOT NULL,
            performed_by TEXT,
            performed_at TEXT NOT NULL,
            details TEXT,
            FOREIGN KEY (student_id) REFERENCES students (id)
          )
        ''');
        // Seed default record types

        final defaultTypes = [
          {'name': 'Aadhaar Card', 'category': 'Identity', 'req': 1, 'mult': 0, 'ext': 'pdf,jpg,jpeg,png'},
          {'name': 'Other ID Proof', 'category': 'Identity', 'req': 0, 'mult': 1, 'ext': 'pdf,jpg,jpeg,png'},
          {'name': 'SSLC Certificate', 'category': 'Academic', 'req': 1, 'mult': 0, 'ext': 'pdf,jpg,jpeg,png'},
          {'name': 'Plus Two Certificate', 'category': 'Academic', 'req': 1, 'mult': 0, 'ext': 'pdf,jpg,jpeg,png'},
          {'name': 'Previous Qualification Certificate', 'category': 'Academic', 'req': 0, 'mult': 1, 'ext': 'pdf,jpg,jpeg,png'},
          {'name': 'Transfer Certificate', 'category': 'Institutional', 'req': 0, 'mult': 0, 'ext': 'pdf,jpg,jpeg,png'},
          {'name': 'Migration Certificate', 'category': 'Institutional', 'req': 0, 'mult': 0, 'ext': 'pdf,jpg,jpeg,png'},
          {'name': 'Other Institutional Document', 'category': 'Institutional', 'req': 0, 'mult': 1, 'ext': 'pdf,jpg,jpeg,png'},
        ];

        for (var i = 0; i < defaultTypes.length; i++) {
          final t = defaultTypes[i];
          await txn.insert('student_record_types', {
            'name': t['name'],
            'category': t['category'],
            'is_required': t['req'],
            'allow_multiple': t['mult'],
            'allowed_extensions': t['ext'],
            'is_system': 1,
            'is_active': 1,
            'sort_order': i,
          });
        }
      });
    }

    if (oldVersion < 3) {
      await db.transaction((txn) async {
        // Seed default universities, academic_years, batches if empty
        final unis = await txn.query('universities');
        if (unis.isEmpty) {
          await txn.insert('universities', {'id': 1, 'name': 'Default University'});
        }
        final ays = await txn.query('academic_years');
        if (ays.isEmpty) {
          await txn.insert('academic_years', {'id': 1, 'year_name': '2024-2025', 'is_current': 1});
        }
        final batches = await txn.query('batches');
        if (batches.isEmpty) {
          await txn.insert('batches', {'id': 1, 'start_date': '2024-01-01', 'end_date': '2025-12-31', 'status': 'Active'});
        }
      });
    }
    if (oldVersion < 4) {
      // students
      await _safeExecute(db, 'ALTER TABLE students ADD COLUMN created_at TEXT');
      await _safeExecute(db, 'ALTER TABLE students ADD COLUMN updated_at TEXT');
      await _safeExecute(db, 'ALTER TABLE students ADD COLUMN is_deleted INTEGER DEFAULT 0');
      
      // courses
      await _safeExecute(db, 'ALTER TABLE courses ADD COLUMN created_at TEXT');
      await _safeExecute(db, 'ALTER TABLE courses ADD COLUMN updated_at TEXT');
      await _safeExecute(db, 'ALTER TABLE courses ADD COLUMN is_deleted INTEGER DEFAULT 0');

      // batches
      await _safeExecute(db, 'ALTER TABLE batches ADD COLUMN created_at TEXT');
      await _safeExecute(db, 'ALTER TABLE batches ADD COLUMN updated_at TEXT');
      await _safeExecute(db, 'ALTER TABLE batches ADD COLUMN is_deleted INTEGER DEFAULT 0');

      // payments
      await _safeExecute(db, 'ALTER TABLE payments ADD COLUMN created_at TEXT');
      await _safeExecute(db, 'ALTER TABLE payments ADD COLUMN updated_at TEXT');
      await _safeExecute(db, 'ALTER TABLE payments ADD COLUMN is_deleted INTEGER DEFAULT 0');

      // exams
      await _safeExecute(db, 'ALTER TABLE exams ADD COLUMN semester TEXT');
      await _safeExecute(db, 'ALTER TABLE exams ADD COLUMN created_at TEXT');
      await _safeExecute(db, 'ALTER TABLE exams ADD COLUMN updated_at TEXT');
      await _safeExecute(db, 'ALTER TABLE exams ADD COLUMN is_deleted INTEGER DEFAULT 0');

      // Registration number index
      await _safeExecute(db, 'CREATE INDEX IF NOT EXISTS idx_student_registration ON students(registration_number)');

      // Performance indexes
      await _safeExecute(db, 'CREATE INDEX IF NOT EXISTS idx_student_course ON students(course_id)');
      await _safeExecute(db, 'CREATE INDEX IF NOT EXISTS idx_student_batch ON students(batch_id)');
      await _safeExecute(db, 'CREATE INDEX IF NOT EXISTS idx_payment_student ON payments(student_id)');
      await _safeExecute(db, 'CREATE INDEX IF NOT EXISTS idx_mark_exam_student ON marks(exam_id, student_id)');

      // New tables
      await _safeExecute(db, '''
        CREATE TABLE IF NOT EXISTS audit_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT NOT NULL,
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          old_value TEXT,
          new_value TEXT,
          user_id INTEGER,
          created_at TEXT NOT NULL
        )
      ''');

      await _safeExecute(db, '''
        CREATE TABLE IF NOT EXISTS course_subjects (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          course_id INTEGER NOT NULL,
          semester TEXT,
          subject_name TEXT NOT NULL,
          max_marks REAL NOT NULL,
          pass_marks REAL NOT NULL,
          FOREIGN KEY (course_id) REFERENCES courses (id)
        )
      ''');

      await _safeExecute(db, '''
        CREATE TABLE IF NOT EXISTS grading_schemes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          min_percent REAL NOT NULL,
          max_percent REAL NOT NULL,
          grade TEXT NOT NULL,
          is_pass INTEGER NOT NULL DEFAULT 1
        )
      ''');
    }
    if (oldVersion < 5) {
      await _safeExecute(db, 'ALTER TABLE users ADD COLUMN failed_attempts INTEGER DEFAULT 0');
      await _safeExecute(db, 'ALTER TABLE users ADD COLUMN locked_until TEXT');
      
      try {
        final users = await db.query('users');
        for (var user in users) {
          if (user['password_hash'] == 'admin') {
            await db.update(
              'users',
              {'password_hash': r'$2a$10$iLcSqOOSQjxAnIN5Qrvlwu5obuBUv.LWmsL5PuMFmlnjS8FbmBxeG', 'role': 'admin'},
              where: 'id = ?',
              whereArgs: [user['id']]
            );
          }
        }
      } catch (_) {}
    }
    if (oldVersion < 6) {
      // New tables
      await _safeExecute(db, '''
        CREATE TABLE IF NOT EXISTS fee_heads (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          description TEXT
        )
      ''');
      
      await _safeExecute(db, '''
        CREATE TABLE IF NOT EXISTS fee_structures (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          course_id INTEGER NOT NULL,
          academic_year_id INTEGER NOT NULL,
          fee_head_id INTEGER NOT NULL,
          amount_paise INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (course_id) REFERENCES courses (id),
          FOREIGN KEY (academic_year_id) REFERENCES academic_years (id),
          FOREIGN KEY (fee_head_id) REFERENCES fee_heads (id)
        )
      ''');
      
      await _safeExecute(db, '''
        CREATE TABLE IF NOT EXISTS student_fees (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id INTEGER NOT NULL,
          fee_head_id INTEGER NOT NULL,
          amount_paise INTEGER NOT NULL DEFAULT 0,
          due_date TEXT,
          discount_paise INTEGER NOT NULL DEFAULT 0,
          fine_paise INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'pending',
          FOREIGN KEY (student_id) REFERENCES students (id),
          FOREIGN KEY (fee_head_id) REFERENCES fee_heads (id)
        )
      ''');

      // Alter payments
      await _safeExecute(db, 'ALTER TABLE payments ADD COLUMN amount_paise INTEGER NOT NULL DEFAULT 0');
      await _safeExecute(db, 'ALTER TABLE payments ADD COLUMN receipt_id INTEGER');
      await _safeExecute(db, 'ALTER TABLE payments ADD COLUMN is_cancelled INTEGER NOT NULL DEFAULT 0');
      await _safeExecute(db, 'ALTER TABLE payments ADD COLUMN cancel_reason TEXT');
      await _safeExecute(db, 'ALTER TABLE payments ADD COLUMN cancelled_at TEXT');
      await _safeExecute(db, 'ALTER TABLE payments ADD COLUMN cancelled_by INTEGER');

      // Alter fees
      await _safeExecute(db, 'ALTER TABLE fees ADD COLUMN total_fee_paise INTEGER NOT NULL DEFAULT 0');
      await _safeExecute(db, 'ALTER TABLE fees ADD COLUMN paid_amount_paise INTEGER NOT NULL DEFAULT 0');
      await _safeExecute(db, 'ALTER TABLE fees ADD COLUMN pending_amount_paise INTEGER NOT NULL DEFAULT 0');

      // Alter courses
      await _safeExecute(db, 'ALTER TABLE courses ADD COLUMN total_fee_paise INTEGER NOT NULL DEFAULT 0');

      // Data migration (REAL to INTEGER paise)
      await _safeExecute(db, 'UPDATE payments SET amount_paise = CAST(amount * 100 AS INTEGER) WHERE amount_paise = 0 OR amount_paise IS NULL');
      await _safeExecute(db, 'UPDATE fees SET total_fee_paise = CAST(total_fee * 100 AS INTEGER), paid_amount_paise = CAST(paid_amount * 100 AS INTEGER), pending_amount_paise = CAST(pending_amount * 100 AS INTEGER) WHERE total_fee_paise = 0 OR total_fee_paise IS NULL');
      await _safeExecute(db, 'UPDATE courses SET total_fee_paise = CAST(total_fee * 100 AS INTEGER) WHERE total_fee_paise = 0 OR total_fee_paise IS NULL');
    }
    if (oldVersion < 7) {
      await _safeExecute(db, 'ALTER TABLE students ADD COLUMN import_id TEXT');
    }
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE generated_documents ADD COLUMN document_number TEXT');
      } catch(e) {}
    }
    if (oldVersion < 9) {
      try {
        await db.execute('ALTER TABLE exams ADD COLUMN sync_status TEXT');
      } catch(e) {}
    }
    if (oldVersion < 10) {
      await db.execute('CREATE TABLE IF NOT EXISTS document_templates (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, content TEXT)');
      await db.execute('CREATE TABLE IF NOT EXISTS generated_documents (id INTEGER PRIMARY KEY AUTOINCREMENT, student_id INTEGER NOT NULL, template_id INTEGER NOT NULL, date TEXT, file_path TEXT, document_number TEXT, FOREIGN KEY (student_id) REFERENCES students (id), FOREIGN KEY (template_id) REFERENCES document_templates (id))');
      await db.execute('CREATE TABLE IF NOT EXISTS results (id INTEGER PRIMARY KEY AUTOINCREMENT, exam_id INTEGER NOT NULL, student_id INTEGER NOT NULL, total_marks REAL NOT NULL, percentage REAL NOT NULL, grade TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT, updated_at TEXT, FOREIGN KEY (exam_id) REFERENCES exams (id), FOREIGN KEY (student_id) REFERENCES students (id))');
      await db.execute('CREATE TABLE IF NOT EXISTS published_exams (id INTEGER PRIMARY KEY AUTOINCREMENT, exam_id INTEGER NOT NULL UNIQUE, published_at TEXT NOT NULL, FOREIGN KEY (exam_id) REFERENCES exams (id))');
      await db.execute('CREATE TABLE IF NOT EXISTS course_subjects (id INTEGER PRIMARY KEY AUTOINCREMENT, course_id INTEGER NOT NULL, semester TEXT NOT NULL, name TEXT NOT NULL, max_marks REAL NOT NULL, pass_marks REAL NOT NULL, FOREIGN KEY (course_id) REFERENCES courses (id))');
    }
  }

  Future _createDB(Database db, int version) async {



    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textTypeNull = 'TEXT';

    // Users
    await db.execute('''
      CREATE TABLE users (
        id $idType,
        username $textType UNIQUE,
        password_hash $textType,
        role $textType,
          failed_attempts INTEGER DEFAULT 0,
          locked_until TEXT
      )
    ''');

    // Settings
    await db.execute('''
      CREATE TABLE settings (
        key $textType PRIMARY KEY,
        value $textTypeNull
      )
    ''');

    // Add default admin user (password: admin123 -> just a dummy hash for now, will implement properly later)
    await db.execute('''
      INSERT INTO users (username, password_hash, role)
      VALUES ('admin', r'\.LWmsL5PuMFmlnjS8FbmBxeG', 'admin')
    ''');

    // Academic Years
    await db.execute('''
      CREATE TABLE academic_years (
        id $idType,
        year_name $textType,
        is_current INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Universities
    await db.execute('''
      CREATE TABLE universities (
        id $idType,
        name $textType UNIQUE
      )
    ''');

    // Courses
    await db.execute('''
      CREATE TABLE courses (
        id $idType,
        name $textType,
        code $textType UNIQUE,
        university_id INTEGER,
        duration $textTypeNull,
        total_fee REAL NOT NULL DEFAULT 0,
          total_fee_paise INTEGER NOT NULL DEFAULT 0,
        description $textTypeNull,
        status $textType DEFAULT 'Active',
        FOREIGN KEY (university_id) REFERENCES universities (id)
      )
    ''');

    // Batches
    await db.execute('''
      CREATE TABLE batches (
        id $idType,
        course_id INTEGER NOT NULL,
        batch_name $textType,
        start_date $textTypeNull,
        end_date $textTypeNull,
        FOREIGN KEY (course_id) REFERENCES courses (id)
      )
    ''');

    // Students (v2)
    await db.execute('''
      CREATE TABLE students (
        id $idType,
        admission_number $textType UNIQUE,
        registration_number $textTypeNull,
        name $textType,
        course_id INTEGER NOT NULL,
        batch_id INTEGER NOT NULL,\n          semester TEXT,
        university_id INTEGER NOT NULL,
        dob $textTypeNull,
        gender $textTypeNull,
        phone $textTypeNull,
        email $textTypeNull,
        address $textTypeNull,
        admission_date $textTypeNull,
        academic_year_id INTEGER NOT NULL,
        status $textType DEFAULT 'Active',
        profile_photo_path $textTypeNull,
        profile_photo_thumb_path $textTypeNull,
        profile_photo_updated_at $textTypeNull,
        FOREIGN KEY (course_id) REFERENCES courses (id),
        FOREIGN KEY (batch_id) REFERENCES batches (id),
        FOREIGN KEY (university_id) REFERENCES universities (id),
        FOREIGN KEY (academic_year_id) REFERENCES academic_years (id)
      )
    ''');

    // Fees
    await db.execute('''
      CREATE TABLE fees (
        id $idType,
        student_id INTEGER NOT NULL UNIQUE,
        total_fee REAL NOT NULL DEFAULT 0,
          total_fee_paise INTEGER NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        pending_amount REAL NOT NULL DEFAULT 0,
          total_fee_paise INTEGER NOT NULL DEFAULT 0,
          paid_amount_paise INTEGER NOT NULL DEFAULT 0,
          pending_amount_paise INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (student_id) REFERENCES students (id)
      )
    ''');

    // Payments
    await db.execute('''
      CREATE TABLE payments (
        id $idType,
        student_id INTEGER NOT NULL,
        amount REAL NOT NULL,
          amount_paise INTEGER NOT NULL DEFAULT 0,
          receipt_id INTEGER,
          is_cancelled INTEGER NOT NULL DEFAULT 0,
          cancel_reason TEXT,
          cancelled_at TEXT,
          cancelled_by INTEGER,
        payment_mode $textType,
        reference_number $textTypeNull,
        remarks $textTypeNull,
        date $textType,
        FOREIGN KEY (student_id) REFERENCES students (id)
      )
    ''');

    // Receipts
    await db.execute('''
      CREATE TABLE receipts (
        id $idType,
        payment_id INTEGER NOT NULL UNIQUE,
        receipt_number $textType UNIQUE,
        file_path $textTypeNull,
        FOREIGN KEY (payment_id) REFERENCES payments (id)
      )
    ''');
    
    // Document Templates
    await db.execute('''
      CREATE TABLE document_templates (
        id $idType,
        name $textType UNIQUE,
        content $textType
      )
    ''');

    // Generated Documents
    await db.execute('''
      CREATE TABLE generated_documents (
        id $idType,
        student_id INTEGER NOT NULL,
        template_id INTEGER NOT NULL,
        date $textType,
        file_path $textTypeNull,
        FOREIGN KEY (student_id) REFERENCES students (id),
        FOREIGN KEY (template_id) REFERENCES document_templates (id)
      )
    ''');
    
    // Exams
    await db.execute('''
      CREATE TABLE exams (
        id $idType,
        name $textType,
        academic_year_id INTEGER NOT NULL,
        course_id INTEGER NOT NULL,
        batch_id INTEGER NOT NULL,\n          semester TEXT,
        exam_date $textTypeNull,
        publish_date $textTypeNull,
        status $textType DEFAULT 'Draft',
        FOREIGN KEY (academic_year_id) REFERENCES academic_years (id),
        FOREIGN KEY (course_id) REFERENCES courses (id),
        FOREIGN KEY (batch_id) REFERENCES batches (id)
      )
    ''');

    // Subjects
    await db.execute('''
      CREATE TABLE subjects (
        id $idType,
        exam_id INTEGER NOT NULL,
        name $textType,
        code $textType,
        max_marks REAL NOT NULL,
        pass_marks REAL NOT NULL,
        theory_marks REAL,
        practical_marks REAL,
        display_order INTEGER DEFAULT 0,
        FOREIGN KEY (exam_id) REFERENCES exams (id)
      )
    ''');

    // Marks
    await db.execute('''
      CREATE TABLE marks (
        id $idType,
        exam_id INTEGER NOT NULL,
        subject_id INTEGER NOT NULL,
        student_id INTEGER NOT NULL,
        marks_obtained REAL,
        grade $textTypeNull,
        status $textTypeNull,
        UNIQUE (exam_id, subject_id, student_id),
        FOREIGN KEY (exam_id) REFERENCES exams (id),
        FOREIGN KEY (subject_id) REFERENCES subjects (id),
        FOREIGN KEY (student_id) REFERENCES students (id)
      )
    ''');

    // Results
    await db.execute('''
      CREATE TABLE results (
        id $idType,
        exam_id INTEGER NOT NULL,
        student_id INTEGER NOT NULL,
        total_marks REAL,
        percentage REAL,
        grade $textTypeNull,
        status $textTypeNull,
        rank INTEGER,
        UNIQUE (exam_id, student_id),
        FOREIGN KEY (exam_id) REFERENCES exams (id),
        FOREIGN KEY (student_id) REFERENCES students (id)
      )
    ''');

    // Published Exams
    await db.execute('''
      CREATE TABLE published_exams (
        id $idType,
        exam_id INTEGER NOT NULL UNIQUE,
        published_at $textType,
        public_url $textTypeNull,
        FOREIGN KEY (exam_id) REFERENCES exams (id)
      )
    ''');

    // V2: Student Record Types
    await db.execute('''
      CREATE TABLE student_record_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        category TEXT NOT NULL,
        description TEXT,
        is_required INTEGER NOT NULL DEFAULT 0,
        allow_multiple INTEGER NOT NULL DEFAULT 0,
        allowed_extensions TEXT NOT NULL,
        is_system INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // V2: Student Records
    await db.execute('''
      CREATE TABLE student_records (
        id TEXT PRIMARY KEY,
        student_id INTEGER NOT NULL,
        record_type_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        original_filename TEXT NOT NULL,
        extension TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        sha256 TEXT NOT NULL,
        document_number TEXT,
        issue_date TEXT,
        expiry_date TEXT,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'current',
        replaced_by_id TEXT,
        uploaded_at TEXT NOT NULL,
        uploaded_by TEXT,
        FOREIGN KEY (student_id) REFERENCES students (id),
        FOREIGN KEY (record_type_id) REFERENCES student_record_types (id)
      )
    ''');

    // V2: Student Record Audit
    await db.execute('''
      CREATE TABLE student_record_audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        record_id TEXT,
        action TEXT NOT NULL,
        performed_by TEXT,
        performed_at TEXT NOT NULL,
        details TEXT,
        FOREIGN KEY (student_id) REFERENCES students (id)
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_student_registration ON students(registration_number)');
    await db.execute('CREATE INDEX idx_student_course ON students(course_id)');
    await db.execute('CREATE INDEX idx_student_batch ON students(batch_id)');
    await db.execute('CREATE INDEX idx_payment_student ON payments(student_id)');
    await db.execute('CREATE INDEX idx_mark_exam_student ON marks(exam_id, student_id)');

    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        old_value TEXT,
        new_value TEXT,
        user_id INTEGER,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE course_subjects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id INTEGER NOT NULL,
        semester TEXT,
        subject_name TEXT NOT NULL,
        max_marks REAL NOT NULL,
        pass_marks REAL NOT NULL,
        FOREIGN KEY (course_id) REFERENCES courses (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE grading_schemes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        min_percent REAL NOT NULL,
        max_percent REAL NOT NULL,
        grade TEXT NOT NULL,
        is_pass INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE fee_heads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE fee_structures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id INTEGER NOT NULL,
        academic_year_id INTEGER NOT NULL,
        fee_head_id INTEGER NOT NULL,
        amount_paise INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (course_id) REFERENCES courses (id),
        FOREIGN KEY (academic_year_id) REFERENCES academic_years (id),
        FOREIGN KEY (fee_head_id) REFERENCES fee_heads (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE student_fees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        fee_head_id INTEGER NOT NULL,
        amount_paise INTEGER NOT NULL DEFAULT 0,
        due_date TEXT,
        discount_paise INTEGER NOT NULL DEFAULT 0,
        fine_paise INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (student_id) REFERENCES students (id),
        FOREIGN KEY (fee_head_id) REFERENCES fee_heads (id)
      )
    ''');

    // Seed default record types

    final defaultTypes = [
      {'name': 'Aadhaar Card', 'category': 'Identity', 'req': 1, 'mult': 0, 'ext': 'pdf,jpg,jpeg,png'},
      {'name': 'Other ID Proof', 'category': 'Identity', 'req': 0, 'mult': 1, 'ext': 'pdf,jpg,jpeg,png'},
      {'name': 'SSLC Certificate', 'category': 'Academic', 'req': 1, 'mult': 0, 'ext': 'pdf,jpg,jpeg,png'},
      {'name': 'Plus Two Certificate', 'category': 'Academic', 'req': 1, 'mult': 0, 'ext': 'pdf,jpg,jpeg,png'},
      {'name': 'Previous Qualification Certificate', 'category': 'Academic', 'req': 0, 'mult': 1, 'ext': 'pdf,jpg,jpeg,png'},
      {'name': 'Transfer Certificate', 'category': 'Institutional', 'req': 0, 'mult': 0, 'ext': 'pdf,jpg,jpeg,png'},
      {'name': 'Migration Certificate', 'category': 'Institutional', 'req': 0, 'mult': 0, 'ext': 'pdf,jpg,jpeg,png'},
      {'name': 'Other Institutional Document', 'category': 'Institutional', 'req': 0, 'mult': 1, 'ext': 'pdf,jpg,jpeg,png'},
    ];

    for (var i = 0; i < defaultTypes.length; i++) {
      final t = defaultTypes[i];
      await db.insert('student_record_types', {
        'name': t['name'],
        'category': t['category'],
        'is_required': t['req'],
        'allow_multiple': t['mult'],
        'allowed_extensions': t['ext'],
        'is_system': 1,
        'is_active': 1,
        'sort_order': i,
      });
    }
  }
}



