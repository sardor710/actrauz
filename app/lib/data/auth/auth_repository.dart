// Sign-in (product spec §7.1): the player proves their phone number to the
// Actra Telegram bot, and the app receives a session for that number.

/// One sign-in attempt: a link to open in Telegram and what the app needs to
/// collect the result.
class LoginChallenge {
  const LoginChallenge({required this.token, required this.pollSecret, required this.botUrl, required this.expiresAt});

  final String token;

  /// Known only to this device; the link alone cannot collect the session.
  final String pollSecret;
  final Uri botUrl;
  final DateTime expiresAt;
}

sealed class LoginPoll {
  const LoginPoll();
}

/// The player has not shared their contact yet.
class LoginPending extends LoginPoll {
  const LoginPending();
}

/// Too late, or the link was already used: start again.
class LoginExpired extends LoginPoll {
  const LoginExpired();
}

/// Signed in. [fullName] is null for a player who has not finished their
/// profile yet.
class LoginSignedIn extends LoginPoll {
  const LoginSignedIn({this.fullName});

  final String? fullName;
}

abstract class AuthRepository {
  /// `true` for the built-in sample mode: no Telegram, just a name.
  bool get isDemo;

  /// Whether a backend session exists on this device.
  bool get hasSession;

  /// Fires when the backend session ends on its own (revoked or expired).
  Stream<void> get sessionLost;

  Future<LoginChallenge> startTelegramLogin(String languageCode);

  Future<LoginPoll> pollTelegramLogin(LoginChallenge challenge);

  /// The signed-in player's name, or null if they have not entered one.
  Future<String?> profileName();

  /// Saves the first-sign-in details and records that the terms were accepted.
  Future<void> saveProfile({required String fullName, required String cityId, required String languageCode});

  Future<void> signOut();

  /// Deletes the signed-in player's account (both app stores require it in
  /// the app), then signs out. Throws [AdminAccountException] for an Actra
  /// admin; any other failure leaves the account and the session as they were.
  Future<void> deleteAccount();
}

/// An admin account cannot delete itself: another admin removes the role first.
class AdminAccountException implements Exception {
  const AdminAccountException();
}

/// Sample mode: there is nothing to sign in to.
class DemoAuthRepository implements AuthRepository {
  const DemoAuthRepository();

  @override
  bool get isDemo => true;

  @override
  bool get hasSession => true;

  @override
  Stream<void> get sessionLost => const Stream.empty();

  @override
  Future<LoginChallenge> startTelegramLogin(String languageCode) =>
      throw UnsupportedError('Telegram sign-in needs a backend');

  @override
  Future<LoginPoll> pollTelegramLogin(LoginChallenge challenge) =>
      throw UnsupportedError('Telegram sign-in needs a backend');

  @override
  Future<String?> profileName() async => null;

  @override
  Future<void> saveProfile({required String fullName, required String cityId, required String languageCode}) async {}

  @override
  Future<void> signOut() async {}

  /// The sample data belongs to this app run and goes with the name, so
  /// deleting is signing out.
  @override
  Future<void> deleteAccount() => signOut();
}
