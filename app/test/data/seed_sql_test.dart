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

  test("each tournament's first category is the one the tournaments migration creates", () {
    for (final t in kTournamentSeeds) {
      // md5('actra:default-category:' || <tournament uuid>)::uuid, as in
      // app.backfill_tournaments(): the seed updates that row, not a second.
      final first = "(md5('actra:default-category:' || md5('actra:${t.id}')::uuid::text)::uuid, md5('actra:${t.id}')::uuid, ";
      expect(sql, contains(first), reason: t.id);
      expect(sql.split(first), hasLength(2), reason: t.id);
      // The others are derived from their sample ids, like every other row.
      for (final c in t.categories.skip(1)) {
        expect(sql, contains("(md5('actra:${c.id}')::uuid, md5('actra:${t.id}')::uuid, "), reason: c.id);
      }
    }
    expect(sql, contains('insert into public.tournament_categories ('));
    expect(sql, contains('on conflict (id) do update set tournament_id = excluded.tournament_id'));
  });

  test('tournaments carry a deadline, and the summaries are recomputed last', () {
    expect(sql, contains('registration_deadline) values'));
    expect(sql, contains('registration_deadline = excluded.registration_deadline'));
    // The summary columns are no longer written from sample numbers.
    expect(sql, isNot(contains('slots_filled = excluded.slots_filled')));
    expect(sql, isNot(contains('min_fee = excluded.min_fee')));
    final sync = sql.indexOf('select app.sync_tournament_summary(id) from public.tournaments');
    expect(sync, greaterThan(sql.indexOf('insert into public.tournament_categories')));
    expect(sync, greaterThan(sql.indexOf('actra_seed_game(md5')));
    expect(sql.substring(sync).trimRight(), endsWith(';'));
    // The comment lines before it are not part of it: just the select and its where.
    expect(sql.substring(sync).trimRight().split('\n'), hasLength(2));
  });

  test('every sample row is in the seed', () {
    final ids = [
      ...kSampleVenues.map((v) => v.id),
      ...kSampleVenues.expand((v) => v.courts).map((c) => c.id),
      ...kSamplePlayers.map((p) => p.id),
      ...kSampleBanners.map((b) => b.id),
      ...kTournamentSeeds.map((t) => t.id),
      ...kTournamentSeeds.expand((t) => t.categories.skip(1)).map((c) => c.id),
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
