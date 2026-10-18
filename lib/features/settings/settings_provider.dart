import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/repositories/interfaces/settings_repository_interface.dart';
import '../../core/repositories/supabase/supabase_settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => SupabaseSettingsRepository());

final settingsProvider = StateNotifierProvider<SettingsNotifier, Map<String, String>>((ref) {
  return SettingsNotifier(ref.read(settingsRepositoryProvider));
});

class SettingsNotifier extends StateNotifier<Map<String, String>> {
  final SettingsRepository _repository;

  SettingsNotifier(this._repository) : super({}) {
    loadSettings();
  }

  Future<void> loadSettings() async {
    try {
      final settings = await _repository.getAllSettings();
      state = settings;
    } catch (_) {}
  }

  Future<void> saveSettings(Map<String, String> newSettings) async {
    await _repository.saveAllSettings(newSettings);
    state = {...state, ...newSettings};
  }
}
