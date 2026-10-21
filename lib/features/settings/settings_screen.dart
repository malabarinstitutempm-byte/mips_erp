import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/services/supabase_service.dart';
import '../../core/services/admin_user_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/status_badge.dart';
import '../backup/backup_service.dart';
import 'record_types_settings.dart';
import 'integrity_check_dialog.dart';
import 'settings_provider.dart';
import 'system_health_view.dart';
import '../exams/grading_scheme_manager.dart';
import '../auth/auth_provider.dart';

class AcademicYearsNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  AcademicYearsNotifier() : super(const AsyncValue.loading()) {
    loadYears();
  }

  static List<Map<String, dynamic>> _fallbackYears = [
    {'id': 3, 'year_name': '2025-2026', 'is_current': false},
    {'id': 2, 'year_name': '2024-2025', 'is_current': true},
    {'id': 1, 'year_name': '2023-2024', 'is_current': false},
  ];

  Future<void> loadYears() async {
    try {
      final client = SupabaseService.instance.client;
      final data = await client
          .from('academic_years')
          .select('*')
          .isFilter('deleted_at', null)
          .order('id', ascending: false);
      final list = (data as List).map((row) => Map<String, dynamic>.from(row)).toList();
      if (list.isNotEmpty) {
        _fallbackYears = list;
      }
      state = AsyncValue.data(List.from(_fallbackYears));
    } catch (_) {
      state = AsyncValue.data(List.from(_fallbackYears));
    }
  }

  Future<void> addYear(String yearName) async {
    try {
      final client = SupabaseService.instance.client;
      await client.from('academic_years').insert({
        'year_name': yearName,
        'is_current': false,
      });
    } catch (_) {}

    final nextId = (_fallbackYears.map((y) => (y['id'] as num?)?.toInt() ?? 0).fold(0, (max, v) => v > max ? v : max)) + 1;
    _fallbackYears.insert(0, {'id': nextId, 'year_name': yearName, 'is_current': false});
    state = AsyncValue.data(List.from(_fallbackYears));
  }

  Future<void> setCurrentYear(int yearId) async {
    try {
      final client = SupabaseService.instance.client;
      await client.from('academic_years').update({'is_current': false}).neq('id', yearId);
      await client.from('academic_years').update({'is_current': true}).eq('id', yearId);
    } catch (_) {}

    _fallbackYears = _fallbackYears.map((y) {
      final copy = Map<String, dynamic>.from(y);
      copy['is_current'] = (copy['id'] == yearId);
      return copy;
    }).toList();
    state = AsyncValue.data(List.from(_fallbackYears));
  }
}

final academicYearsProvider = StateNotifierProvider<AcademicYearsNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return AcademicYearsNotifier();
});

class AdminUsersNotifier extends StateNotifier<AsyncValue<List<AdminAccount>>> {
  AdminUsersNotifier() : super(const AsyncValue.loading()) {
    loadAdmins();
  }

