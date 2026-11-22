import 'dart:io';

import 'package:actra/data/sample/sample_data.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/seed_sql.dart';

void main() {
  final sql = buildSeedSql();

  test('supabase/seed.sql is up to date with the sample data', () {
    final file = File('../supabase/seed.sql');
    expect(file.existsSync(), isTrue, reason: 'run: dart run tool/gen_seed.dart');
    expect(
      file.readAsStringSync().replaceAll('\r\n', '\n'),
      sql,
      reason: 'sample data changed; run: dart run tool/gen_seed.dart',
    );
  });

  test('every sample row is in the seed', () {
    final ids = [
      ...kSampleVenues.map((v) => v.id),
      ...kSampleVenues.expand((v) => v.courts).map((c) => c.id),
      ...kSamplePlayers.map((p) => p.id),
      ...kSampleBanners.map((b) => b.id),
      ...kTournamentSeeds.map((t) => t.id),
      ...kGameSeeds.map((g) => g.id),
    ];
    for (final id in ids) {
      expect(sql, contains("md5('actra:$id')::uuid"), reason: id);
    }
    for (final sport in kSampleSports) {
      expect(sql, contains("('${sport.id}', "), reason: sport.id);
    }
  });
}
