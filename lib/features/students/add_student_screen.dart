import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image/image.dart' as img;

import '../../core/models/student.dart';
import '../../core/models/batch.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/form_section.dart';
import '../../shared/widgets/profile_photo_uploader.dart';
import '../../core/services/file_storage_service.dart';

import 'student_provider.dart';
import '../courses/course_provider.dart';

class AddStudentPanel extends ConsumerStatefulWidget {
  final Student? existingStudent;
  final int? preselectedCourseId;
  const AddStudentPanel({super.key, this.existingStudent, this.preselectedCourseId});

  static Future<void> show(BuildContext context, {Student? student, int? courseId}) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.3),
      transitionDuration: AppDurations.fast,
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: AddStudentPanel(existingStudent: student, preselectedCourseId: courseId),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
  }

  @override
  ConsumerState<AddStudentPanel> createState() => _AddStudentPanelState();
}

class _AddStudentPanelState extends ConsumerState<AddStudentPanel> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _dobCtrl;
  late TextEditingController _regNoCtrl;
  late TextEditingController _admCtrl;
  bool _isManualAdm = false;
  String? _admErrorText;
  int? _selectedCourseId;
  int? _selectedBatchId;
  List<Batch> _primaryBatches = [];
  bool _loadingPrimaryBatches = false;

  bool _enableSkillCourse = false;
  int? _selectedSkillCourseId;
  int? _selectedSkillBatchId;
  late TextEditingController _skillFeeCtrl;
  List<Batch> _skillBatches = [];
  bool _loadingSkillBatches = false;

  String _selectedGender = 'Male';

  @override
  void initState() {
    super.initState();
    _selectedGender = widget.existingStudent?.gender ?? 'Male';
    _nameCtrl = TextEditingController(text: widget.existingStudent?.name);
    _phoneCtrl = TextEditingController(text: widget.existingStudent?.phone);
    _dobCtrl = TextEditingController(text: widget.existingStudent?.dob);
    _regNoCtrl = TextEditingController(text: widget.existingStudent?.registrationNumber);
    _admCtrl = TextEditingController(text: widget.existingStudent?.admissionNumber);
    _skillFeeCtrl = TextEditingController();
    _selectedCourseId = widget.existingStudent?.courseId ?? widget.preselectedCourseId;
    _selectedBatchId = widget.existingStudent?.batchId;

    if (widget.existingStudent?.profilePhotoPath != null &&
        widget.existingStudent!.profilePhotoPath!.startsWith('data:image')) {
      try {
        _profilePhotoBytes = base64Decode(widget.existingStudent!.profilePhotoPath!.split(',').last);
      } catch (_) {}
    }

    if (_selectedCourseId != null) {
      Future.microtask(() async {
        try {
          final batches = await ref.read(batchRepositoryProvider).getBatches(courseId: _selectedCourseId);
          if (mounted) {
            setState(() {
              _primaryBatches = batches;
              if (_selectedBatchId == null && batches.isNotEmpty) {
                _selectedBatchId = batches.first.id;
              }
            });
          }
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _dobCtrl.dispose();
    _regNoCtrl.dispose();
    _admCtrl.dispose();
    _skillFeeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    DateTime initialDate = DateTime(2005, 1, 1);
    if (_dobCtrl.text.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(_dobCtrl.text.trim());
      if (parsed != null) initialDate = parsed;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1960),
      lastDate: DateTime.now(),
      helpText: 'Select Date of Birth (for Exam Portal Login)',
    );

    if (picked != null) {
      final formatted =
          "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      setState(() {
        _dobCtrl.text = formatted;
      });
    }
  }
  
  File? _profilePhotoFile;
  Uint8List? _profilePhotoBytes;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final nextAdmAsync = ref.watch(nextAdmissionNumberProvider);
    final coursesAsync = ref.watch(coursesProvider);

    // Auto-populate admission number when generated if not in manual mode
    if (widget.existingStudent == null && !_isManualAdm && _admCtrl.text.isEmpty && nextAdmAsync.hasValue) {
      _admCtrl.text = nextAdmAsync.value!;
    }

    return Material(
      color: AppColors.surface,
      elevation: 16,
      child: Container(
        width: 540,
        height: double.infinity,
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
              child: Row(
                children: [
                  Icon(LucideIcons.userPlus, color: AppColors.brandDark),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(widget.existingStudent == null ? 'New Admission' : 'Edit Student', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
            ),
            
            // Form
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: [
                      _buildTintedSection(
                        title: 'Personal Details',
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ProfilePhotoUploader(
                              initialFile: _profilePhotoFile,
                              initialBytes: _profilePhotoBytes,
                              initialPhotoPath: widget.existingStudent?.profilePhotoPath,
                              onPhotoChanged: (file) {
                                setState(() => _profilePhotoFile = file);
                              },
                              onBytesChanged: (bytes) {
                                setState(() => _profilePhotoBytes = bytes);
                              },
                            ),
                            const SizedBox(width: AppSpacing.xl),
                            Expanded(
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _nameCtrl,
                                    decoration: const InputDecoration(labelText: 'Full Name', hintText: 'e.g., Mohammed Ali'),
                                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  TextFormField(
                                    controller: _phoneCtrl,
                                    decoration: const InputDecoration(labelText: 'Phone Number', hintText: '+91...'),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  TextFormField(
                                    controller: _dobCtrl,
                                    readOnly: true,
                                    onTap: _pickDob,
                                    decoration: InputDecoration(
                                      labelText: 'Date of Birth (Exam Portal Login)',
                                      hintText: 'YYYY-MM-DD',
                                      prefixIcon: const Icon(LucideIcons.calendar, size: 18),
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_dobCtrl.text.isNotEmpty)
                                            IconButton(
                                              tooltip: 'Clear',
                                              icon: const Icon(LucideIcons.x, size: 16),
                                              onPressed: () => setState(() => _dobCtrl.clear()),
                                            ),
                                          IconButton(
                                            tooltip: 'Select Date',
                                            icon: const Icon(LucideIcons.calendarDays, size: 18),
                                            onPressed: _pickDob,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  DropdownButtonFormField<String>(
                                    value: _selectedGender,
                                    decoration: const InputDecoration(
                                      labelText: 'Gender',
                                      prefixIcon: Icon(LucideIcons.user, size: 18),
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedGender = val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: AppSpacing.xl),
                      
                      _buildTintedSection(
                        title: 'Academic Profile',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Admission Number',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textStrong),
                                ),
                                if (widget.existingStudent == null)
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _isManualAdm = !_isManualAdm;
                                        _admErrorText = null;
                                        if (!_isManualAdm && nextAdmAsync.hasValue) {
                                          _admCtrl.text = nextAdmAsync.value!;
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _isManualAdm ? LucideIcons.checkSquare : LucideIcons.square,
                                            size: 16,
                                            color: _isManualAdm ? AppColors.brandDark : AppColors.textMuted,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Manual Entry',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _isManualAdm ? AppColors.brandDark : AppColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            TextFormField(
                              controller: _admCtrl,
                              readOnly: widget.existingStudent != null || !_isManualAdm,
                              decoration: InputDecoration(
                                hintText: 'e.g. ADM-2026-0001 or custom ID',
                                errorText: _admErrorText,
                                prefixIcon: const Icon(LucideIcons.hash, size: 18),
                                suffixIcon: widget.existingStudent == null && _isManualAdm
                                    ? IconButton(
                                        tooltip: 'Reset to auto-generated sequence',
                                        icon: const Icon(LucideIcons.rotateCcw, size: 16),
                                        onPressed: () {
                                          if (nextAdmAsync.hasValue) {
                                            setState(() {
                                              _admCtrl.text = nextAdmAsync.value!;
                                              _admErrorText = null;
                                            });
                                          }
                                        },
                                      )
                                    : null,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Admission number is required';
                                return null;
                              },
                              onChanged: (val) {
                                if (_admErrorText != null) {
                                  setState(() => _admErrorText = null);
                                }
                              },
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            TextFormField(
                              controller: _regNoCtrl,
                              decoration: const InputDecoration(
                                labelText: 'University Reg No. (Optional)',
                                hintText: 'e.g., MIPS/2026/001 (Optional)',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            coursesAsync.when(
                              data: (courses) {
                                final primaryCourses = courses.where((c) => c.courseType != 'skill').toList();
                                final displayCourses = primaryCourses.isNotEmpty ? primaryCourses : courses;
                                return DropdownButtonFormField<int>(
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'Primary Course'),
                                  value: _selectedCourseId,
                                  items: displayCourses.map((c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                                  )).toList(),
                                  onChanged: (val) async {
                                    setState(() {
                                      _selectedCourseId = val;
                                      _selectedBatchId = null;
                                      _primaryBatches = [];
                                      _loadingPrimaryBatches = true;
                                    });
                                    if (val != null) {
                                      try {
                                        final batches = await ref.read(batchRepositoryProvider).getBatches(courseId: val);
                                        if (mounted) {
                                          setState(() {
                                            _primaryBatches = batches;
                                            if (batches.isNotEmpty) _selectedBatchId = batches.first.id;
                                            _loadingPrimaryBatches = false;
                                          });
                                        }
                                      } catch (_) {
                                        if (mounted) setState(() => _loadingPrimaryBatches = false);
                                      }
                                    }
                                  },
                                  validator: (v) => v == null ? 'Primary course is required' : null,
                                );
                              },
                              loading: () => const LinearProgressIndicator(),
                              error: (_,__) => const Text('Error loading courses'),
                            ),
                            if (_loadingPrimaryBatches)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: LinearProgressIndicator(minHeight: 2),
                              )
                            else if (_primaryBatches.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.lg),
                              DropdownButtonFormField<int>(
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Primary Batch'),
                                value: _selectedBatchId,
                                items: _primaryBatches.map((b) => DropdownMenuItem(
                                  value: b.id,
                                  child: Text(b.batchName, overflow: TextOverflow.ellipsis),
                                )).toList(),
                                onChanged: (val) => setState(() => _selectedBatchId = val),
                                validator: (v) => v == null ? 'Please select a batch' : null,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.existingStudent == null) ...[
                        const SizedBox(height: AppSpacing.xl),
                        _buildTintedSection(
                          title: 'Optional Skill Course',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Enroll in Skill Course', style: TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: const Text(
                                  'Add an optional secondary certification course (tracked with separate fee ledger & batch)',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                                value: _enableSkillCourse,
                                activeColor: Colors.purple,
                                onChanged: (val) {
                                  setState(() {
                                    _enableSkillCourse = val;
                                    if (!val) {
                                      _selectedSkillCourseId = null;
                                      _selectedSkillBatchId = null;
                                      _skillBatches = [];
                                      _skillFeeCtrl.clear();
                                    }
                                  });
                                },
                              ),
                              if (_enableSkillCourse) ...[
                                const SizedBox(height: AppSpacing.md),
                                coursesAsync.when(
                                  data: (allCourses) {
                                    final skillCourses = allCourses.where((c) => c.courseType == 'skill').toList();
                                    if (skillCourses.isEmpty) {
                                      return Container(
                                        padding: const EdgeInsets.all(AppSpacing.md),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.amber.withOpacity(0.3)),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(LucideIcons.alertCircle, color: Colors.amber, size: 18),
                                            SizedBox(width: AppSpacing.sm),
                                            Expanded(
                                              child: Text(
                                                'No skill courses found. Create a course with type "Skill" in Course Management to offer skill courses.',
                                                style: TextStyle(fontSize: 12, color: Colors.amber),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        DropdownButtonFormField<int>(
                                          isExpanded: true,
                                          decoration: const InputDecoration(labelText: 'Select Skill Course'),
                                          value: _selectedSkillCourseId,
                                          items: skillCourses.map((c) => DropdownMenuItem(
                                            value: c.id,
                                            child: Text(c.name, overflow: TextOverflow.ellipsis),
                                          )).toList(),
                                          onChanged: (val) async {
                                            setState(() {
                                              _selectedSkillCourseId = val;
                                              _selectedSkillBatchId = null;
                                              _skillBatches = [];
                                              _loadingSkillBatches = true;
                                              final match = skillCourses.where((c) => c.id == val).toList();
                                              if (match.isNotEmpty) {
                                                _skillFeeCtrl.text = match.first.totalFee.toStringAsFixed(0);
                                              }
                                            });
                                            if (val != null) {
                                              try {
                                                final batches = await ref.read(batchRepositoryProvider).getBatches(courseId: val);
                                                if (mounted) {
                                                  setState(() {
                                                    _skillBatches = batches;
                                                    if (batches.isNotEmpty) _selectedSkillBatchId = batches.first.id;
                                                    _loadingSkillBatches = false;
                                                  });
                                                }
                                              } catch (_) {
                                                if (mounted) setState(() => _loadingSkillBatches = false);
                                              }
                                            }
                                          },
                                          validator: (v) => _enableSkillCourse && v == null ? 'Please select a skill course' : null,
                                        ),
                                        const SizedBox(height: AppSpacing.lg),
                                        if (_loadingSkillBatches)
                                          const Padding(
                                            padding: EdgeInsets.symmetric(vertical: 8),
                                            child: LinearProgressIndicator(minHeight: 2),
                                          )
                                        else
                                          DropdownButtonFormField<int>(
                                            isExpanded: true,
                                            decoration: const InputDecoration(labelText: 'Skill Course Batch'),
                                            value: _selectedSkillBatchId,
                                            items: _skillBatches.map((b) => DropdownMenuItem(
                                              value: b.id,
                                              child: Text(b.batchName, overflow: TextOverflow.ellipsis),
                                            )).toList(),
                                            onChanged: (val) => setState(() => _selectedSkillBatchId = val),
                                            validator: (v) => _enableSkillCourse && v == null ? 'Please select a batch for the skill course' : null,
                                          ),
                                        const SizedBox(height: AppSpacing.lg),
                                        TextFormField(
                                          controller: _skillFeeCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Skill Course Fee (₹)',
                                            prefixText: '₹ ',
                                            hintText: 'e.g., 5000',
                                          ),
                                          keyboardType: TextInputType.number,
                                        ),
                                      ],
                                    );
                                  },
                                  loading: () => const LinearProgressIndicator(),
                                  error: (_, __) => const Text('Error loading skill courses'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            
            // Footer
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: const BoxDecoration(
                color: AppColors.bg,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveStudent,
                    icon: _isSaving 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(LucideIcons.save, size: 18),
                    label: Text(_isSaving ? 'Saving...' : (widget.existingStudent == null ? 'Admit Student' : 'Save Changes')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTintedSection({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: FormSection(
        title: title,
        child: child,
      ),
    );
  }

  void _saveStudent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCourseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an enrolled course')),
      );
      return;
    }

    final admNumber = _admCtrl.text.trim();
    if (admNumber.isEmpty) {
      setState(() => _admErrorText = 'Admission number is required');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(studentRepositoryProvider);

      // Verify uniqueness
      final isUnique = await repo.isAdmissionNumberUnique(
        admNumber,
        excludeStudentId: widget.existingStudent?.id,
      );

      if (!isUnique) {
        setState(() {
          _isSaving = false;
          _admErrorText = 'Admission number "$admNumber" already exists';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Admission number "$admNumber" is already taken. Please enter a unique number.'),
              backgroundColor: AppColors.danger.base,
            ),
          );
        }
        return;
      }

      // Process profile photo if uploaded or changed
      String? displayPath = widget.existingStudent?.profilePhotoPath;
      String? thumbPath = widget.existingStudent?.profilePhotoThumbPath;
      String? photoTime = widget.existingStudent?.profilePhotoUpdatedAt;

      if (_profilePhotoBytes != null || _profilePhotoFile != null) {
        try {
          final rawBytes = _profilePhotoBytes ?? await _profilePhotoFile!.readAsBytes();
          final decoded = img.decodeImage(rawBytes);
          if (decoded != null) {
            final displayImg = img.copyResize(decoded, width: 400, interpolation: img.Interpolation.linear);
            final displayJpg = Uint8List.fromList(img.encodeJpg(displayImg, quality: 85));

            final thumbImg = img.copyResize(decoded, width: 128, interpolation: img.Interpolation.linear);
            final thumbJpg = Uint8List.fromList(img.encodeJpg(thumbImg, quality: 75));

            displayPath = 'data:image/jpeg;base64,${base64Encode(displayJpg)}';
            thumbPath = 'data:image/jpeg;base64,${base64Encode(thumbJpg)}';
            photoTime = DateTime.now().toIso8601String();
          }
        } catch (e) {
          debugPrint('Error preparing profile photo: $e');
        }
      }

      var student = Student(
        id: widget.existingStudent?.id,
        admissionNumber: admNumber,
        registrationNumber: _regNoCtrl.text.trim().isEmpty ? null : _regNoCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        dob: _dobCtrl.text.trim().isEmpty ? null : _dobCtrl.text.trim(),
        gender: _selectedGender,
        courseId: _selectedCourseId!,
        batchId: _selectedBatchId ?? widget.existingStudent?.batchId ?? 1, 
        universityId: widget.existingStudent?.universityId ?? 1, 
        academicYearId: widget.existingStudent?.academicYearId ?? 1,
        status: widget.existingStudent?.status ?? 'active',
        completedOn: widget.existingStudent?.completedOn,
        profilePhotoPath: displayPath,
        profilePhotoThumbPath: thumbPath,
        profilePhotoUpdatedAt: photoTime,
      );

      int studentId;
      if (widget.existingStudent == null) {
        final res = await repo.addStudent(student);
        if (res is Student) {
          studentId = res.id ?? (DateTime.now().millisecondsSinceEpoch % 100000);
        } else if (res is int) {
          studentId = res;
        } else {
          studentId = int.tryParse(res?.toString() ?? '1') ?? 1;
        }
        if (_enableSkillCourse && _selectedSkillCourseId != null && _selectedSkillBatchId != null) {
          final feeAmount = double.tryParse(_skillFeeCtrl.text.trim()) ?? 0.0;
          final feePaise = (feeAmount * 100).toInt();
          await repo.addSkillCourse(
            studentId: studentId,
            courseId: _selectedSkillCourseId!,
            batchId: _selectedSkillBatchId!,
            feePaise: feePaise > 0 ? feePaise : null,
          );
        }
      } else {
        studentId = widget.existingStudent!.id!;
        await repo.updateStudent(student);
      }

      if (!kIsWeb && _profilePhotoFile != null) {
        try {
          await FileStorageService.saveProfilePhoto(studentId, _profilePhotoFile!, 'display.jpg');
        } catch (_) {}
      }

      if (mounted) {
        ref.invalidate(studentListResultProvider);
        ref.invalidate(paginatedStudentsProvider);
        ref.invalidate(studentsTotalCountProvider);
        ref.invalidate(studentsProvider);
        ref.invalidate(nextAdmissionNumberProvider);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existingStudent == null ? 'Student admitted successfully!' : 'Student updated successfully!'),
            backgroundColor: AppColors.success.base,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Failed to save student record.';
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('admission_number') && (errStr.contains('unique') || errStr.contains('already exists') || errStr.contains('duplicate'))) {
          msg = 'Admission number "$admNumber" is already in use. Please enter a different admission number.';
        } else if (errStr.contains('registration_number') && (errStr.contains('unique') || errStr.contains('already exists') || errStr.contains('duplicate'))) {
          msg = 'University registration number is already registered for another student.';
        } else {
          msg = 'Error saving student: ${e.toString().split('\n').first}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.danger.base,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