  Future<void> loadAdmins() async {
    try {
      final admins = await AdminUserService.instance.getAdmins();
      state = AsyncValue.data(admins);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createAdmin({
    required String fullName,
    required String username,
    required String password,
    String? email,
    String role = 'Super Administrator',
  }) async {
    await AdminUserService.instance.createAdmin(
      fullName: fullName,
      username: username,
      password: password,
      email: email,
      role: role,
    );
    await loadAdmins();
  }

  Future<void> updatePassword(String id, String newPassword) async {
    await AdminUserService.instance.updatePassword(id, newPassword);
    await loadAdmins();
  }

  Future<void> updateAdmin(String id, {
    String? fullName,
    String? username,
    String? email,
    String? role,
    bool? active,
  }) async {
    await AdminUserService.instance.updateAdmin(
      id,
      fullName: fullName,
      username: username,
      email: email,
      role: role,
      active: active,
    );
    await loadAdmins();
  }

  Future<bool> deleteAdmin(String id) async {
    final success = await AdminUserService.instance.deleteAdmin(id);
    if (success) {
      await loadAdmins();
    }
    return success;
  }
}

final adminUsersProvider = StateNotifierProvider<AdminUsersNotifier, AsyncValue<List<AdminAccount>>>((ref) {
  return AdminUsersNotifier();
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedIndex = 0;
  bool _isSaving = false;
  bool _isTestingConnection = false;
  bool _isInitializedFromSettings = false;

  final _institutionNameCtrl = TextEditingController(text: 'Malabar Institute of Paramedical Science');
  final _institutionAddressCtrl = TextEditingController(text: 'CH Centre, Malappuram, Kerala - 676519');
  final _institutionEmailCtrl = TextEditingController(text: 'office@mipsedu.in');
  final _institutionPhoneCtrl = TextEditingController(text: '+91 98460 00000');
  final _institutionWebsiteCtrl = TextEditingController(text: 'https://mipsedu.in');

  final _receiptPrefixCtrl = TextEditingController(text: 'REC-');
  final _currencySymbolCtrl = TextEditingController(text: '₹');
  final _defaultTuitionFeeCtrl = TextEditingController(text: '35000');
  final _defaultRegFeeCtrl = TextEditingController(text: '5000');

  String _localDocsPath = '';
  String _lastLocalBackup = 'Never';

  @override
  void initState() {
    super.initState();
    _loadLocalStats();
  }

  Future<void> _loadLocalStats() async {
    final docs = await getApplicationDocumentsDirectory();
    final dataDir = Directory(p.join(docs.path, 'MIPS_ERP_Database'));
    if (await dataDir.exists()) {
      _localDocsPath = dataDir.path;
    }

    final backupDir = Directory(p.join(docs.path, 'MIPS_ERP_Database', 'Backups'));
    if (await backupDir.exists()) {
      final files = await backupDir.list().toList();
      final zips = files.whereType<File>().where((f) => f.path.endsWith('.zip')).toList();
      if (zips.isNotEmpty) {
        zips.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        _lastLocalBackup = zips.first.lastModifiedSync().toString().substring(0, 16);
      }
    }
    if (mounted) setState(() {});
  }

  void _syncControllersWithSettings(Map<String, String> settings) {
    if (_isInitializedFromSettings) return;
    if (settings.isNotEmpty) {
      if (settings.containsKey('institution_name')) _institutionNameCtrl.text = settings['institution_name']!;
      if (settings.containsKey('institution_address')) _institutionAddressCtrl.text = settings['institution_address']!;
      if (settings.containsKey('institution_email')) _institutionEmailCtrl.text = settings['institution_email']!;
      if (settings.containsKey('institution_phone')) _institutionPhoneCtrl.text = settings['institution_phone']!;
      if (settings.containsKey('institution_website')) _institutionWebsiteCtrl.text = settings['institution_website']!;

      if (settings.containsKey('receipt_prefix')) _receiptPrefixCtrl.text = settings['receipt_prefix']!;
      if (settings.containsKey('currency_symbol')) _currencySymbolCtrl.text = settings['currency_symbol']!;
      if (settings.containsKey('default_tuition_fee')) _defaultTuitionFeeCtrl.text = settings['default_tuition_fee']!;
      if (settings.containsKey('default_reg_fee')) _defaultRegFeeCtrl.text = settings['default_reg_fee']!;

      _isInitializedFromSettings = true;
    }
  }

  @override
  void dispose() {
    _institutionNameCtrl.dispose();
    _institutionAddressCtrl.dispose();
    _institutionEmailCtrl.dispose();
    _institutionPhoneCtrl.dispose();
    _institutionWebsiteCtrl.dispose();
    _receiptPrefixCtrl.dispose();
    _currencySymbolCtrl.dispose();
    _defaultTuitionFeeCtrl.dispose();
    _defaultRegFeeCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final map = {
      'institution_name': _institutionNameCtrl.text.trim(),
      'institution_address': _institutionAddressCtrl.text.trim(),
      'institution_email': _institutionEmailCtrl.text.trim(),
      'institution_phone': _institutionPhoneCtrl.text.trim(),
      'institution_website': _institutionWebsiteCtrl.text.trim(),
      'receipt_prefix': _receiptPrefixCtrl.text.trim(),
      'currency_symbol': _currencySymbolCtrl.text.trim(),
      'default_tuition_fee': _defaultTuitionFeeCtrl.text.trim(),
      'default_reg_fee': _defaultRegFeeCtrl.text.trim(),
    };

    try {
      await ref.read(settingsProvider.notifier).saveSettings(map);
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settings saved successfully and synced across devices!'),
            backgroundColor: AppColors.success.base,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _testSupabaseConnection() async {
    setState(() => _isTestingConnection = true);
    final ok = await SupabaseService.instance.checkConnectivity();
    if (mounted) {
      setState(() => _isTestingConnection = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Connected to Supabase Cloud Master Database.'
              : 'Unable to reach Supabase Cloud. Check internet connection.'),
          backgroundColor: ok ? AppColors.success.base : Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildNavTile(int index, String title, IconData icon, ColorSet colorSet) {
    final isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? colorSet.base : AppColors.textMuted),
      title: Text(title, style: TextStyle(
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        color: isSelected ? colorSet.base : AppColors.textStrong,
      )),
      selected: isSelected,
      selectedTileColor: colorSet.tint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      onTap: () => setState(() => _selectedIndex = index),
    );
  }

  Widget _buildMobileCategoryChip(int index, String title, IconData icon) {
    final isSelected = _selectedIndex == index;
    return ChoiceChip(
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedIndex = index),
      avatar: Icon(
        icon,
        size: 15,
        color: isSelected ? Colors.white : AppColors.brand,
      ),
      label: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.white : AppColors.textStrong,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
        ),
      ),
      selectedColor: AppColors.brand,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? AppColors.brand : AppColors.border),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSettings = ref.watch(settingsProvider);
    _syncControllersWithSettings(currentSettings);
    final isMobile = MediaQuery.of(context).size.width < 800;

    final contentSection = Stack(
      children: [
        SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 0: Institution Profile
                          if (_selectedIndex == 0) ...[
                            SectionCard(
                              title: 'Institution Profile',
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _institutionNameCtrl,
                                    decoration: const InputDecoration(labelText: 'Institution Name'),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  TextFormField(
                                    controller: _institutionAddressCtrl,
                                    maxLines: 3,
                                    decoration: const InputDecoration(labelText: 'Complete Address'),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  if (isMobile) ...[
                                    TextFormField(
                                      controller: _institutionEmailCtrl,
                                      decoration: const InputDecoration(labelText: 'Contact Email'),
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    TextFormField(
                                      controller: _institutionPhoneCtrl,
                                      decoration: const InputDecoration(labelText: 'Contact Phone'),
                                    ),
                                  ] else ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _institutionEmailCtrl,
                                            decoration: const InputDecoration(labelText: 'Contact Email'),
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.lg),
                                        Expanded(
                                          child: TextFormField(
                                            controller: _institutionPhoneCtrl,
                                            decoration: const InputDecoration(labelText: 'Contact Phone'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: AppSpacing.lg),
                                  TextFormField(
                                    controller: _institutionWebsiteCtrl,
                                    decoration: const InputDecoration(labelText: 'Website URL'),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // 1: Academic Years
                          if (_selectedIndex == 1) ...[
                            _buildAcademicYearsSection(isMobile),
                          ],
                          
                          // 2: Fee & Receipts
                          if (_selectedIndex == 2) ...[
                            SectionCard(
                              title: 'Fee & Receipt Settings',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextFormField(
                                    controller: _receiptPrefixCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Receipt Number Prefix',
                                      hintText: 'e.g., REC-',
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  TextFormField(
                                    controller: _currencySymbolCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Currency Symbol',
                                      hintText: 'e.g., ₹',
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  const Text('Default Fee Structure Templates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  const Text('Default template amounts applied when creating new courses.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                  const SizedBox(height: AppSpacing.md),
                                  if (isMobile) ...[
                                    TextFormField(
                                      controller: _defaultRegFeeCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: 'Default Registration Fee (₹)'),
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    TextFormField(
                                      controller: _defaultTuitionFeeCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: 'Default Tuition Fee (₹)'),
                                    ),
                                  ] else ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _defaultRegFeeCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(labelText: 'Default Registration Fee (₹)'),
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.lg),
                                        Expanded(
                                          child: TextFormField(
                                            controller: _defaultTuitionFeeCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(labelText: 'Default Tuition Fee (₹)'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],

                          // 3: Admin Users
                          if (_selectedIndex == 3) ...[
                            _buildAdminUsersSection(isMobile),
                          ],

                          // 4: Data Management (Backup)
                          if (_selectedIndex == 4) ...[
                            SectionCard(
                              title: 'Cloud Master Database & Backups',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Cloud Backup
                                  const Text('Download Cloud Backup', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Export a complete, timestamped JSON snapshot of all master tables (students, courses, fees, exams, results, and settings) directly from the cloud database.',
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (_) => const AlertDialog(
                                          content: Row(
                                            children: [
                                              CircularProgressIndicator(),
                                              SizedBox(width: 20),
                                              Text('Exporting cloud database dump...'),
                                            ],
                                          ),
                                        ),
                                      );
                                      try {
                                        final path = await BackupService.downloadCloudBackup();
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Cloud backup saved to $path'),
                                              backgroundColor: AppColors.success.base,
                                              duration: const Duration(seconds: 5),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Cloud backup failed: $e'), backgroundColor: Colors.red),
                                          );
                                        }
                                      }
                                    },
                                    icon: const Icon(LucideIcons.downloadCloud, size: 16),
                                    label: const Text('Download Cloud Backup (JSON)'),
                                  ),

                                  const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.xl), child: Divider()),

                                  // Local Documents Backup
                                  const Text('Local Documents Backup', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Create a compressed .zip archive of all locally stored student records, scanned files, and profile photos.',
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (_) => const AlertDialog(
                                          content: Row(
                                            children: [
                                              CircularProgressIndicator(),
                                              SizedBox(width: 20),
                                              Text('Archiving local documents...'),
                                            ],
                                          ),
                                        ),
                                      );
                                      try {
                                        final path = await BackupService.createLocalDocumentsBackup();
                                        _loadLocalStats();
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Local documents archive saved to $path'),
                                              backgroundColor: AppColors.success.base,
                                              duration: const Duration(seconds: 5),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Document archive failed: $e'), backgroundColor: Colors.red),
                                          );
                                        }
                                      }
                                    },
                                    icon: const Icon(LucideIcons.archive, size: 16),
                                    label: const Text('Backup Local Documents (.zip)'),
                                  ),

                                  const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.xl), child: Divider()),

                                  // Cloud Connection Monitor
                                  const Text('Cloud Connection Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Supabase Cloud is the central single source of truth for MIPS ERP. Check real-time connection status below.',
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                                  ),
                                  const SizedBox(height: 12),
                                  ValueListenableBuilder<bool>(
                                    valueListenable: SupabaseService.instance.isOnlineNotifier,
                                    builder: (context, isOnline, _) {
                                      return Container(
                                        padding: const EdgeInsets.all(AppSpacing.md),
                                        decoration: BoxDecoration(
                                          color: isOnline ? AppColors.success.tint : Colors.red.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(AppRadius.control),
                                          border: Border.all(
                                            color: isOnline ? AppColors.success.base.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isOnline ? LucideIcons.cloud : LucideIcons.cloudOff,
                                              color: isOnline ? AppColors.success.base : Colors.red,
                                              size: 24,
                                            ),
                                            const SizedBox(width: AppSpacing.md),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    isOnline ? 'Connected to Supabase Cloud Master' : 'Offline / Disconnected',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w600,
                                                      color: isOnline ? AppColors.success.base : Colors.red,
                                                    ),
                                                  ),
                                                  Text(
                                                    SupabaseService.instance.url.isNotEmpty 
                                                        ? 'Project URL: ${SupabaseService.instance.url}' 
                                                        : 'Connected via configured endpoint',
                                                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: _isTestingConnection ? null : _testSupabaseConnection,
                                              icon: _isTestingConnection 
                                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                                : const Icon(LucideIcons.refreshCw, size: 16),
                                              label: Text(_isTestingConnection ? 'Testing...' : 'Test Connection'),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),

                                  const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.xl), child: Divider()),

                                  // Local Data Integrity
                                  const Text('Local Document Diagnostics', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  const Text('Run a diagnostic check on local files and attachments to detect missing scans or orphaned files.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: () => showDialog(context: context, builder: (_) => const IntegrityCheckDialog()),
                                    icon: const Icon(LucideIcons.shieldCheck, size: 16),
                                    label: const Text('Run Integrity Diagnostics'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          
                          // 5: Student Record Types
                          if (_selectedIndex == 5) ...[
                            const RecordTypesSettingsPanel(),
                          ],

                          // 6: Grading System
                          if (_selectedIndex == 6) ...[
                            const GradingSchemeManagerView(),
                          ],

                          // 7: System Info
                          if (_selectedIndex == 7) ...[
                            SectionCard(
                              title: 'System Information',
                              child: Column(
                                children: [
                                  const ListTile(title: Text('App Version'), trailing: Text('2.0.0 (Cloud Master)')),
                                  const Divider(),
                                  const ListTile(title: Text('Backend Database'), trailing: Text('Supabase Cloud (PostgreSQL 15)')),
                                  const Divider(),
                                  const ListTile(title: Text('Architecture'), trailing: Text('Single Cloud Master, Local Documents')),
                                  const Divider(),
                                  ListTile(title: const Text('Local Data Folder'), subtitle: Text(_localDocsPath)),
                                  const Divider(),
                                  ListTile(title: const Text('Last Local Documents Backup'), trailing: Text(_lastLocalBackup)),
                                ],
                              ),
                            ),
                          ],

                          // 8: System Health & Quotas
                          if (_selectedIndex == 8) ...[
                            const SystemHealthView(),
                          ],
                        ],
                      ),
                    ),
                    
                    // Save Button Floating for settings tabs
                    if (_selectedIndex == 0 || _selectedIndex == 2)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                            border: Border(top: BorderSide(color: AppColors.border)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ElevatedButton(
                                onPressed: _isSaving ? null : _saveSettings,
                                child: _isSaving
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Save Changes'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'Settings',
          subtitle: 'Manage institution profile, academic years, database backups, and system preferences',
        ),
        if (isMobile) ...[
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildMobileCategoryChip(0, 'Profile', LucideIcons.building),
                const SizedBox(width: 6),
                _buildMobileCategoryChip(1, 'Academic Years', LucideIcons.calendar),
                const SizedBox(width: 6),
                _buildMobileCategoryChip(2, 'Fees & Receipts', LucideIcons.receipt),
                const SizedBox(width: 6),
                _buildMobileCategoryChip(3, 'Admin Users', LucideIcons.shieldCheck),
                const SizedBox(width: 6),
                _buildMobileCategoryChip(4, 'Data Backup', LucideIcons.database),
                const SizedBox(width: 6),
                _buildMobileCategoryChip(5, 'Record Types', LucideIcons.files),
                const SizedBox(width: 6),
                _buildMobileCategoryChip(6, 'Grading', LucideIcons.award),
                const SizedBox(width: 6),
                _buildMobileCategoryChip(7, 'System Info', LucideIcons.info),
                const SizedBox(width: 6),
                _buildMobileCategoryChip(8, 'Health & Quotas', LucideIcons.activity),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: contentSection),
        ] else ...[
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 260,
                  child: Column(
                    children: [
                      _buildNavTile(0, 'Institution Profile', LucideIcons.building, AppColors.students),
                      _buildNavTile(1, 'Academic Years', LucideIcons.calendar, AppColors.courses),
                      _buildNavTile(2, 'Fee & Receipts', LucideIcons.receipt, AppColors.fees),
                      _buildNavTile(3, 'Administrator Users', LucideIcons.shieldCheck, AppColors.courses),
                      _buildNavTile(4, 'Data Management', LucideIcons.database, AppColors.settings),
                      _buildNavTile(5, 'Student Record Types', LucideIcons.files, AppColors.documents),
                      _buildNavTile(6, 'Grading System', LucideIcons.award, AppColors.exams),
                      _buildNavTile(7, 'System Info', LucideIcons.info, AppColors.reports),
                      _buildNavTile(8, 'System Health & Quotas', LucideIcons.activity, AppColors.success),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xxl),
                Expanded(child: contentSection),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAcademicYearsSection(bool isMobile) {
    final yearsAsync = ref.watch(academicYearsProvider);

    return SectionCard(
      title: 'Academic Years',
      trailing: isMobile ? null : ElevatedButton.icon(
        onPressed: () => _showAddAcademicYearDialog(),
        icon: const Icon(LucideIcons.plus, size: 16),
        label: const Text('Add Academic Year'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showAddAcademicYearDialog(),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add Academic Year'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Text('Manage institution academic cycles and active year configuration.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: AppSpacing.md),
          yearsAsync.when(
            data: (years) {
              if (years.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No academic years found. Click "Add Academic Year" to create one.')),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: years.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final y = years[i];
                  final isCurrent = y['is_current'] == true;
                  final yearName = y['year_name']?.toString() ?? 'N/A';
                  final yearId = (y['id'] as num?)?.toInt() ?? (i + 1);

                  final isMobile = MediaQuery.of(context).size.width < 600;

                  if (isMobile) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  yearName,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              StatusBadge(
                                text: isCurrent ? 'Active Cycle' : 'Past / Future',
                                status: isCurrent ? BadgeStatus.success : BadgeStatus.draft,
                              ),
                            ],
                          ),
                          if (!isCurrent) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                icon: const Icon(Icons.check_circle_outline, size: 16),
                                label: const Text('Set as Current'),
                                onPressed: () async {
                                  await ref.read(academicYearsProvider.notifier).setCurrentYear(yearId);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Academic cycle set to $yearName.')),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return ListTile(
                    title: Text(yearName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusBadge(
                          text: isCurrent ? 'Active Cycle' : 'Past / Future',
                          status: isCurrent ? BadgeStatus.success : BadgeStatus.draft,
                        ),
                        const SizedBox(width: 12),
                        if (!isCurrent)
                          TextButton(
                            onPressed: () async {
                              await ref.read(academicYearsProvider.notifier).setCurrentYear(yearId);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Academic cycle set to $yearName.')),
                                );
                              }
                            },
                            child: const Text('Set as Current'),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text('Failed to load academic years: $e')),
          ),
        ],
      ),
    );
  }

  void _showAddAcademicYearDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Academic Year'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Academic Year Name',
            hintText: 'e.g., 2026-2027',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final val = ctrl.text.trim();
              if (val.isEmpty) return;
              await ref.read(academicYearsProvider.notifier).addYear(val);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Academic cycle "$val" added successfully!'),
                    backgroundColor: AppColors.success.base,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminUsersSection(bool isMobile) {
    final adminsAsync = ref.watch(adminUsersProvider);
    final authState = ref.watch(authProvider);
    final currentUserId = authState.user?.id;
    final currentUserEmail = authState.email.trim().toLowerCase();
    final currentUserName = authState.displayName.trim().toLowerCase();

    return SectionCard(
      title: 'Administrator Accounts',
      trailing: isMobile ? null : ElevatedButton.icon(
        onPressed: () => _showAddAdminDialog(context),
        icon: const Icon(LucideIcons.userPlus, size: 16),
        label: const Text('Add Administrator'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showAddAdminDialog(context),
                icon: const Icon(LucideIcons.userPlus, size: 16),
                label: const Text('Add Administrator'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            'Users with administrative access to manage institution settings, academics, exams, and student records.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.md),
          adminsAsync.when(
            data: (admins) {
              if (admins.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No admin accounts found.')),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: admins.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final a = admins[i];
                  final name = a.fullName;
                  final username = a.username;
                  final email = a.email;
                  final active = a.active;
                  final lastLogin = a.lastLoginAt ?? 'Never';
                  final isSuper = a.role.toLowerCase().contains('super');

                  final isCurrentUser = (currentUserId != null && a.id == currentUserId) ||
                      (currentUserEmail.isNotEmpty && (a.email.toLowerCase() == currentUserEmail || a.username.toLowerCase() == currentUserEmail.split('@').first)) ||
                      (currentUserName.isNotEmpty && a.fullName.toLowerCase() == currentUserName);

                  if (isMobile) {
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isCurrentUser
                                    ? AppColors.brand.withValues(alpha: 0.15)
                                    : (isSuper ? AppColors.brand.withValues(alpha: 0.12) : AppColors.courses.tint),
                                child: Icon(
                                  isCurrentUser
                                      ? LucideIcons.userCheck
                                      : (isSuper ? LucideIcons.shieldAlert : LucideIcons.user),
                                  color: isCurrentUser
                                      ? AppColors.brand
                                      : (isSuper ? AppColors.brand : AppColors.courses.base),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        if (isCurrentUser)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(10)),
                                            child: const Text('You', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                                          ),
                                      ],
                                    ),
                                    Text('@ • ', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(LucideIcons.moreVertical, size: 18),
                                onSelected: (val) {
                                  if (val == 'password') _showChangePasswordDialog(context, a);
                                  if (val == 'edit') _showEditAdminDialog(context, a);
                                  if (val == 'delete') _confirmDeleteAdmin(context, a, isCurrentUser: isCurrentUser);
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(value: 'password', child: Row(children: [Icon(LucideIcons.keyRound, size: 16), SizedBox(width: 8), Text('Change Password')])),
                                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(LucideIcons.edit3, size: 16), SizedBox(width: 8), Text('Edit Details')])),
                                  PopupMenuItem(value: 'delete', child: Row(children: [Icon(LucideIcons.trash2, size: 16, color: Colors.red), const SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSuper ? AppColors.brand.withValues(alpha: 0.1) : AppColors.surface,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: isSuper ? AppColors.brand.withValues(alpha: 0.3) : AppColors.border),
                                ),
                                child: Text(a.role, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: isSuper ? AppColors.brand : AppColors.textMuted)),
                              ),
                              const SizedBox(width: 8),
                              StatusBadge(
                                text: active ? 'Active' : 'Disabled',
                                status: active ? BadgeStatus.success : BadgeStatus.danger,
                              ),
                              const Spacer(),
                              Text(isCurrentUser ? 'Active' : 'Login: ', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            ],
                          ),
                        ],
                      ),
                    );
                  }

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    tileColor: isCurrentUser ? AppColors.brand.withValues(alpha: 0.04) : null,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                    leading: Container(
                      decoration: isCurrentUser ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.brand, width: 2),
                      ) : null,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: isCurrentUser
                            ? AppColors.brand.withValues(alpha: 0.15)
                            : (isSuper ? AppColors.brand.withValues(alpha: 0.12) : AppColors.courses.tint),
                        child: Icon(
                          isCurrentUser
                              ? LucideIcons.userCheck
                              : (isSuper ? LucideIcons.shieldAlert : LucideIcons.user),
                          color: isCurrentUser
                              ? AppColors.brand
                              : (isSuper ? AppColors.brand : AppColors.courses.base),
                          size: 20,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brand,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.user, size: 10, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'You',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSuper
                                ? AppColors.brand.withValues(alpha: 0.1)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSuper
                                  ? AppColors.brand.withValues(alpha: 0.3)
                                  : AppColors.border,
                            ),
                          ),
                          child: Text(
                            a.role,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSuper ? AppColors.brand : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Username: @$username  •  Email: $email  •  ${isCurrentUser ? "Active Current Session" : "Last Login: $lastLogin"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isCurrentUser ? AppColors.brand : AppColors.textMuted,
                          fontWeight: isCurrentUser ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusBadge(
                          text: active ? 'Active' : 'Disabled',
                          status: active ? BadgeStatus.success : BadgeStatus.danger,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(LucideIcons.keyRound, size: 18),
                          tooltip: 'Change Password (on-screen)',
                          onPressed: () => _showChangePasswordDialog(context, a),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.edit3, size: 18),
                          tooltip: 'Edit Administrator',
                          onPressed: () => _showEditAdminDialog(context, a),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, size: 18, color: Colors.red),
                          tooltip: isCurrentUser ? 'Remove Administrator (Current User)' : 'Remove Administrator',
                          onPressed: () => _confirmDeleteAdmin(context, a, isCurrentUser: isCurrentUser),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text('Failed to load administrators: $e')),
          ),
        ],
      ),
    );
  }

