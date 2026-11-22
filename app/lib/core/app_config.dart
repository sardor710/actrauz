/// Build-time configuration, passed with `--dart-define-from-file=env/dev.json`.
///
/// Without it the app runs on the built-in sample data with the demo
/// sign-in: that is what tests and an offline demo use.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The public ("anon") key. Safe to ship: row-level security decides what
  /// it can reach.
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get hasBackend => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
