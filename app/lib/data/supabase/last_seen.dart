import 'package:supabase_flutter/supabase_flutter.dart';

/// Tells the database the signed-in player is around, for "active users". The
/// app calls it on start and when it returns to the foreground; the database
/// writes at most once an hour per player.
///
/// Nothing may get in the way of the app for this, so a failure (offline, an
/// older backend) is swallowed.
Future<void> touchLastSeen(SupabaseClient client) async {
  if (client.auth.currentUser == null) return;
  try {
    await client.rpc('touch_last_seen');
  } catch (_) {
    // Nobody should notice.
  }
}
