import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_repository.dart';

/// Telegram sign-in against the `telegram-login` edge function.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  bool get isDemo => false;

  @override
  bool get hasSession => _client.auth.currentSession != null;

  @override
  Stream<void> get sessionLost =>
      _client.auth.onAuthStateChange.where((state) => state.event == AuthChangeEvent.signedOut).map((_) {});

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final response = await _client.functions.invoke('telegram-login', body: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Future<LoginChallenge> startTelegramLogin(String languageCode) async {
    final data = await _call({'action': 'start', 'language': languageCode});
    return LoginChallenge(
      token: data['token'] as String,
      pollSecret: data['poll_secret'] as String,
      botUrl: Uri.parse(data['bot_url'] as String),
      expiresAt: DateTime.now().add(Duration(seconds: data['expires_in'] as int)),
    );
  }

  @override
  Future<LoginPoll> pollTelegramLogin(LoginChallenge challenge) async {
    final data = await _call({'action': 'claim', 'token': challenge.token, 'poll_secret': challenge.pollSecret});
    switch (data['status']) {
      case 'pending':
        return const LoginPending();
      case 'ok':
        // The one-time hash becomes this device's session.
        await _client.auth.verifyOTP(type: OtpType.magiclink, tokenHash: data['token_hash'] as String);
        return LoginSignedIn(fullName: await profileName());
      default:
        return const LoginExpired();
    }
  }

  @override
  Future<String?> profileName() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client.from('profiles').select('full_name').eq('id', userId).maybeSingle();
    final name = (row?['full_name'] as String?)?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  @override
  Future<void> saveProfile({required String fullName, required String cityId, required String languageCode}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Not signed in');
    await _client
        .from('profiles')
        .update({
          'full_name': fullName,
          'city_id': cityId,
          'language': languageCode,
          'terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', userId);
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Offline: the local session is cleared regardless.
    }
  }
}
