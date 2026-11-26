import 'package:actra/core/localized_text.dart';
import 'package:actra/core/markets.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/domain/models.dart';

/// Builds `supabase/seed.sql` from the same sample data the app's sample
/// backend uses, so the two can never drift apart.
///
/// The script can be run any number of times: catalog rows are upserted, and
/// the sample games (dated relative to "today") are deleted and recreated.
String buildSeedSql() {
  final out = StringBuffer()
    ..writeln('-- Sample content for a new Actra database.')
    ..writeln('--')
    ..writeln('-- GENERATED from app/lib/data/sample/sample_data.dart. Do not edit by hand:')
    ..writeln('--   cd app && dart run tool/gen_seed.dart')
    ..writeln('--')
    ..writeln('-- Safe to run again at any time; sample games and tournaments are re-dated')
    ..writeln('-- from today, except a tournament anyone has registered for, which keeps its')
    ..writeln('-- dates and categories. Venues, people and banners are fictional.')
    ..writeln();

  _cities(out);
  _sports(out);
  _venues(out);
  _courts(out);
  _hours(out);
  _priceRules(out);
  _banners(out);
  _tournaments(out);
  _categories(out);
  _players(out);
  _games(out);
  _summaries(out);
  return out.toString();
}

// ---- SQL literals ----

/// Stable id for a sample row: the same expression in every run. The app
/// computes the same value in `lib/data/sample/seed_ids.dart`.
String _id(String sampleId) => "md5('actra:$sampleId')::uuid";

String _text(String? value) => value == null ? 'null' : "'${value.replaceAll("'", "''")}'";

/// The four language columns of one text, in `_uz, _ru, _kk, _en` order.
List<String> _lang(LocalizedText t) => [_text(t.uz), _text(t.ru), _text(t.kk), _text(t.en)];

List<String> _langCols(String field) => ['${field}_uz', '${field}_ru', '${field}_kk', '${field}_en'];

void _upsert(
  StringBuffer out,
  String table,
  List<String> columns,
  List<List<String>> rows, {
  List<String> key = const ['id'],
  String? where,
}) {
  out.writeln('insert into public.$table (${columns.join(', ')}) values');
  for (var i = 0; i < rows.length; i++) {
    out.writeln('  (${rows[i].join(', ')})${i == rows.length - 1 ? '' : ','}');
  }
  final updates = columns.where((c) => !key.contains(c)).map((c) => '$c = excluded.$c').join(', ');
  out.writeln('on conflict (${key.join(', ')}) do update set $updates${where == null ? '' : '\n  where $where'};');
  out.writeln();
}

String _idList(Iterable<String> sampleIds) => sampleIds.map(_id).join(', ');

Iterable<Court> get _allCourts => kSampleVenues.expand((v) => v.courts);

// ---- Sections ----

void _cities(StringBuffer out) {
  out.writeln('-- Cities');
  _upsert(
    out,
    'cities',
    ['id', ..._langCols('name'), 'country_code', 'currency', 'utc_offset_minutes'],
    [
      for (final c in kCities)
        [_text(c.id), ..._lang(c.name), _text(c.countryCode), _text(c.currency.name.toUpperCase()), '${c.utcOffsetMinutes}'],
    ],
  );
}

void _sports(StringBuffer out) {
  out.writeln('-- Sports');
  _upsert(
    out,
    'sports',
    ['id', ..._langCols('name'), 'icon_key', 'bookable', 'competitive_rating', 'default_players', 'sort_order'],
    [
      for (final (i, s) in kSampleSports.indexed)
        [_text(s.id), ..._lang(s.name), _text(s.iconKey), '${s.bookable}', '${s.competitiveRating}', '${s.defaultPlayers}', '$i'],
    ],
  );
}

