/// Which signed-in account loaded data belongs to (M8a final review, A1).
///
/// Every account change (sign-in as someone else, sign-out, a deleted or
/// lost session) starts a new epoch ([SessionController] calls
/// [accountChanged]). Data seen fresh — a provider's `AsyncData` that is not
/// loading — is marked with the epoch it was seen in ([markFresh]); Riverpod
/// keeps a provider's previous value through a reload and its failure, so
/// data marked in an earlier epoch, or never seen fresh, is another
/// account's ([fromEarlierAccount]) and is never shown. This holds for every
/// widget, also one built after the reload already failed, which a
/// per-widget memory of the reload cannot know about.
///
/// Values that cannot be marked (numbers, strings, booleans, records) are
/// left to the per-widget rule ([StaleTracker] in widgets.dart).
abstract final class AccountEpoch {
  static int _current = 0;
  static final _seenIn = Expando<int>('account epoch');

  /// The epoch of the account signed in now.
  static int get current => _current;

  /// The signed-in account changed: everything loaded before belongs to
  /// another one.
  static void accountChanged() => _current++;

  /// [data] was just loaded fresh, so it belongs to the account signed in now.
  static void markFresh(Object? data) {
    if (_markable(data)) _seenIn[data!] = _current;
  }

  /// Whether [data] belongs to an earlier account: seen fresh in an earlier
  /// epoch, or never seen fresh at all. False for values that cannot be
  /// marked.
  static bool fromEarlierAccount(Object? data) => _markable(data) && _seenIn[data!] != _current;

  static bool _markable(Object? data) => data != null && data is! num && data is! bool && data is! String && data is! Record;
}
