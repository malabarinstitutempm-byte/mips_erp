// lib/core/models/announcement.dart

class Announcement {
  final int id;
  final String category; // 'programme', 'exam', 'fee_reminder', 'timetable', 'general'
  final String title;
  final String body;
  final String audienceType; // 'all_students', 'course', 'batch', 'teachers', 'fee_defaulters'
  final List<dynamic> audienceIds;
  final int minBalancePaise;
  final int recipientCount;
  final int readCount;
  final String? createdAt;
  final String? retractedAt;

  Announcement({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.audienceType,
    this.audienceIds = const [],
    this.minBalancePaise = 0,
    this.recipientCount = 0,
    this.readCount = 0,
    this.createdAt,
    this.retractedAt,
  });

  bool get isRetracted => retractedAt != null;

  factory Announcement.fromMap(Map<String, dynamic> map) {
    return Announcement(
      id: map['id'] is int ? map['id'] : int.parse(map['id'].toString()),
      category: map['category'] ?? 'general',
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      audienceType: map['audience_type'] ?? 'all_students',
      audienceIds: map['audience_ids'] is List ? map['audience_ids'] : [],
      minBalancePaise: map['min_balance_paise'] is int ? map['min_balance_paise'] : int.tryParse(map['min_balance_paise']?.toString() ?? '0') ?? 0,
      recipientCount: map['recipient_count'] is int ? map['recipient_count'] : int.tryParse(map['recipient_count']?.toString() ?? '0') ?? 0,
      readCount: map['read_count'] is int ? map['read_count'] : int.tryParse(map['read_count']?.toString() ?? '0') ?? 0,
      createdAt: map['created_at']?.toString(),
      retractedAt: map['retracted_at']?.toString(),
    );
  }
}