void _venues(StringBuffer out) {
  out.writeln('-- Venues');
  _upsert(
    out,
    'venues',
    [
      'id',
      'city_id',
      ..._langCols('name'),
      ..._langCols('description'),
      ..._langCols('address'),
      ..._langCols('district'),
      'phone',
      'amenities',
      'color_seed',
    ],
    [
      for (final v in kSampleVenues)
        [
          _id(v.id),
          _text(v.cityId),
          ..._lang(v.name),
          ..._lang(v.description),
          ..._lang(v.address),
          ..._lang(v.district),
          _text(v.phone),
          'array[${v.amenities.map(_text).join(', ')}]::text[]',
          '${v.colorSeed}',
        ],
    ],
  );
}

void _courts(StringBuffer out) {
  out.writeln('-- Courts');
  _upsert(
    out,
    'courts',
    ['id', 'venue_id', 'sport_id', ..._langCols('name'), 'slot_minutes', 'base_price', 'indoor', 'sort_order'],
    [
      for (final v in kSampleVenues)
        for (final (i, c) in v.courts.indexed)
          [_id(c.id), _id(v.id), _text(c.sportId), ..._lang(c.name), '${c.slotMinutes}', '${c.basePrice}', '${c.indoor}', '$i'],
    ],
  );
}

void _hours(StringBuffer out) {
  out
    ..writeln('-- Working hours: a venue row per open weekday; a court row only where it differs.')
    ..writeln('delete from public.working_hours where venue_id in (${_idList(kSampleVenues.map((v) => v.id))});')
    ..writeln('delete from public.working_hours where court_id in (${_idList(_allCourts.map((c) => c.id))});');

  final rows = <String>[];
  for (final v in kSampleVenues) {
    for (final entry in v.hours.entries) {
      final day = entry.value;
      if (day == null) continue;
      rows.add('(${_id(v.id)}, null, ${entry.key}, false, ${day.openMinute}, ${day.closeMinute})');
    }
    for (final c in v.courts) {
      for (final entry in c.hoursOverride.entries) {
        final day = entry.value;
        rows.add(
          '(null, ${_id(c.id)}, ${entry.key}, ${day == null}, ${day?.openMinute ?? 0}, ${day?.closeMinute ?? 0})',
        );
      }
    }
  }
  out
    ..writeln('insert into public.working_hours (venue_id, court_id, weekday, closed, open_minute, close_minute) values')
    ..writeln('  ${rows.join(',\n  ')};')
    ..writeln();
}

void _priceRules(StringBuffer out) {
  out
    ..writeln('-- Price rules, in priority order')
    ..writeln('delete from public.price_rules where court_id in (${_idList(_allCourts.map((c) => c.id))});');
  final rows = <String>[];
  for (final c in _allCourts) {
    for (final (i, r) in c.priceRules.indexed) {
      final days = r.weekdays.toList()..sort();
      rows.add('(${_id(c.id)}, array[${days.join(', ')}], ${r.fromMinute}, ${r.toMinute}, ${r.price}, $i)');
    }
  }
  out
    ..writeln('insert into public.price_rules (court_id, weekdays, from_minute, to_minute, price, sort_order) values')
    ..writeln('  ${rows.join(',\n  ')};')
    ..writeln();
}

void _banners(StringBuffer out) {
  out.writeln('-- Banners (shown in every city)');
  _upsert(
    out,
    'banners',
    ['id', ..._langCols('title'), ..._langCols('subtitle'), 'url', 'color_seed', 'sort_order'],
    [
      for (final (i, b) in kSampleBanners.indexed)
        [_id(b.id), ..._lang(b.title), ..._lang(b.subtitle), _text(b.url), '${b.colorSeed}', '$i'],
    ],
  );
}

/// Today's date in the venue's city.
String _today(String venueSampleId) {
  final cityId = kSampleVenues.firstWhere((v) => v.id == venueSampleId).cityId;
  return '(select app.to_local(now(), c.utc_offset_minutes)::date from public.cities c where c.id = ${_text(cityId)})';
}

