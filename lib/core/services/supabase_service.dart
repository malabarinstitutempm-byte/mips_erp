import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class OfflineException implements Exception {
  final String message;
  OfflineException(this.message);

  @override
  String toString() => message;
}

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  static const _storage = FlutterSecureStorage();

  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);
  Timer? _connectivityTimer;
  bool _isCheckingConnectivity = false;

  String _url = '';
  String _anonKey = '';

  String get url => _url;
  String get anonKey => _anonKey;

  bool get isOnline => isOnlineNotifier.value;
  SupabaseClient get client => Supabase.instance.client;

  Stream<AuthState> get authStateStream => client.auth.onAuthStateChange;

  User? get currentUser => client.auth.currentUser;
  Session? get currentSession => client.auth.currentSession;

  /// Initializes Supabase Cloud connection and starts connectivity monitoring
  Future<void> initialize() async {
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

    if (url.isEmpty) url = SupabaseConfig.defaultUrl;
    if (anonKey.isEmpty) anonKey = SupabaseConfig.defaultAnonKey;

    _url = url;
    _anonKey = anonKey;

    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
      ),
    );

    // Initial network connectivity probe
    await checkConnectivity();

    // Start periodic background connectivity probe (every 8 seconds)
    _connectivityTimer?.cancel();
    _connectivityTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      checkConnectivity();
    });
  }

  /// Web-safe connectivity verification by pinging Supabase health endpoint
  Future<bool> checkConnectivity() async {
    if (_isCheckingConnectivity) return isOnline;
    _isCheckingConnectivity = true;

    try {
      if (kIsWeb) {
        // On web browser, cross-origin XMLHttpRequest to rest/v1 can fail due to CORS.
        // We consider the client online to enable normal app functionality.
        if (isOnlineNotifier.value != true) {
          isOnlineNotifier.value = true;
        }
        return true;
      }

      final uri = Uri.parse('$_url/rest/v1/');
      final response = await http
          .get(uri, headers: {'apikey': _anonKey})
          .timeout(const Duration(seconds: 4));

      final onlineNow = response.statusCode == 200 || response.statusCode == 404;
      if (isOnlineNotifier.value != onlineNow) {
        isOnlineNotifier.value = onlineNow;
      }
      return onlineNow;
    } catch (_) {
      if (isOnlineNotifier.value != false) {
        isOnlineNotifier.value = false;
      }
      return false;
    } finally {
      _isCheckingConnectivity = false;
    }
  }

  /// Guards write operations when offline
  void assertCanWrite(String operationName) {
    if (!isOnline) {
      throw OfflineException(
        'Cannot $operationName while offline. All changes require an active internet connection to preserve database integrity.',
      );
    }
  }

  void dispose() {
    _connectivityTimer?.cancel();
  }
}

/// Unobtrusive Connectivity Banner
class OfflineBanner extends StatelessWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SupabaseService.instance.isOnlineNotifier,
      builder: (context, isOnline, _) {
        return Column(
          children: [
            if (!isOnline)
              Material(
                elevation: 4,
                color: const Color(0xFFB45309), // Amber 700 / Warning Dark
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off_outlined, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text(
                          'No Internet Connection — Writes are temporarily disabled to prevent data desynchronization.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => SupabaseService.instance.checkConnectivity(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Retry',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
