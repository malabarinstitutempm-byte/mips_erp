import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/services/supabase_service.dart';

class DailyTimetableEntry {
  final int id;
  final String courseName;
  final String year;
  final String teacherName;
  final String subjectName;
  final String classRoom;
  final String startTime;
  final String endTime;
  final int sortOrder;

  const DailyTimetableEntry({
    required this.id,
    required this.courseName,
    required this.year,
    required this.teacherName,
    required this.subjectName,
    required this.classRoom,
    required this.startTime,
    required this.endTime,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'course_name': courseName,
    'year': year,
    'teacher_name': teacherName,
    'subject_name': subjectName,
    'class_room': classRoom,
    'start_time': startTime,
    'end_time': endTime,
    'sort_order': sortOrder,
  };

  factory DailyTimetableEntry.fromMap(Map<String, dynamic> map) {
    return DailyTimetableEntry(
      id: (map['id'] as num?)?.toInt() ?? DateTime.now().microsecondsSinceEpoch,
      courseName: map['course_name']?.toString() ?? 'DMLT',
      year: map['year']?.toString() ?? '1st Year',
      teacherName: map['teacher_name']?.toString() ?? 'Faculty Member',
      subjectName: map['subject_name']?.toString() ?? 'Subject',
      classRoom: map['class_room']?.toString() ?? 'LH-1',
      startTime: map['start_time']?.toString() ?? '09:00 AM',
      endTime: map['end_time']?.toString() ?? '10:00 AM',
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  DailyTimetableEntry copyWith({
    int? id,
    String? courseName,
    String? year,
    String? teacherName,
    String? subjectName,
    String? classRoom,
    String? startTime,
    String? endTime,
    int? sortOrder,
  }) {
    return DailyTimetableEntry(
      id: id ?? this.id,
      courseName: courseName ?? this.courseName,
      year: year ?? this.year,
      teacherName: teacherName ?? this.teacherName,
      subjectName: subjectName ?? this.subjectName,
      classRoom: classRoom ?? this.classRoom,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class DailyTimetable {
  final int id;
  final String date; // YYYY-MM-DD
  final String status; // 'draft', 'published', 'not_created'
  final String? publishedAt;
  final bool notifyUsers;
  final List<DailyTimetableEntry> entries;

  const DailyTimetable({
    required this.id,
    required this.date,
    required this.status,
    this.publishedAt,
    this.notifyUsers = true,
    this.entries = const [],
  });

  bool get isPublished => status == 'published';
  bool get isDraft => status == 'draft';
  bool get isNotCreated => status == 'not_created' || entries.isEmpty;

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date,
    'status': status,
    'published_at': publishedAt,
    'notify_users': notifyUsers,
    'entries': entries.map((e) => e.toMap()).toList(),
  };

  factory DailyTimetable.fromMap(Map<String, dynamic> map, [List<DailyTimetableEntry>? entriesList]) {
    final rawEntries = entriesList ?? ((map['entries'] as List?)?.map((e) => DailyTimetableEntry.fromMap(Map<String, dynamic>.from(e))).toList() ?? []);
    return DailyTimetable(
      id: (map['id'] as num?)?.toInt() ?? 1,
      date: map['date']?.toString() ?? '',
      status: map['status']?.toString() ?? 'not_created',
      publishedAt: map['published_at']?.toString(),
      notifyUsers: map['notify_users'] == true || map['notify_users'] == 'true',
      entries: rawEntries,
    );
  }

  DailyTimetable copyWith({
    int? id,
    String? date,
    String? status,
    String? publishedAt,
    bool? notifyUsers,
    List<DailyTimetableEntry>? entries,
  }) {
    return DailyTimetable(
      id: id ?? this.id,
      date: date ?? this.date,
      status: status ?? this.status,
      publishedAt: publishedAt ?? this.publishedAt,
      notifyUsers: notifyUsers ?? this.notifyUsers,
      entries: entries ?? this.entries,
    );
  }
}

class DailyTimetableClashHelper {
  static int _timeToMinutes(String timeStr) {
    try {
      final clean = timeStr.trim().toUpperCase();
      final isPm = clean.contains('PM');
      final isAm = clean.contains('AM');
      final parts = clean.replaceAll(RegExp(r'[^\d:]'), '').split(':');
      var hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      if (isPm && hour < 12) hour += 12;
      if (isAm && hour == 12) hour = 0;
      return hour * 60 + minute;
    } catch (_) {
      return 0;
    }
  }

  static bool _overlaps(DailyTimetableEntry a, DailyTimetableEntry b) {
    if (a.id == b.id) return false;
    final aStart = _timeToMinutes(a.startTime);
    final aEnd = _timeToMinutes(a.endTime);
    final bStart = _timeToMinutes(b.startTime);
    final bEnd = _timeToMinutes(b.endTime);
    return (aStart < bEnd) && (bStart < aEnd);
  }

  /// Detects non-blocking warnings for teacher, room, and cohort conflicts
  static List<String> detectClashes(List<DailyTimetableEntry> entries) {
    final warnings = <String>[];

    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final a = entries[i];
        final b = entries[j];

        if (_overlaps(a, b)) {
          // 1. Teacher conflict
          if (a.teacherName.trim().isNotEmpty &&
              a.teacherName.trim().toLowerCase() == b.teacherName.trim().toLowerCase()) {
            warnings.add('Teacher Clash: "${a.teacherName}" is assigned to both ${a.courseName} (${a.startTime}-${a.endTime}) and ${b.courseName} (${b.startTime}-${b.endTime}).');
          }

          // 2. Room/Classroom conflict
          if (a.classRoom.trim().isNotEmpty &&
              a.classRoom.trim().toLowerCase() == b.classRoom.trim().toLowerCase()) {
            warnings.add('Room Clash: Class "${a.classRoom}" is booked for both ${a.subjectName} and ${b.subjectName} at overlapping times.');
          }

          // 3. Same course and year conflict
          if (a.courseName.trim().toLowerCase() == b.courseName.trim().toLowerCase() &&
              a.year.trim().toLowerCase() == b.year.trim().toLowerCase()) {
            warnings.add('Cohort Conflict: ${a.courseName} (${a.year}) has overlapping classes "${a.subjectName}" and "${b.subjectName}".');
          }
        }
      }
    }
    return warnings.toSet().toList(); // unique
  }
}

class DailyTimetableService {
  static final DailyTimetableService instance = DailyTimetableService._();
  DailyTimetableService._();

  static const _storage = FlutterSecureStorage();
  static const _storageKeyPrefix = 'mips_daily_timetable_';

  static String getTomorrowDateString() {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    return "${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";
  }

  static String getTodayDateString() {
    final now = DateTime.now();
    return "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  static List<String> getRecentDates() {
    final list = <String>[];
    final now = DateTime.now();
    for (int i = 0; i < 7; i++) {
      final d = now.subtract(Duration(days: i));
      list.add("${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}");
    }
    return list;
  }

  static final List<DailyTimetableEntry> _defaultSeedEntries = [
    const DailyTimetableEntry(
      id: 1,
      courseName: 'DMLT',
      year: '1st Year',
      teacherName: 'Prof. Suresh Kumar',
      subjectName: 'Clinical Biochemistry',
      classRoom: 'LH-1',
      startTime: '09:00 AM',
      endTime: '10:00 AM',
      sortOrder: 1,
    ),
    const DailyTimetableEntry(
      id: 2,
      courseName: 'DRT',
      year: '1st Year',
      teacherName: 'Dr. Aysha Mariyam',
      subjectName: 'Radiographic Anatomy',
      classRoom: 'LH-2',
      startTime: '09:00 AM',
      endTime: '10:00 AM',
      sortOrder: 2,
    ),
    const DailyTimetableEntry(
      id: 3,
      courseName: 'DOTAT',
      year: '2nd Year',
      teacherName: 'Dr. Alan Turing',
      subjectName: 'Anesthesia Techniques',
      classRoom: 'OT-Lab',
      startTime: '10:15 AM',
      endTime: '11:15 AM',
      sortOrder: 3,
    ),
    const DailyTimetableEntry(
      id: 4,
      courseName: 'DMLT',
      year: '1st Year',
      teacherName: 'Prof. Fatima',
      subjectName: 'Medical Microbiology',
      classRoom: 'Lab-A',
      startTime: '10:15 AM',
      endTime: '12:30 PM',
      sortOrder: 4,
    ),
    const DailyTimetableEntry(
      id: 5,
      courseName: 'B.Sc MLT',
      year: '2nd Year',
      teacherName: 'Prof. Suresh Kumar',
      subjectName: 'Clinical Pathology',
      classRoom: 'LH-3',
      startTime: '01:30 PM',
      endTime: '02:30 PM',
      sortOrder: 5,
    ),
    const DailyTimetableEntry(
      id: 6,
      courseName: 'DRT',
      year: '2nd Year',
      teacherName: 'Dr. Aysha Mariyam',
      subjectName: 'Radiation Physics',
      classRoom: 'X-Ray Lab',
      startTime: '02:45 PM',
      endTime: '04:00 PM',
      sortOrder: 6,
    ),
  ];

  final Map<String, DailyTimetable> _memoryCache = {};

  Future<DailyTimetable> getTimetableForDate(String date) async {
    if (_memoryCache.containsKey(date)) {
      return _memoryCache[date]!;
    }

    try {
      final jsonStr = await _storage
          .read(key: '$_storageKeyPrefix$date')
          .timeout(const Duration(milliseconds: 300), onTimeout: () => null);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr);
        final tt = DailyTimetable.fromMap(decoded);
        _memoryCache[date] = tt;
        return tt;
      }
    } catch (_) {}

    // Check remote Supabase if available
    try {
      final client = SupabaseService.instance.client;
      final dtRow = await client
          .from('daily_timetables')
          .select()
          .eq('date', date)
          .maybeSingle()
          .timeout(const Duration(milliseconds: 500), onTimeout: () => null);
      if (dtRow != null) {
        final entriesData = await client
            .from('daily_timetable_entries')
            .select()
            .eq('date', date)
            .order('sort_order')
            .timeout(const Duration(milliseconds: 500), onTimeout: () => []);
        final entriesList = (entriesData as List).map((e) => DailyTimetableEntry.fromMap(Map<String, dynamic>.from(e))).toList();
        final tt = DailyTimetable.fromMap(Map<String, dynamic>.from(dtRow), entriesList);
        _memoryCache[date] = tt;
        return tt;
      }
    } catch (_) {}

    // Fallback default: If requested date is tomorrow or today, provide seed data for immediate demonstration
    final isTomorrowOrToday = date == getTomorrowDateString() || date == getTodayDateString();
    final defaultStatus = isTomorrowOrToday ? 'draft' : 'not_created';
    final entries = isTomorrowOrToday ? List<DailyTimetableEntry>.from(_defaultSeedEntries) : <DailyTimetableEntry>[];

    final defaultTt = DailyTimetable(
      id: date.hashCode.abs(),
      date: date,
      status: defaultStatus,
      publishedAt: null,
      notifyUsers: true,
      entries: entries,
    );

    _memoryCache[date] = defaultTt;
    return defaultTt;
  }

  Future<void> saveDraft(String date, List<DailyTimetableEntry> entries) async {
    final updated = DailyTimetable(
      id: date.hashCode.abs(),
      date: date,
      status: 'draft',
      publishedAt: null,
      notifyUsers: true,
      entries: entries,
    );

    _memoryCache[date] = updated;
    await _persist(date, updated);
  }

  Future<void> publish(String date, List<DailyTimetableEntry> entries, {bool notifyUsers = true}) async {
    final updated = DailyTimetable(
      id: date.hashCode.abs(),
      date: date,
      status: 'published',
      publishedAt: DateTime.now().toIso8601String(),
      notifyUsers: notifyUsers,
      entries: entries,
    );

    _memoryCache[date] = updated;
    await _persist(date, updated);
  }

  Future<void> unpublish(String date) async {
    final current = await getTimetableForDate(date);
    final updated = current.copyWith(status: 'draft', publishedAt: null);
    _memoryCache[date] = updated;
    await _persist(date, updated);
  }

  Future<DailyTimetable> copyFromPreviousDay(String targetDate) async {
    final targetDt = DateTime.parse(targetDate);
    final prevDt = targetDt.subtract(const Duration(days: 1));
    final prevDateStr = "${prevDt.year.toString().padLeft(4, '0')}-${prevDt.month.toString().padLeft(2, '0')}-${prevDt.day.toString().padLeft(2, '0')}";

    final prevTt = await getTimetableForDate(prevDateStr);
    final copiedEntries = prevTt.entries.map((e) {
      return e.copyWith(id: DateTime.now().microsecondsSinceEpoch + e.id);
    }).toList();

    // If prev day had no entries, copy standard seed
    final effectiveEntries = copiedEntries.isNotEmpty ? copiedEntries : List<DailyTimetableEntry>.from(_defaultSeedEntries);

    final updated = DailyTimetable(
      id: targetDate.hashCode.abs(),
      date: targetDate,
      status: 'draft',
      publishedAt: null,
      notifyUsers: true,
      entries: effectiveEntries,
    );

    _memoryCache[targetDate] = updated;
    await _persist(targetDate, updated);
    return updated;
  }

  Future<bool> isTomorrowPublished() async {
    final tomorrowStr = getTomorrowDateString();
    final tt = await getTimetableForDate(tomorrowStr);
    return tt.status == 'published';
  }

  Future<void> _persist(String date, DailyTimetable tt) async {
    try {
      final jsonStr = jsonEncode(tt.toMap());
      await _storage
          .write(key: '$_storageKeyPrefix$date', value: jsonStr)
          .timeout(const Duration(milliseconds: 300));
    } catch (_) {}

    try {
      final client = SupabaseService.instance.client;
      await client.from('daily_timetables').upsert({
        'date': date,
        'status': tt.status,
        'published_at': tt.publishedAt,
        'notify_users': tt.notifyUsers,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'date');

      // Sync entries
      await client.from('daily_timetable_entries').delete().eq('date', date);
      if (tt.entries.isNotEmpty) {
        final rows = tt.entries.asMap().entries.map((entry) {
          final idx = entry.key;
          final e = entry.value;
          return {
            'date': date,
            'course_name': e.courseName,
            'year': e.year,
            'teacher_name': e.teacherName,
            'subject_name': e.subjectName,
            'class_room': e.classRoom,
            'start_time': e.startTime,
            'end_time': e.endTime,
            'sort_order': idx + 1,
          };
        }).toList();
        await client.from('daily_timetable_entries').insert(rows);
      }
    } catch (_) {}
  }
}
