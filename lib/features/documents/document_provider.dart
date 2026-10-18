import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/document_template.dart';
import '../../core/repositories/document_repository.dart';

final documentRepositoryProvider = Provider((ref) => DocumentRepository());

final templatesProvider = FutureProvider<List<DocumentTemplate>>((ref) async {
  return ref.read(documentRepositoryProvider).getTemplates();
});