String _cityOf(String venueSampleId) => kSampleVenues.firstWhere((v) => v.id == venueSampleId).cityId;

void _tournaments(StringBuffer out) {
  out.writeln('-- Tournaments, dated from today. The summary columns (min_fee, max_fee, slots_total,');
  out.writeln('-- slots_filled) are not written: the last statement of this file recomputes them.');
  _upsert(
    out,
    'tournaments',
    [
      'id',
      'city_id',
      'sport_id',
      'venue_id',
      ..._langCols('title'),
      'starts_on',
      'ends_on',
      'registration_deadline',
    ],
    [
      for (final t in kTournamentSeeds)
        [
          _id(t.id),
          _text(_cityOf(t.venueId)),
          _text(t.sportId),
          _id(t.venueId),
          ..._lang(t.title),
          '${_today(t.venueId)} + ${t.daysAhead}',
          '${_today(t.venueId)} + ${t.daysAhead + t.days - 1}',
          // Venue wall-clock time, 18:00 on the day [deadlineDaysBefore] days before the first.
          'app.to_instant((${_today(t.venueId)} + ${t.daysAhead - t.deadlineDaysBefore})::timestamp + interval \'18 hours\', '
              '(select c.utc_offset_minutes from public.cities c where c.id = ${_text(_cityOf(t.venueId))}))',
        ],
    ],
    // A tournament someone registered for keeps its dates (and its title).
    where:
        'not exists (select 1 from public.tournament_registrations r '
        'join public.tournament_categories c on c.id = r.category_id where c.tournament_id = excluded.id)',
  );
}

/// The id of a sample tournament's category. The first one gets the id the
/// tournaments migration gives the default category it creates for a
/// tournament without any (the seed then updates that row instead of adding a
/// second); the rest are derived from their sample id like everything else.
String _categoryId(TournamentSeed t, CategorySeed c) =>
    t.categories.first == c ? "md5('actra:default-category:' || ${_id(t.id)}::text)::uuid" : _id(c.id);

void _categories(StringBuffer out) {
  out.writeln('-- Tournament categories (the first of each is the default category the migration made)');
  _upsert(
    out,
    'tournament_categories',
    [
      'id',
      'tournament_id',
      ..._langCols('name'),
      'kind',
      'gender',
      'min_level',
      'max_level',
      'fee',
      'cap',
      'waitlist_enabled',
      'sort_order',
    ],
    [
      for (final t in kTournamentSeeds)
        for (final (i, c) in t.categories.indexed)
          [
            _categoryId(t, c),
            _id(t.id),
            ..._lang(c.name),
            _text(c.kind.name),
            _text(c.gender.name),
            '${c.minLevel}',
            '${c.maxLevel}',
            '${c.fee}',
            '${c.cap}',
            '${c.waitlistEnabled}',
            '$i',
          ],
    ],
    // A category anyone has registered in is left as it is: its kind, cap and
    // fee are what those entries were made under.
    where: 'not exists (select 1 from public.tournament_registrations r where r.category_id = excluded.id)',
  );
}

void _players(StringBuffer out) {
  out
    ..writeln('-- Sample players. They have no password and an undeliverable address,')
    ..writeln('-- so nobody can sign in as them.')
    ..writeln('insert into auth.users (')
    ..writeln('  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,')
    ..writeln('  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,')
    ..writeln('  confirmation_token, recovery_token, email_change_token_new, email_change) values');
  for (final (i, p) in kSamplePlayers.indexed) {
    out.writeln(
      "  ('00000000-0000-0000-0000-000000000000', ${_id(p.id)}, 'authenticated', 'authenticated', "
      "'${p.id}@seed.actra.invalid', '', now(), "
      """'{"provider":"email","providers":["email"]}'::jsonb, '{"sample":true}'::jsonb, now(), now(), '', '', '', '')"""
      "${i == kSamplePlayers.length - 1 ? '' : ','}",
    );
  }
  out
    ..writeln('on conflict (id) do nothing;')
    ..writeln();

  _upsert(
    out,
    'profiles',
    ['id', 'full_name', 'language'],
    [
      for (final p in kSamplePlayers) [_id(p.id), _text(p.name), "'ru'"],
    ],
  );
  _upsert(
    out,
    'player_levels',
    ['user_id', 'sport_id', 'level'],
    [
      for (final p in kSamplePlayers)
        for (final level in p.levels.entries) [_id(p.id), _text(level.key), '${level.value}'],
    ],
    key: ['user_id', 'sport_id'],
  );
}

