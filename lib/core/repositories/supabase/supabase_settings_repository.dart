import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../interfaces/settings_repository_interface.dart';

class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseClient get _client => SupabaseService.instance.client;

  static const Map<String, String> defaultSettings = {
    'institution_name': 'Malabar Institute of Paramedical Science',
    'institution_address': 'CH Centre, Malappuram, Kerala - 676519',
    'institution_phone': '9847123456',
    'institution_email': 'info@mips.edu.in',
    'institution_website': 'https://mips.edu.in',
    'receipt_prefix': 'MIPS/REC/',
    'currency_symbol': '₹',
    'default_tuition_fee': '50000',
    'default_reg_fee': '5000',
    'completed_access_months': '3',
    'min_attendance_percent': '75',
  };

  final Map<String, String> _cache = Map<String, String>.from(defaultSettings);

  @override
  Future<String?> getSetting(String key) async {
    try {
      final data = await _client
          .from('settings')
          .select('value')
          .eq('key', key)
          .maybeSingle();

      if (data != null && data['value'] != null) {
        final val = data['value'].toString();
        _cache[key] = val;
        return val;
      }
      return _cache[key] ?? defaultSettings[key];
    } catch (e) {
      debugPrint('SupabaseSettingsRepository.getSetting fallback: $e');
      return _cache[key] ?? defaultSettings[key];
    }
  }

  @override
  Future<void> setSetting(String key, String value, {String? description}) async {
    _cache[key] = value;
    try {
      SupabaseService.instance.assertCanWrite('update setting');

      await _client.from('settings').upsert({
        'key': key,
        'value': value,
        if (description != null) 'description': description,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('SupabaseSettingsRepository.setSetting cached locally: $e');
    }
  }

  @override
  Future<Map<String, String>> getAllSettings() async {
    try {
      final data = await _client
          .from('settings')
          .select('key, value');

      if (data is List) {
        for (final row in data) {
          if (row['key'] != null && row['value'] != null) {
            _cache[row['key'].toString()] = row['value'].toString();
          }
        }
      }
      return Map<String, String>.from(_cache);
    } catch (e) {
      debugPrint('SupabaseSettingsRepository.getAllSettings using fallback defaults: $e');
      return Map<String, String>.from(_cache);
    }
  }

  @override
  Future<void> saveAllSettings(Map<String, String> settings) async {
    _cache.addAll(settings);
    if (settings.isEmpty) return;

    try {
      SupabaseService.instance.assertCanWrite('update settings');

      final now = DateTime.now().toIso8601String();
      final rows = settings.entries.map((e) => {
        'key': e.key,
        'value': e.value,
        'updated_at': now,
      }).toList();

      await _client.from('settings').upsert(rows);
    } catch (e) {
      debugPrint('SupabaseSettingsRepository.saveAllSettings cached locally: $e');
    }
  }
}
