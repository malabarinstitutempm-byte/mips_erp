import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/inactivity_service.dart';
import '../../core/services/admin_user_service.dart';

class AuthState {
  final User? user;
  final Map<String, dynamic>? profile;
  final bool isLoading;
  final String? errorMessage;
  final bool isMfaRequired;

  AuthState({
    this.user,
    this.profile,
    this.isLoading = false,
    this.errorMessage,
    this.isMfaRequired = false,
  });

  bool get isAuthenticated => user != null && profile != null && profile!['role'] == 'admin' && (profile!['active'] == true);

  String get displayName =>
      profile?['name'] as String? ?? user?.userMetadata?['name'] as String? ?? user?.email ?? 'Administrator';

  String get email => user?.email ?? '';

  AuthState copyWith({
    User? user,
    Map<String, dynamic>? profile,
    bool? isLoading,
    String? errorMessage,
    bool? isMfaRequired,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      profile: clearUser ? null : (profile ?? this.profile),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isMfaRequired: isMfaRequired ?? this.isMfaRequired,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState(isLoading: true)) {
    _initializeAuth();
  }

  static const _storage = FlutterSecureStorage();

  SupabaseClient get _client => SupabaseService.instance.client;

  Future<void> _persistSession(User user, Map<String, dynamic> profile) async {
    try {
      await _storage.write(key: 'mips_admin_session_active', value: 'true');
      await _storage.write(key: 'mips_admin_session_time', value: DateTime.now().millisecondsSinceEpoch.toString());
      await _storage.write(key: 'mips_admin_user_id', value: user.id);
      await _storage.write(key: 'mips_admin_email', value: user.email ?? 'admin@mipsedu.in');
      await _storage.write(key: 'mips_admin_name', value: (profile['name'] as String?) ?? 'System Administrator');
    } catch (_) {}
  }

  Future<void> _clearPersistedSession() async {
    try {
      await _storage.delete(key: 'mips_admin_session_active');
      await _storage.delete(key: 'mips_admin_session_time');
      await _storage.delete(key: 'mips_admin_user_id');
      await _storage.delete(key: 'mips_admin_email');
      await _storage.delete(key: 'mips_admin_name');
    } catch (_) {}
  }

  void _initializeAuth() async {
    try {
      // 1. Check local persistent storage for saved admin session (survives browser refresh)
      final sessionActive = await _storage.read(key: 'mips_admin_session_active');
      final sessionTimeStr = await _storage.read(key: 'mips_admin_session_time');

      if (sessionActive == 'true' && sessionTimeStr != null) {
        final sessionTime = int.tryParse(sessionTimeStr) ?? 0;
        final elapsedMs = DateTime.now().millisecondsSinceEpoch - sessionTime;
        const maxInactivityMs = 5 * 24 * 60 * 60 * 1000; // 5 days

        if (elapsedMs < maxInactivityMs) {
          final userId = await _storage.read(key: 'mips_admin_user_id') ?? 'a0000000-0000-0000-0000-000000000001';
          final email = await _storage.read(key: 'mips_admin_email') ?? 'admin@mipsedu.in';
          final name = await _storage.read(key: 'mips_admin_name') ?? 'System Administrator';

          final adminUser = User(
            id: userId,
            appMetadata: {},
            userMetadata: {'name': name},
            aud: 'authenticated',
            createdAt: DateTime.now().toIso8601String(),
            email: email,
          );

          state = AuthState(
            user: adminUser,
            profile: {
              'user_id': userId,
              'role': 'admin',
              'active': true,
              'name': name,
            },
            isLoading: false,
          );

          // Update session activity timestamp
          await _storage.write(key: 'mips_admin_session_time', value: DateTime.now().millisecondsSinceEpoch.toString());

          InactivityService.instance.start(onTimeout: () {
            logout(reason: 'You have been signed out due to 5 days of inactivity.');
          });
          return;
        } else {
          // Expired after 5 days of inactivity
          await _clearPersistedSession();
        }
      }

      final currentSession = _client.auth.currentSession;
      if (currentSession != null) {
        _loadUserProfile(currentSession.user);
      } else {
        state = AuthState(isLoading: false);
      }

      // Listen to auth state transitions
      _client.auth.onAuthStateChange.listen((data) {
        final session = data.session;
        if (session != null) {
          _loadUserProfile(session.user);
        } else {
          InactivityService.instance.stop();
          state = AuthState(isLoading: false);
        }
      });
    } catch (_) {
      state = AuthState(isLoading: false);
    }
  }

  Future<void> _loadUserProfile(User user) async {
    try {
      final profileRes = await _client
          .from('profiles')
          .select('*, teachers(name), students(name)')
          .eq('user_id', user.id)
          .maybeSingle();

      if (profileRes != null) {
        final role = profileRes['role'] as String?;
        final active = profileRes['active'] as bool? ?? false;

        if (role == 'admin' && active) {
          state = AuthState(
            user: user,
            profile: profileRes,
            isLoading: false,
          );

          await _persistSession(user, profileRes);

          // Start 5-day inactivity timer
          InactivityService.instance.start(onTimeout: () {
            logout(reason: 'You have been signed out due to 5 days of inactivity.');
          });
          return;
        } else {
          // Role guard: Only administrators are authorized
          await _client.auth.signOut();
          InactivityService.instance.stop();
          state = AuthState(
            isLoading: false,
            errorMessage: 'This app is for administrators.',
          );
          return;
        }
      }

      // If no profile found: deny access
      await _client.auth.signOut();
      InactivityService.instance.stop();
      state = AuthState(
        isLoading: false,
        errorMessage: 'This app is for administrators.',
      );
    } catch (e) {
      state = AuthState(
        isLoading: false,
        errorMessage: 'Failed to verify administrator account permissions: $e',
      );
    }
  }

  Future<bool> login(String identifier, String password) async {
    state = state.copyWith(isLoading: true, clearError: true, isMfaRequired: false);

    // 1. Direct authentication check for configured administrator accounts
    final rawClean = identifier.trim().toLowerCase();
    final cleanId = rawClean.replaceAll(RegExp(r'^@+'), '');
    final localAdmin = await AdminUserService.instance.authenticate(cleanId, password);
    if (localAdmin != null) {
      final adminUser = User(
        id: localAdmin.id,
        appMetadata: {},
        userMetadata: {'name': localAdmin.fullName},
        aud: 'authenticated',
        createdAt: localAdmin.createdAt,
        email: localAdmin.email,
      );
      final profile = {
        'user_id': adminUser.id,
        'role': 'admin',
        'active': true,
        'name': localAdmin.fullName,
      };
      state = AuthState(
        user: adminUser,
        profile: profile,
        isLoading: false,
      );
      await _persistSession(adminUser, profile);
      InactivityService.instance.start(onTimeout: () {
        logout(reason: 'You have been signed out due to 5 days of inactivity.');
      });
      return true;
    }

    // 2. Direct server-side RPC verification via portal_verify_login (checks admin_accounts in DB)
    try {
      final rpcRes = await _client.rpc('portal_verify_login', params: {
        'p_identifier': cleanId,
        'p_password': password,
      });

      if (rpcRes != null && rpcRes is Map && rpcRes['success'] == true) {
        final role = rpcRes['role']?.toString() ?? 'admin';
        if (role == 'admin') {
          final userObj = (rpcRes['user'] as Map?)?.cast<String, dynamic>() ?? {};
          final adminUser = User(
            id: userObj['id']?.toString() ?? 'admin_${DateTime.now().millisecondsSinceEpoch}',
            appMetadata: {},
            userMetadata: {'name': userObj['name']?.toString() ?? 'Administrator'},
            aud: 'authenticated',
            createdAt: DateTime.now().toIso8601String(),
            email: userObj['email']?.toString() ?? '$cleanId@mipsedu.in',
          );
          final profile = {
            'user_id': adminUser.id,
            'role': 'admin',
            'active': true,
            'name': userObj['name']?.toString() ?? 'Administrator',
          };
          state = AuthState(
            user: adminUser,
            profile: profile,
            isLoading: false,
          );
          await _persistSession(adminUser, profile);
          InactivityService.instance.start(onTimeout: () {
            logout(reason: 'You have been signed out due to 5 days of inactivity.');
          });
          return true;
        } else {
          state = state.copyWith(
            isLoading: false,
            errorMessage: 'This app is for administrators. Students and teachers should use the web portal.',
          );
          return false;
        }
      }
    } catch (_) {}

    // 3. Direct Supabase Auth signIn fallback (if user has auth.users entry)
    try {
      final email = identifier.trim().contains('@')
          ? identifier.trim()
          : '$cleanId@mipsedu.in';

      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        await _loadUserProfile(response.user!);
        return state.isAuthenticated;
      }
    } catch (_) {}

    state = state.copyWith(
      isLoading: false,
      errorMessage: 'Username or password is incorrect.',
    );
    return false;
  }

  Future<bool> verifyTotp(String code) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final factors = await _client.auth.mfa.listFactors();
      final totpFactor = factors.totp.firstOrNull;

      if (totpFactor == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'No TOTP factor enrolled on this administrator account.',
        );
        return false;
      }

      final challenge = await _client.auth.mfa.challenge(factorId: totpFactor.id);
      await _client.auth.mfa.verify(factorId: totpFactor.id, challengeId: challenge.id, code: code);

      final current = _client.auth.currentUser;
      if (current != null) {
        await _loadUserProfile(current);
      }

      state = state.copyWith(isMfaRequired: false);
      return state.isAuthenticated;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Invalid TOTP authentication code.',
      );
      return false;
    }
  }

  Future<void> logout({String? reason}) async {
    InactivityService.instance.stop();
    await _clearPersistedSession();
    try {
      await _client.auth.signOut().timeout(const Duration(seconds: 1), onTimeout: () => null);
    } catch (_) {}
    state = AuthState(
      isLoading: false,
      errorMessage: reason,
    );
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
