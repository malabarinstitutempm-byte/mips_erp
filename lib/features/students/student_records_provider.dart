import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/student_record.dart';
import '../../core/models/student_record_type.dart';
import 'student_provider.dart';

final studentRecordTypesProvider = FutureProvider<List<StudentRecordType>>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  return repo.getRecordTypes();
});

final studentRecordsProvider = FutureProvider.family<List<StudentRecord>, int>((ref, studentId) async {
  final repo = ref.read(studentRepositoryProvider);
  return repo.getStudentRecords(studentId);
});
