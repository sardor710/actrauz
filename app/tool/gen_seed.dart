import 'dart:io';

import 'seed_sql.dart';

/// Writes `supabase/seed.sql` from the app's sample data.
///
///     cd app && dart run tool/gen_seed.dart
void main() {
  final file = File.fromUri(Platform.script.resolve('../../supabase/seed.sql'));
  file.writeAsStringSync(buildSeedSql());
  stdout.writeln('Wrote ${file.path}');
}
