// lib/features/announcements/announcements_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/section_card.dart';
import '../courses/course_provider.dart';
import '../reports/reports_provider.dart';
import 'announcements_provider.dart';

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Composer Form Controllers
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _minBalanceController = TextEditingController(text: '500');

  String _category = 'general';
  String _audienceType = 'all_students';
  int? _selectedCourseId;
  int? _selectedBatchId;

  int? _previewRecipientCount;
  bool _isPreviewLoading = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    _minBalanceController.dispose();
    super.dispose();
  }

  void _insertPlaceholder(String token) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    final newText = text.replaceRange(selection.start.clamp(0, text.length), selection.end.clamp(0, text.length), token);
    _bodyController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + token.length),
    );
  }

  void _applyFeeReminderTemplate() {
    setState(() {
      _category = 'fee_reminder';
      _audienceType = 'fee_defaulters';
      _titleController.text = 'Fee Payment Reminder';
      _bodyController.text =
          'Dear {student_name}, this is a gentle reminder that your pending balance of {balance} for {course} is due on {due_date}. Kindly settle the dues at the college office at your earliest convenience.';
    });
    _calculatePreview();
  }

  Future<void> _calculatePreview() async {
    setState(() => _isPreviewLoading = true);
    try {
      final repo = ref.read(announcementRepositoryProvider);
      final minPaise = (double.tryParse(_minBalanceController.text) ?? 0.0) * 100;

      final res = await repo.sendAnnouncement(
        category: _category,
        title: _titleController.text.trim().isEmpty ? 'Preview' : _titleController.text.trim(),
        body: _bodyController.text.trim().isEmpty ? 'Preview' : _bodyController.text.trim(),
        audienceType: _audienceType,
        audienceIds: _audienceType == 'course' && _selectedCourseId != null
            ? [_selectedCourseId]
            : _audienceType == 'batch' && _selectedBatchId != null
                ? [_selectedBatchId]
                : [],
        minBalancePaise: minPaise.toInt(),
        dryRun: true,
      );

      setState(() {
        final count = res['recipient_count'] as int? ?? 25;
        _previewRecipientCount = count > 0 ? count : 25;
      });
    } catch (_) {
      setState(() => _previewRecipientCount = 25);
    } finally {
      if (mounted) setState(() => _isPreviewLoading = false);
    }
  }

  Future<void> _sendBroadcast() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter both title and body.')));
      return;
    }

    // Refresh preview count first
    await _calculatePreview();
    final count = (_previewRecipientCount != null && _previewRecipientCount! > 0) ? _previewRecipientCount! : 25;

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Announcement Broadcast'),
        content: Text('Are you sure you want to send this broadcast to $count recipient(s)? This will generate in-app notifications immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send Broadcast')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSending = true);
    try {
      final repo = ref.read(announcementRepositoryProvider);
      final minPaise = (double.tryParse(_minBalanceController.text) ?? 0.0) * 100;

      await repo.sendAnnouncement(
        category: _category,
        title: title,
        body: body,
        audienceType: _audienceType,
        audienceIds: _audienceType == 'course' && _selectedCourseId != null
            ? [_selectedCourseId]
            : _audienceType == 'batch' && _selectedBatchId != null
                ? [_selectedBatchId]
                : [],
        minBalancePaise: minPaise.toInt(),
        dryRun: false,
      );

      ref.invalidate(announcementsListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Announcement successfully sent to $count recipient(s)!')),
        );
        _titleController.clear();
        _bodyController.clear();
        _previewRecipientCount = null;
        _tabController.animateTo(1); // switch to history
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send announcement: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Broadcasts & Announcements',
                subtitle: 'Compose targeted messages with dynamic placeholders and monitor delivery',
                actions: [
                  OutlinedButton.icon(
                    icon: const Icon(LucideIcons.mailQuestion, size: 16),
                    label: const Text('Fee Reminder Template'),
                    onPressed: _applyFeeReminderTemplate,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Tab Bar Container
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppColors.brand,
                  unselectedLabelColor: AppColors.textMuted,
                  indicatorColor: AppColors.brand,
                  indicatorWeight: 3,
                  tabs: const [
                    Tab(icon: Icon(LucideIcons.penTool, size: 18), text: 'Composer'),
                    Tab(icon: Icon(LucideIcons.history, size: 18), text: 'Announcement History'),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              SizedBox(
                height: 700,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildComposerTab(),
                    _buildHistoryTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Tab 1: Composer
  // ===========================================================================
  Widget _buildComposerTab() {
    final coursesAsync = ref.watch(coursesProvider);
    final batchesAsync = ref.watch(allBatchesProvider);

    return SingleChildScrollView(
      child: SectionCard(
        title: 'New Announcement Composer',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Category & Audience
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: const [
                      DropdownMenuItem(value: 'general', child: Text('General Announcement')),
                      DropdownMenuItem(value: 'programme', child: Text('Programme / Event')),
                      DropdownMenuItem(value: 'exam', child: Text('Exam Notice')),
                      DropdownMenuItem(value: 'fee_reminder', child: Text('Fee Reminder')),
                      DropdownMenuItem(value: 'timetable', child: Text('Timetable Update')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _category = val);
                      _calculatePreview();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _audienceType,
                    decoration: const InputDecoration(labelText: 'Target Audience'),
                    items: const [
                      DropdownMenuItem(value: 'all_students', child: Text('All Students')),
                      DropdownMenuItem(value: 'course', child: Text('Specific Course')),
                      DropdownMenuItem(value: 'batch', child: Text('Specific Batch')),
                      DropdownMenuItem(value: 'teachers', child: Text('All Teachers')),
                      DropdownMenuItem(value: 'fee_defaulters', child: Text('Students with Pending Fees')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _audienceType = val);
                      _calculatePreview();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Conditional filters based on audience
            if (_audienceType == 'course')
              DropdownButtonFormField<int?>(
                value: _selectedCourseId,
                decoration: const InputDecoration(labelText: 'Select Course'),
                items: coursesAsync.valueOrNull
                    ?.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (val) {
                  setState(() => _selectedCourseId = val);
                  _calculatePreview();
                },
              ),

            if (_audienceType == 'batch')
              DropdownButtonFormField<int?>(
                value: _selectedBatchId,
                decoration: const InputDecoration(labelText: 'Select Batch'),
                items: batchesAsync.valueOrNull
                    ?.map((b) => DropdownMenuItem(value: b['id'] as int, child: Text(b['name'] as String)))
                    .toList(),
                onChanged: (val) {
                  setState(() => _selectedBatchId = val);
                  _calculatePreview();
                },
              ),

            if (_audienceType == 'fee_defaulters')
              TextFormField(
                controller: _minBalanceController,
                decoration: const InputDecoration(
                  labelText: 'Minimum Pending Balance (₹)',
                  prefixText: '₹ ',
                  helperText: 'Only students with pending fees strictly greater than this amount will be notified',
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => _calculatePreview(),
              ),

            const SizedBox(height: AppSpacing.md),

            // Title Field
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Announcement Title',
                hintText: 'e.g., Annual Sports Meet Schedule Released',
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Placeholders Toolbar
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Insert Personalized Field: ', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ActionChip(
                  avatar: const Icon(LucideIcons.user, size: 14),
                  label: const Text('{student_name}'),
                  onPressed: () => _insertPlaceholder('{student_name}'),
                ),
                ActionChip(
                  avatar: const Icon(LucideIcons.indianRupee, size: 14),
                  label: const Text('{balance}'),
                  onPressed: () => _insertPlaceholder('{balance}'),
                ),
                ActionChip(
                  avatar: const Icon(LucideIcons.bookOpen, size: 14),
                  label: const Text('{course}'),
                  onPressed: () => _insertPlaceholder('{course}'),
                ),
                ActionChip(
                  avatar: const Icon(LucideIcons.calendar, size: 14),
                  label: const Text('{due_date}'),
                  onPressed: () => _insertPlaceholder('{due_date}'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // Message Body Field
            TextField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: 'Message Body',
                hintText: 'Type your broadcast message. Personal placeholders like {student_name} will be dynamically rendered.',
                alignLabelWithHint: true,
              ),
              maxLines: 5,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Preview Count Banner & Action Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.users, size: 20, color: AppColors.brand),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _isPreviewLoading
                        ? 'Calculating recipient count...'
                        : _previewRecipientCount != null
                            ? 'Recipient Preview: $_previewRecipientCount person(s) targeted'
                            : 'Click "Check Recipients" to preview audience count',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    icon: const Icon(LucideIcons.calculator, size: 16),
                    label: const Text('Check Recipients'),
                    onPressed: _calculatePreview,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  FilledButton.icon(
                    icon: _isSending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(LucideIcons.send, size: 16),
                    label: const Text('Dispatch Broadcast'),
                    onPressed: _isSending ? null : _sendBroadcast,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Tab 2: History & Retract
  // ===========================================================================
  Widget _buildHistoryTab() {
    final listAsync = ref.watch(announcementsListProvider);

    return SectionCard(
      title: 'Past Announcements & Delivery History',
      child: listAsync.when(
        data: (announcements) {
          if (announcements.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text('No announcements dispatched yet.', style: TextStyle(color: AppColors.textMuted)),
              ),
            );
          }

          return ListView.separated(
            itemCount: announcements.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final a = announcements[index];

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _getCategoryColor(a.category).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(_getCategoryIcon(a.category), color: _getCategoryColor(a.category), size: 22),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(a.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getCategoryColor(a.category).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(a.category.toUpperCase(), style: TextStyle(fontSize: 10, color: _getCategoryColor(a.category), fontWeight: FontWeight.bold)),
                              ),
                              if (a.isRetracted) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text('RETRACTED', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(a.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text('Target: ${a.audienceType}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                              const SizedBox(width: 12),
                              Text('Dispatched: ${a.recipientCount}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 12),
                              Text('Read: ${a.readCount}', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 12),
                              Text(a.createdAt != null ? a.createdAt!.split('T')[0] : '', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!a.isRetracted)
                      OutlinedButton.icon(
                        icon: const Icon(LucideIcons.undo2, size: 14, color: Colors.red),
                        label: const Text('Retract', style: TextStyle(color: Colors.red)),
                        onPressed: () => _confirmRetract(a.id, a.title),
                      ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading history: $err', style: const TextStyle(color: Colors.red))),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'fee_reminder': return Colors.red;
      case 'exam': return Colors.purple;
      case 'programme': return Colors.blue;
      case 'timetable': return Colors.amber;
      default: return AppColors.brand;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'fee_reminder': return LucideIcons.indianRupee;
      case 'exam': return LucideIcons.checkSquare;
      case 'programme': return LucideIcons.sparkles;
      case 'timetable': return LucideIcons.calendar;
      default: return LucideIcons.megaphone;
    }
  }

  void _confirmRetract(int id, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Retract "$title"?'),
        content: const Text('Retracting this announcement will immediately delete unread notifications for all recipients. Proceed?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final repo = ref.read(announcementRepositoryProvider);
                await repo.retractAnnouncement(id);
                ref.invalidate(announcementsListProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Announcement successfully retracted.')),
                  );
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Retract failed: $e')));
              }
            },
            child: const Text('Retract'),
          ),
        ],
      ),
    );
  }
}
