import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/document_template.dart';
import '../../core/repositories/document_repository.dart';

final documentRepositoryProvider = Provider((ref) => DocumentRepository());

final templatesProvider = FutureProvider<List<DocumentTemplate>>((ref) async {
  final repo = ref.read(documentRepositoryProvider);
  final templates = await repo.getTemplates();
  if (templates.isEmpty) {
    // Seed templates
    final bonafide = DocumentTemplate(
      name: 'Bonafide Certificate',
      content: 'This is to certify that Mr/Ms. {{student_name}} (Adm No: {{admission_number}}) is a bonafide student of {{university}} during the academic year 2024-2026. This certificate is issued upon the student\'s request for general purposes.',
    );
    final fee = DocumentTemplate(
      name: 'Fee Certificate',
      content: 'This is to certify that Mr/Ms. {{student_name}}, admitted under {{course}} (Batch: {{batch}}), has paid the required fees. Admission Number: {{admission_number}}.',
    );
    final tc = DocumentTemplate(
      name: 'Transfer Certificate',
      content: 'Transfer Certificate for Mr/Ms. {{student_name}}, Admission Number: {{admission_number}}. The student has completed the course {{course}}.',
    );
    final study = DocumentTemplate(
      name: 'Study Certificate',
      content: 'This is to certify that Mr/Ms. {{student_name}}, is a regular student of this institution studying in {{course}}.',
    );
    final completion = DocumentTemplate(
      name: 'Course Completion Certificate',
      content: 'This is to certify that {{title}} {{student_name}} (Adm No: {{admission_number}}) has successfully completed the program {{course}} (Batch: {{batch}}) on {{completion_date}}. {{He_She}} has fulfilled all prescribed academic curriculum and institutional requirements with exemplary conduct.',
    );
    await repo.addTemplate(bonafide);
    await repo.addTemplate(fee);
    await repo.addTemplate(tc);
    await repo.addTemplate(study);
    await repo.addTemplate(completion);
    return await repo.getTemplates();
  }
  return templates;
});