void _games(StringBuffer out) {
  final players = _idList(kSamplePlayers.map((p) => p.id));
  out
    ..writeln('-- Sample games. Each sits on a real booking made through the booking')
    ..writeln('-- functions, so its slot shows as taken. Recreated on every run.')
    ..writeln('delete from public.games where host_id in ($players);')
    ..writeln('delete from public.bookings where user_id in ($players);')
    ..writeln()
    ..writeln(r'''
create function pg_temp.actra_seed_game(
  p_game_id uuid, p_court_id uuid, p_days_ahead integer, p_minute_of_day integer,
  p_spots integer, p_min_level integer, p_max_level integer, p_players uuid[])
returns void
language plpgsql
as $$
declare
  v_now timestamptz := now();
  v_venue_id uuid;
  v_sport_id text;
  v_city_id text;
  v_offset integer;
  v_start timestamp;
  v_booking public.bookings;
begin
  select c.venue_id, c.sport_id, v.city_id, ci.utc_offset_minutes
    into v_venue_id, v_sport_id, v_city_id, v_offset
  from public.courts c
  join public.venues v on v.id = c.venue_id
  join public.cities ci on ci.id = v.city_id
  where c.id = p_court_id;

  v_start := app.to_local(v_now, v_offset)::date + make_interval(days => p_days_ahead, mins => p_minute_of_day);
  begin
    -- The first player is the host and holds the booking.
    v_booking := app.hold_slots(p_players[1], p_court_id, array[v_start], v_now);
    v_booking := app.confirm_booking(p_players[1], v_booking.id, p_spots, null, v_now);
  exception when raise_exception then
    -- The court is closed that day or the slot is gone: skip this sample game.
    return;
  end;

  insert into public.games (
    id, sport_id, city_id, venue_id, host_id, booking_id, during, utc_offset_minutes,
    spots, min_level, max_level, price_per_player)
  values (
    p_game_id, v_sport_id, v_city_id, v_venue_id, p_players[1], v_booking.id, v_booking.during, v_offset,
    p_spots, p_min_level, p_max_level, round(v_booking.total_price::numeric / p_spots)::integer);

  insert into public.game_participants (game_id, user_id, joined_at)
  select p_game_id, t.user_id, v_now + t.position * interval '1 second'
  from unnest(p_players) with ordinality as t (user_id, position);
end $$;
'''.trim())
    ..writeln();

  for (final g in kGameSeeds) {
    out.writeln(
      'select pg_temp.actra_seed_game(${_id(g.id)}, ${_id(g.courtId)}, ${g.daysAhead}, ${g.hour * 60 + g.minute}, '
      '${g.spots}, ${g.minLevel}, ${g.maxLevel}, array[${_idList(g.participantIds)}]);',
    );
  }
  out
    ..writeln()
    ..writeln('drop function pg_temp.actra_seed_game(uuid, uuid, integer, integer, integer, integer, integer, uuid[]);');
}

void _summaries(StringBuffer out) {
  out
    ..writeln()
    ..writeln('-- Each tournament summary (fees, places, places taken) becomes the real totals')
    ..writeln('-- of its categories and registrations.')
    ..writeln('select app.sync_tournament_summary(id) from public.tournaments')
    ..writeln('where id in (${_idList(kTournamentSeeds.map((t) => t.id))});');
}
