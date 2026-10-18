abstract class SettingsRepository {
  Future<String?> getSetting(String key);

  Future<void> setSetting(String key, String value, {String? description});

  Future<Map<String, String>> getAllSettings();
  Future<void> saveAllSettings(Map<String, String> settings);
}
