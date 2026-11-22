import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'sample_data.dart';

/// The id a sample row has in the database once `supabase/seed.sql` has
/// loaded it: `md5('actra:<sampleId>')` written as a UUID. The seed generator
/// (`tool/seed_sql.dart`) emits the same expression in SQL.
String seedUuid(String sampleId) {
  final h = md5.convert(utf8.encode('actra:$sampleId')).toString();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

final Map<String, String> _sampleIdBySeedUuid = {
  for (final id in [
    ...kSampleVenues.map((v) => v.id),
    ...kSampleBanners.map((b) => b.id),
    ...kTournamentSeeds.map((t) => t.id),
  ])
    seedUuid(id): id,
};

/// The sample id behind a seeded database id (`v1` for Lochin Padel Club's
/// UUID), or [id] unchanged when it is already a sample id or belongs to a
/// row that did not come from the seed.
String sampleKey(String id) => _sampleIdBySeedUuid[id] ?? id;
