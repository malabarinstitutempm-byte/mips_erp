import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/fee.dart';
import '../../core/models/payment.dart';
import '../../core/models/student.dart';
import '../../core/repositories/interfaces/fee_repository_interface.dart';
import '../../core/repositories/interfaces/payment_repository_interface.dart';
import '../../core/repositories/supabase/supabase_fee_repository.dart';
import '../../core/repositories/supabase/supabase_payment_repository.dart';
import '../students/student_provider.dart';

final feeRepositoryProvider = Provider<FeeRepository>((ref) => SupabaseFeeRepository());
final paymentRepositoryProvider = Provider<PaymentRepository>((ref) => SupabasePaymentRepository());

final feeDetailsProvider = FutureProvider.family<Fee?, int>((ref, studentId) async {
  return ref.read(feeRepositoryProvider).getFeeForStudent(studentId);
});

final paymentHistoryProvider = FutureProvider.family<List<Payment>, int>((ref, studentId) async {
  return ref.read(paymentRepositoryProvider).getPaymentsForStudent(studentId);
});

// A combined provider for Fee Screen (Student + Fee details)
final studentSearchProvider = FutureProvider.family<List<Student>, String>((ref, query) async {
  return ref.read(studentRepositoryProvider).getStudents(query: query.isEmpty ? null : query);
});
