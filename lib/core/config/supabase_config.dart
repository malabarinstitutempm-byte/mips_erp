import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/perf_logger.dart';

class SupabaseConfig {
  static const String defaultUrl = 'https://evzehywyyqmcktszwmeg.supabase.co';
  static const String defaultAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV2emVoeXd5eXFtY2t0c3p3bWVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NjM0MTYsImV4cCI6MjEwNzUzOTQxNn0.xNfdyP9f9if2INEdDdzGR4U04oItnt8XVhdM1-2Jnk4';

  static const _storage = FlutterSecureStorage();

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    String url = const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    String anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

    if (url.isEmpty || anonKey.isEmpty) {
      try {
        final storedUrl = await _storage.read(key: 'supabase_url');
        final storedKey = await _storage.read(key: 'supabase_anon_key');
        if (storedUrl != null && storedUrl.isNotEmpty) url = storedUrl;
        if (storedKey != null && storedKey.isNotEmpty) anonKey = storedKey;
      } catch (_) {}
    }

    if (url.isEmpty) url = defaultUrl;
    if (anonKey.isEmpty) anonKey = defaultAnonKey;

    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      httpClient: kDebugMode ? PerfLoggingHttpClient() : null,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }
}