  void _showAddAdminDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    String selectedRole = 'Super Administrator';
    bool obscurePassword = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          title: const Row(
            children: [
              Icon(LucideIcons.userPlus, color: AppColors.brand, size: 22),
              SizedBox(width: 10),
              Text('Add Administrator Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(color: AppColors.brand.withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        children: [
                          Icon(LucideIcons.shieldCheck, size: 20, color: AppColors.brand),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Direct Password Setup: Set the login password directly here. The administrator can log in immediately using these credentials without any temporary passwords or activation emails.',
                              style: TextStyle(fontSize: 12, color: AppColors.textStrong),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        hintText: 'e.g. Dr. Salim PK',
                        prefixIcon: Icon(LucideIcons.user, size: 18),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter full name' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Username / Login ID *',
                        hintText: 'e.g. salim / office_head',
                        prefixIcon: Icon(LucideIcons.atSign, size: 18),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Please enter username';
                        if (v.trim().contains(' ')) return 'Username cannot contain spaces';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Email Address (Optional)',
                        hintText: 'e.g. salim@mipsedu.in',
                        prefixIcon: Icon(LucideIcons.mail, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Privilege Role *',
                        prefixIcon: Icon(LucideIcons.shield, size: 18),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Super Administrator',
                          child: Text('Super Administrator (Full System Control)'),
                        ),
                        DropdownMenuItem(
                          value: 'Office Administrator',
                          child: Text('Office Administrator (Desk & Management)'),
                        ),
                      ],
                      onChanged: (v) => setDialogState(() => selectedRole = v!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: passwordCtrl,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password (Permanent) *',
                        hintText: 'Enter direct login password',
                        prefixIcon: const Icon(LucideIcons.lock, size: 18),
                        suffixIcon: IconButton(
                          icon: Icon(obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
                          onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Please set a password';
                        if (v.length < 4) return 'Password must be at least 4 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmPasswordCtrl,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password *',
                        hintText: 'Re-enter password to confirm',
                        prefixIcon: const Icon(LucideIcons.checkCircle2, size: 18),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirm ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
                          onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                        ),
                      ),
                      validator: (v) {
                        if (v != passwordCtrl.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(LucideIcons.check, size: 16),
              label: const Text('Create Administrator'),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final name = nameCtrl.text.trim();
                final username = usernameCtrl.text.trim();
                final email = emailCtrl.text.trim();
                final password = passwordCtrl.text;
                Navigator.pop(dialogCtx);

                await ref.read(adminUsersProvider.notifier).createAdmin(
                  fullName: name,
                  username: username,
                  password: password,
                  email: email.isNotEmpty ? email : null,
                  role: selectedRole,
                );

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Administrator "$name" (@$username) created successfully with permanent password!'),
                    backgroundColor: AppColors.success.base,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, AdminAccount admin) {
    final formKey = GlobalKey<FormState>();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool obscureNew = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          title: Row(
            children: [
              const Icon(LucideIcons.keyRound, color: AppColors.brand, size: 20),
              const SizedBox(width: 10),
              Flexible(child: Text('Change Password for ${admin.fullName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Direct Password Update: The password is updated immediately on this screen. No temporary password or confirmation link is required.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: newPassCtrl,
                    obscureText: obscureNew,
                    decoration: InputDecoration(
                      labelText: 'New Password *',
                      prefixIcon: const Icon(LucideIcons.lock, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(obscureNew ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
                        onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Please enter a new password';
                      if (v.length < 4) return 'Password must be at least 4 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmPassCtrl,
                    obscureText: obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password *',
                      prefixIcon: const Icon(LucideIcons.checkCircle2, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirm ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
                        onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v != newPassCtrl.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogCtx);
                await ref.read(adminUsersProvider.notifier).updatePassword(admin.id, newPassCtrl.text);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Password for administrator "${admin.fullName}" updated successfully!'),
                    backgroundColor: AppColors.success.base,
                  ),
                );
              },
              child: const Text('Update Password'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditAdminDialog(BuildContext context, AdminAccount admin) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: admin.fullName);
    final usernameCtrl = TextEditingController(text: admin.username);
    final emailCtrl = TextEditingController(text: admin.email);
    String selectedRole = admin.role;
    bool isActive = admin.active;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          title: Row(
            children: [
              const Icon(LucideIcons.edit3, color: AppColors.brand, size: 20),
              const SizedBox(width: 10),
              Flexible(child: Text('Edit Administrator: ${admin.fullName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(LucideIcons.user, size: 18)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter full name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(labelText: 'Username *', prefixIcon: Icon(LucideIcons.atSign, size: 18)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter username' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(LucideIcons.mail, size: 18)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(LucideIcons.shield, size: 18)),
                    items: const [
                      DropdownMenuItem(value: 'Super Administrator', child: Text('Super Administrator')),
                      DropdownMenuItem(value: 'Office Administrator', child: Text('Office Administrator')),
                    ],
                    onChanged: (v) => setDialogState(() => selectedRole = v!),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Account Active'),
                    subtitle: Text(isActive ? 'User can log in' : 'User is locked out', style: const TextStyle(fontSize: 12)),
                    value: isActive,
                    onChanged: (v) => setDialogState(() => isActive = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogCtx);
                await ref.read(adminUsersProvider.notifier).updateAdmin(
                  admin.id,
                  fullName: nameCtrl.text.trim(),
                  username: usernameCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  role: selectedRole,
                  active: isActive,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Administrator "${nameCtrl.text.trim()}" updated successfully!'), backgroundColor: AppColors.success.base),
                );
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAdmin(BuildContext context, AdminAccount admin, {bool isCurrentUser = false}) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(
          children: [
            const Icon(LucideIcons.alertTriangle, color: Colors.red, size: 22),
            const SizedBox(width: 10),
            Text(isCurrentUser ? 'Remove Your Account?' : 'Remove Administrator?'),
          ],
        ),
        content: Text(
          isCurrentUser
              ? 'Warning: You are currently logged in with this account (@${admin.username}).\n\nIf you remove this account, your administrative privileges will be revoked and you will be signed out immediately.'
              : 'Are you sure you want to remove administrator "${admin.fullName}" (@${admin.username})?\n\nThis account will be permanently revoked and unable to log in.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final deleted = await ref.read(adminUsersProvider.notifier).deleteAdmin(admin.id);
              if (!context.mounted) return;
              if (deleted) {
                if (isCurrentUser) {
                  ref.read(authProvider.notifier).logout(reason: 'Your administrator account was removed.');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Administrator "${admin.fullName}" has been removed.'), backgroundColor: Colors.red),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cannot remove the only remaining active administrator account.'), backgroundColor: Colors.orange),
                );
              }
            },
            child: Text(isCurrentUser ? 'Remove & Sign Out' : 'Remove Admin'),
          ),
        ],
      ),
    );
  }
}
