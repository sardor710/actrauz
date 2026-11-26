import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/languages.dart';
import 'providers.dart';

class SessionState {
  const SessionState({this.languageCode, this.cityId, this.userName});

  final String? languageCode;
  final String? cityId;
  final String? userName;

  bool get onboarded => languageCode != null && cityId != null && userName != null;
}

/// Language, city and signed-in user, kept across app restarts.
class SessionController extends Notifier<SessionState> {
  static const _lang = 'lang';
  static const _city = 'city';
  static const _user = 'user_name';

  @override
  SessionState build() {
    final prefs = ref.watch(sharedPrefsProvider);
    final auth = ref.watch(authRepositoryProvider);

    // If the backend ends the session (revoked, expired), go back to sign-in.
    final lost = auth.sessionLost.listen((_) => _forgetUser());
    ref.onDispose(lost.cancel);

    final lang = prefs.getString(_lang);
    return SessionState(
      languageCode: kLanguageCodes.contains(lang) ? lang : null,
      cityId: prefs.getString(_city),
      // A remembered name without a backend session is not a sign-in.
      userName: auth.hasSession ? prefs.getString(_user) : null,
    );
  }

  Future<void> setLanguage(String code) async {
    state = SessionState(languageCode: code, cityId: state.cityId, userName: state.userName);
    await ref.read(sharedPrefsProvider).setString(_lang, code);
  }

  Future<void> setCity(String cityId) async {
    state = SessionState(languageCode: state.languageCode, cityId: cityId, userName: state.userName);
    await ref.read(sharedPrefsProvider).setString(_city, cityId);
  }

  /// Called once the player is signed in and has a name.
  Future<void> signIn(String name) async {
    state = SessionState(languageCode: state.languageCode, cityId: state.cityId, userName: name);
    await ref.read(sharedPrefsProvider).setString(_user, name);
  }

  /// Keeps language and city so the next sign-in starts where it left off.
  Future<void> signOut() async {
    await _forgetUser();
    await ref.read(authRepositoryProvider).signOut();
  }

  Future<void> _forgetUser() async {
    if (state.userName == null) return;
    state = SessionState(languageCode: state.languageCode, cityId: state.cityId);
    await ref.read(sharedPrefsProvider).remove(_user);
  }
}
