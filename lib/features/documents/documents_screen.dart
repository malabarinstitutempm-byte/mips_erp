import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:printing/printing.dart';

import '../../core/models/student.dart';
import '../../core/models/generated_document.dart';
import '../../core/models/document_template.dart';
import '../../core/database/database_helper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/search_field.dart';

import 'documents_provider.dart';
import 'add_template_dialog.dart';
import 'document_generator.dart';
import '../students/student_provider.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  int? _selectedTemplateId;
  Student? _selectedStudent;
  String _searchQuery = '';
  String _selectedCertificateGender = 'Male';
  int _mobileDocTab = 0; // 0 = Template, 1 = Student, 2 = Preview & Print
  
  String _previewContent = '';
  String _currentDocumentNumber = '';

  Future<void> _generatePreview(String templateContent) async {
    if (_selectedStudent == null) return;
    final content = await DocumentGenerator.replaceVariables(
      templateContent,
      _selectedStudent!,
      'MIPS/DOC/PREVIEW',
      overrideGender: _selectedCertificateGender,
    );
    setState(() {
      _previewContent = content;
    });
  }

  Future<String> _generateNextDocumentNumber() async {
    final year = DateTime.now().year;
    final prefix = 'MIPS/DOC/$year/';
    
    if (!kIsWeb) {
      try {
        final db = await DatabaseHelper.instance.database;
        final result = await db.rawQuery(
          "SELECT document_number FROM generated_documents WHERE document_number LIKE ? ORDER BY id DESC LIMIT 1",
          ['$prefix%']
        );

        if (result.isNotEmpty) {
          final lastNumStr = result.first['document_number'] as String;
          final parts = lastNumStr.split('/');
          if (parts.length == 4) {
            final nextNum = (int.tryParse(parts[3]) ?? 0) + 1;
            return '$prefix${nextNum.toString().padLeft(4, '0')}';
          }
        }
      } catch (_) {}
    }

    final rand = (DateTime.now().millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    return '$prefix$rand';
  }

  void _printPdf() async {
    if (_previewContent.isEmpty || _selectedStudent == null || _selectedTemplateId == null) return;
    
    try {
      final docNum = await _generateNextDocumentNumber();
      setState(() => _currentDocumentNumber = docNum);

      final templates = await ref.read(templatesProvider.future);
      final t = templates.firstWhere((x) => x.id == _selectedTemplateId);

      // Re-generate content with actual doc number and selected gender
      final finalContent = await DocumentGenerator.replaceVariables(
        t.content,
        _selectedStudent!,
        docNum,
        overrideGender: _selectedCertificateGender,
      );

      final pdf = await DocumentGenerator.generatePdfDocument(finalContent, docNum);
      
      // Save to database
      final repo = ref.read(documentRepositoryProvider);
      await repo.addGeneratedDocument(GeneratedDocument(
        studentId: _selectedStudent!.id!,
        templateId: _selectedTemplateId!,
        date: DateTime.now().toIso8601String(),
        documentNumber: docNum,
      ));
      
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Document $docNum generated successfully!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(templatesProvider);
    final studentsAsync = ref.watch(studentsProvider(_searchQuery));
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Document Generator',
            subtitle: 'Select a template, fill the details, and generate official documents',
            actions: [
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(context: context, builder: (_) => const AddTemplateDialog());
                },
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add Template'),
              ),
            ],
          ),
          
          if (isMobile) ...[
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(LucideIcons.fileSpreadsheet, size: 16),
                  label: Text('1. Template'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(LucideIcons.userCheck, size: 16),
                  label: Text('2. Student'),
                ),
                ButtonSegment(
                  value: 2,
                  icon: Icon(LucideIcons.printer, size: 16),
                  label: Text('3. Preview'),
                ),
              ],
              selected: {_mobileDocTab},
              onSelectionChanged: (set) => setState(() => _mobileDocTab = set.first),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_mobileDocTab == 0) _buildTemplatesPanel(templatesAsync, isMobile),
            if (_mobileDocTab == 1) _buildDetailsPanel(studentsAsync, templatesAsync, isMobile),
            if (_mobileDocTab == 2) _buildPreviewPanel(isMobile),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _buildTemplatesPanel(templatesAsync, false),
                ),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  flex: 3,
                  child: _buildDetailsPanel(studentsAsync, templatesAsync, false),
                ),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  flex: 4,
                  child: _buildPreviewPanel(false),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTemplatesPanel(AsyncValue<List<DocumentTemplate>> templatesAsync, bool isMobile) {
    return SectionCard(
      title: 'Available Templates',
      padding: EdgeInsets.zero,
      child: templatesAsync.when(
        data: (templates) => ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: templates.length,
          itemBuilder: (context, index) {
            final t = templates[index];
            final isSelected = _selectedTemplateId == t.id;
            return ListTile(
              title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: isMobile && isSelected ? const Text('Selected ✓', style: TextStyle(color: Colors.green, fontSize: 11)) : null,
              selected: isSelected,
              selectedTileColor: AppColors.documents.tint,
              trailing: isMobile ? const Icon(LucideIcons.chevronRight, size: 16) : null,
              onTap: () {
                setState(() {
                  _selectedTemplateId = t.id;
                  if (isMobile) _mobileDocTab = 1; // Auto advance to student picker on mobile
                });
                if (_selectedStudent != null) _generatePreview(t.content);
              },
            );
          },
        ),
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildDetailsPanel(AsyncValue<List<Student>> studentsAsync, AsyncValue<List<DocumentTemplate>> templatesAsync, bool isMobile) {
    return SectionCard(
      title: 'Document Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select Student', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textStrong)),
          const SizedBox(height: AppSpacing.sm),
          SearchField(
            hint: 'Search by Name or Admission No...',
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          
          if (_searchQuery.isNotEmpty)
            Container(
              height: 150,
              decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
              child: studentsAsync.when(
                data: (students) => ListView.builder(
                  itemCount: students.length,
                  itemBuilder: (c, i) {
                    final s = students[i];
                    return ListTile(
                      title: Text(s.name),
                      subtitle: Text(s.admissionNumber ?? ''),
                      onTap: () {
                        final gender = s.gender != null && s.gender!.toLowerCase() == 'female' ? 'Female' : 'Male';
                        setState(() {
                          _selectedStudent = s;
                          _selectedCertificateGender = gender;
                          _searchQuery = '';
                          FocusScope.of(context).unfocus();
                        });
                        if (_selectedTemplateId != null) {
                          final t = templatesAsync.value?.cast<DocumentTemplate?>().firstWhere((x) => x?.id == _selectedTemplateId, orElse: () => null);
                          if (t != null) _generatePreview(t.content);
                        }
                      },
                    );
                  },
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_,__) => const SizedBox(),
              ),
            ),

          if (_selectedStudent != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.user, size: 16, color: AppColors.brandDark),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${_selectedStudent!.name} (${_selectedStudent!.admissionNumber ?? "N/A"})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Certificate Pronoun / Gender:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('He / Son of (Male)'),
                        selected: _selectedCertificateGender == 'Male',
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedCertificateGender = 'Male');
                            if (_selectedTemplateId != null) {
                              final t = templatesAsync.value?.cast<DocumentTemplate?>().firstWhere((x) => x?.id == _selectedTemplateId, orElse: () => null);
                              if (t != null) _generatePreview(t.content);
                            }
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('She / Daughter of (Female)'),
                        selected: _selectedCertificateGender == 'Female',
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedCertificateGender = 'Female');
                            if (_selectedTemplateId != null) {
                              final t = templatesAsync.value?.cast<DocumentTemplate?>().firstWhere((x) => x?.id == _selectedTemplateId, orElse: () => null);
                              if (t != null) _generatePreview(t.content);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: AppSpacing.xl),
          
          // Actions
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _selectedStudent != null && _selectedTemplateId != null ? _printPdf : null,
                  icon: const Icon(LucideIcons.fileText, size: 16),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.documents.base),
                  label: const Text('Generate & Print PDF'),
                ),
              ),
              if (isMobile && _selectedStudent != null && _selectedTemplateId != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _mobileDocTab = 2),
                  icon: const Icon(LucideIcons.eye, size: 16),
                  label: const Text('Preview'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPanel(bool isMobile) {
    return SectionCard(
      title: 'Live Preview (A4)',
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        color: const Color(0xFFE2E8F0),
        child: Center(
          child: AspectRatio(
            aspectRatio: 1 / 1.414,
            child: Container(
              margin: EdgeInsets.all(isMobile ? 10 : AppSpacing.xxl),
              padding: EdgeInsets.all(isMobile ? 14 : AppSpacing.xxl),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Text('INSTITUTION NAME', style: TextStyle(fontSize: isMobile ? 14 : 18, fontWeight: FontWeight.bold))),
                  SizedBox(height: isMobile ? 20.0 : 48.0),
                  if (_previewContent.isEmpty)
                    const Center(child: Text('Select template and student to view preview', style: TextStyle(color: AppColors.textMuted)))
                  else
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(_previewContent, style: TextStyle(fontSize: isMobile ? 11 : 12, height: 1.8)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
