import 'dart:math' as math;

import 'package:flutter/material.dart' show TimeOfDay;

import '../../core/markets.dart';
import '../../domain/booking_engine.dart';
import '../../domain/brackets.dart';
import '../../domain/competitive.dart';
import '../../domain/models.dart';
import '../../domain/owner.dart';
import '../../domain/slot_generator.dart';
import '../../domain/tournaments.dart';
import 'sample_data.dart' show kMeId;
import 'sample_tournaments.dart';

/// Tournament draws, schedules, scores and organisers in memory, with the
/// database's rules (supabase/migrations/20261128100000_draws.sql,
/// 20261128110000_schedule.sql, 20261128120000_match_scores.sql,
/// 20261128130000_tournament_ratings.sql). The bracket maths is
/// [BracketRules]; this class keeps the state and the checks, in the same
/// order as the SQL so the same error wins.
///
/// Every call takes the acting user; the demo player is an admin, so an
/// organiser of every tournament. Times are venue wall-clock, as in
/// [SampleTournaments].
///
/// What a SQL transaction undoes on an error, [_txn] undoes here: the
/// category's draw goes back as it was, and notices and released calendar
/// blocks wait for the end of the call.
///
/// Not modelled: the audit log's before/after rows in full (each call logs
/// its action), and rating results for the sample bracket's seeded matches
/// (they moved nobody's rating).
class SampleBrackets implements SampleDrawGuard {
  SampleBrackets({
    required this.tournaments,
    required this.engine,
    required this.utcNow,
    required this.cityNow,
    required this.venueOf,
    required this.courtOf,
    required this.courtActive,
    required this.isRated,
    required this.strengthOf,
    required this.ratingOf,
    required this.setRating,
    required this.isAdmin,
    required this.userExists,
    required this.nameOf,
    required this.isDeleted,
    required this.notify,
    required this.log,
  }) {
    tournaments.draws = this;
  }

  final SampleTournaments tournaments;

  /// Where match blocks live, beside the venue's bookings.
  final BookingEngine engine;
  final DateTime Function() utcNow;

  /// Wall-clock time in a city.
  final DateTime Function(String cityId) cityNow;
  final Venue? Function(String venueId) venueOf;
  final Court? Function(String courtId) courtOf;

  /// The court and its venue are active.
  final bool Function(String courtId) courtActive;
  final bool Function(String sportId) isRated;

  /// Seeding strength of one player (`app.entry_strength`): a rated sport's
  /// rating (1.00 without one), otherwise the level (0 without one).
  final double Function(String userId, String sportId) strengthOf;
  final SportRating? Function(String userId, String sportId) ratingOf;
  final void Function(String userId, String sportId, SportRating rating) setRating;
  final bool Function(String userId) isAdmin;
  final bool Function(String userId) userExists;
  final String Function(String userId) nameOf;
  final bool Function(String userId) isDeleted;
  final void Function(String userId, String kind, String category, Map<String, Object?> payload) notify;
  final void Function(
    String action,
    String entity,
    String? entityId, {
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  })
  log;

  final Map<String, Set<String>> _organizers = {};
  final Map<String, _Draw> _draws = {};

  /// Tournament match id → the rating change of each player of the result
  /// in force (`match_results` with its `rating_events`).
  final Map<String, Map<String, RatingChange>> _results = {};
  int _nextId = 1;

  /// Notices and block releases of the call in progress, run at its end.
  List<void Function()>? _pending;

  static const _scored = {MatchOutcome.played, MatchOutcome.walkover, MatchOutcome.retired, MatchOutcome.decider};

  static Never _fail(TournamentError error) => throw TournamentException(error);

  // ---- Transactions ----

  /// Runs [body] for [categoryId]'s draw: on an error the draw is put back
  /// and nothing it queued happens.
  T _txn<T>(String categoryId, T Function() body) {
    final saved = _draws[categoryId]?.copy();
    final pending = _pending = [];
    try {
      final result = body();
      _pending = null;
      for (final f in pending) {
        f();
      }
      return result;
    } catch (_) {
      _pending = null;
      if (saved == null) {
        _draws.remove(categoryId);
      } else {
        _draws[categoryId] = saved;
      }
      rethrow;
    }
  }

  void _later(void Function() f) {
    final pending = _pending;
    if (pending == null) {
      f();
    } else {
      pending.add(f);
    }
  }

  void _notify(String userId, String kind, Map<String, Object?> payload) =>
      _later(() => notify(userId, kind, 'tournaments', payload));

  /// Deletes the match's calendar block, if it has one (`app.release_match_block`).
  void _release(_Match m) {
    final id = m.blockId;
    if (id == null) return;
    m.blockId = null;
    _later(() => engine.remove(id));
  }

  // ---- Organisers ----

  bool isOrganizer(String userId, String tournamentId) =>
      isAdmin(userId) || (_organizers[tournamentId]?.contains(userId) ?? false);

  void _requireOrganizer(String userId, String tournamentId) {
    if (!isOrganizer(userId, tournamentId)) _fail(TournamentError.notAllowed);
  }

  SampleTournamentInfo _tournament(String tournamentId) =>
      tournaments.info(tournamentId) ?? _fail(TournamentError.notFound);

  /// `app.lock_draw`: the category, the organiser check, then its draw (null
  /// when there is none).
  _Draw? _lockDraw(String userId, String categoryId) {
    final tournamentId = tournaments.tournamentOf(categoryId) ?? _fail(TournamentError.notFound);
    _requireOrganizer(userId, tournamentId);
    return _draws[categoryId];
  }

  List<PlayerRef> organizers(String userId, String tournamentId) {
    if (!isAdmin(userId)) _fail(TournamentError.notAllowed);
    _tournament(tournamentId);
    return _organizerList(tournamentId);
  }

  List<PlayerRef> _organizerList(String tournamentId) {
    final rows = [for (final id in _organizers[tournamentId] ?? const <String>{}) PlayerRef(id: id, name: nameOf(id))]
      ..sort((a, b) {
        final byName = a.name.compareTo(b.name);
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    return rows;
  }

  /// Adds or removes an organiser; the person hears when the list changes.
  List<PlayerRef> setOrganizer(String userId, String tournamentId, String targetId, {required bool add}) {
    if (!isAdmin(userId)) _fail(TournamentError.notAllowed);
    _tournament(tournamentId);
    if (!userExists(targetId)) _fail(TournamentError.notFound);
    final set = _organizers.putIfAbsent(tournamentId, () => {});
    final changed = add ? set.add(targetId) : set.remove(targetId);
    if (changed) {
      notify(
        targetId,
        add ? 'organizer_added' : 'organizer_removed',
        'tournaments',
        tournaments.note(tournamentId, null),
      );
    }
    log(
      add ? 'add_organizer' : 'remove_organizer',
      'tournament',
      tournamentId,
      after: {'user_id': targetId, 'add': add},
    );
    return _organizerList(tournamentId);
  }

  /// Active tournaments the player is a named organiser of, earliest first.
  List<TournamentSummary> organizedTournaments(String userId) {
    final rows =
        [
          for (final MapEntry(key: id, value: users) in _organizers.entries)
            if (users.contains(userId))
              if (tournaments.info(id) case final t? when t.active) t,
        ]..sort((a, b) {
          final byStart = a.start.compareTo(b.start);
          return byStart != 0 ? byStart : a.id.compareTo(b.id);
        });
    return [for (final t in rows) tournaments.summary(t.id)];
  }

  List<AdminRegistration> entries(String userId, String tournamentId) {
    _requireOrganizer(userId, tournamentId);
    _tournament(tournamentId);
    return tournaments.registrations(tournamentId);
  }

  // ---- Helpers ----

  /// The players of an entry: the registrant, then the partner.
  List<String> _players(String? registrationId) {
    if (registrationId == null) return const [];
    final e = tournaments.entry(registrationId);
    if (e == null) return const [];
    return [e.userId, if (e.partnerId != null) e.partnerId!];
  }

  List<String> _matchPlayers(_Match m) => [..._players(m.sideA), ..._players(m.sideB)];

  List<String> _drawPlayers(_Draw d) => {for (final e in d.entries) ..._players(e.registrationId)}.toList();

  bool _withdrawn(_Draw d, String registrationId) =>
      d.entries.any((e) => e.registrationId == registrationId && e.withdrawn);

  DateTime _now(String tournamentId) => cityNow(tournaments.info(tournamentId)!.cityId);

  _Match? _ko(_Draw d, int round, int position) =>
      d.matches.where((m) => m.stage == MatchStage.knockout && m.round == round && m.position == position).firstOrNull;

  _Match? _next(_Draw d, _Match m) => _ko(d, m.round + 1, (m.position + 1) ~/ 2);

  /// The match and its draw.
  (_Draw, _Match)? _find(String matchId) {
    for (final d in _draws.values) {
      for (final m in d.matches) {
        if (m.id == matchId) return (d, m);
      }
    }
    return null;
  }

  Iterable<_Draw> _drawsOf(String tournamentId) sync* {
    for (final id in tournaments.categoryIds(tournamentId)) {
      if (_draws[id] case final d?) yield d;
    }
  }

  // ---- Spans and clashes (app.match_span, app.players_busy) ----

  /// One slot of the match's court; without a court, the instant it starts.
  _Span? _span(_Match m) {
    final start = m.startsAt;
    if (start == null) return null;
    final court = m.courtId == null ? null : courtOf(m.courtId!);
    if (court == null) return _Span(start, start, point: true);
    return _Span(start, start.add(Duration(minutes: court.slotMinutes)));
  }

  /// One of [players] is in another scheduled match of the tournament, in any
  /// category, at a time overlapping [span].
  bool _busy(String tournamentId, String matchId, List<String> players, _Span? span) {
    if (span == null || players.isEmpty) return false;
    for (final d in _drawsOf(tournamentId)) {
      for (final o in d.matches) {
        if (o.id == matchId || o.startsAt == null) continue;
        if (!_span(o)!.overlaps(span)) continue;
        if (_matchPlayers(o).any(players.contains)) return true;
      }
    }
    return false;
  }

  // ---- Making a draw (app.build_draw, app.build_matches, app.build_knockout) ----

  void _checkEntries(String categoryId, DrawFormat format) {
    final n = tournaments.registered(categoryId).length;
    if (n < 2 || (format == DrawFormat.groups && n < 3)) _fail(TournamentError.tooFewEntries);
  }

  /// The draw's entries, groups and matches afresh from the category's
  /// registered entries. Strongest first; ties in the order they registered
  /// (the database breaks them at random).
  void _buildDraw(_Draw d) {
    final sport = tournaments.info(d.tournamentId)!.sportId;
    final regs = tournaments.registered(d.categoryId);
    double strength(SampleEntryInfo e) {
      final players = [e.userId, if (e.partnerId != null) e.partnerId!];
      final total = players.fold<double>(0, (s, p) => s + strengthOf(p, sport));
      return (total / players.length * 100).round() / 100;
    }

    final rows = [for (final (i, e) in regs.indexed) (i, e.id, strength(e))]
      ..sort((x, y) {
        final byStrength = y.$3.compareTo(x.$3);
        return byStrength != 0 ? byStrength : x.$1.compareTo(y.$1);
      });
    for (final m in d.matches) {
      _release(m);
    }
    d
      ..entries = [for (final (i, (_, id, s)) in rows.indexed) _DrawEntry(id, i + 1, s)]
      ..groups = [];
    if (d.format == DrawFormat.groups) {
      final count = BracketRules.groupSizes(rows.length, d.groupSize!).length;
      d.groups = [for (var i = 1; i <= count; i++) _Group('tg${_nextId++}', _label(i), i)];
      // Snake: seeds 1..G to A..G, then G..A, and so on.
      for (final e in d.entries) {
        final s = e.seed - 1;
        final index = (s ~/ count).isEven ? s % count + 1 : count - s % count;
        e.groupId = d.groups[index - 1].id;
      }
    }
    _buildMatches(d);
  }

  static String _label(int i) => i <= 26
      ? String.fromCharCode(64 + i)
      : String.fromCharCode(64 + (i - 1) ~/ 26) + String.fromCharCode(65 + (i - 1) % 26);

  /// Every match of the draw afresh from its entries.
  void _buildMatches(_Draw d) {
    for (final m in d.matches) {
      _release(m);
    }
    d.matches = [];
    final bySeed = [...d.entries]..sort((a, b) => a.seed.compareTo(b.seed));
    if (d.format == DrawFormat.knockout) {
      _buildKnockout(d, bySeed.length, [for (final e in bySeed) e.registrationId]);
      return;
    }
    for (final g in d.groups) {
      final members = [
        for (final e in bySeed)
          if (e.groupId == g.id) e.registrationId,
      ];
      if (members.isEmpty) continue;
      for (final (r, pairs) in BracketRules.roundRobin(members.length).indexed) {
        for (final (p, (i, j)) in pairs.indexed) {
          d.matches.add(
            _Match('tm${_nextId++}', MatchStage.group, r + 1, p + 1, groupId: g.id)
              ..sideA = members[i]
              ..sideB = members[j]
              ..status = MatchStatus.ready,
          );
        }
      }
    }
    // One group with one advancing has no knockout: the group decides.
    if (d.groups.length * d.advance! >= 2) _buildKnockout(d, d.groups.length * d.advance!, null);
  }

  /// The knockout rows for [count] entries. [regs] (by seed) fills round 1,
  /// settling byes at once; null (after groups) leaves every row waiting,
  /// with the slots beyond [count] marked empty.
  void _buildKnockout(_Draw d, int count, List<String>? regs) {
    final size = BracketRules.bracketSize(count);
    final order = BracketRules.seedOrder(size);
    var rounds = 0;
    while ((1 << rounds) < size) {
      rounds++;
    }
    for (var r = 1; r <= rounds; r++) {
      for (var p = 1; p <= size >> r; p++) {
        d.matches.add(_Match('tm${_nextId++}', MatchStage.knockout, r, p));
      }
    }
    for (var p = 1; p <= size ~/ 2; p++) {
      final seedA = order[2 * p - 2], seedB = order[2 * p - 1];
      final m = _ko(d, 1, p)!
        ..aEmpty = seedA > count
        ..bEmpty = seedB > count;
      if (regs == null) continue;
      m
        ..sideA = seedA <= count ? regs[seedA - 1] : null
        ..sideB = seedB <= count ? regs[seedB - 1] : null;
      if (seedA > count || seedB > count) {
        m
          ..status = MatchStatus.done
          ..outcome = MatchOutcome.bye
          ..winner = seedB > count ? Side.a : Side.b;
        final next = _ko(d, 2, (p + 1) ~/ 2);
        if (next != null) {
          if (p.isOdd) {
            next.sideA = regs[math.min(seedA, seedB) - 1];
          } else {
            next.sideB = regs[math.min(seedA, seedB) - 1];
          }
        }
      }
    }
    for (final m in d.matches) {
      if (m.stage == MatchStage.knockout && m.status == MatchStatus.waiting && m.sideA != null && m.sideB != null) {
        m.status = MatchStatus.ready;
      }
    }
  }

  // ---- Draw calls ----

  /// Makes, or makes again, the category's draft from its registered entries.
  CategoryDraw makeDraw(String userId, String categoryId, DrawFormat format, {int? groupSize, int? advance}) {
    final existing = _lockDraw(userId, categoryId);
    if (existing?.published ?? false) _fail(TournamentError.drawPublished);
    if (format == DrawFormat.knockout) {
      groupSize = null;
      advance = null;
    } else if (groupSize == null ||
        !const {3, 4}.contains(groupSize) ||
        advance == null ||
        !const {1, 2}.contains(advance)) {
      _fail(TournamentError.invalidArgument);
    }
    _checkEntries(categoryId, format);
    final d = existing ?? _Draw(categoryId, tournaments.tournamentOf(categoryId)!, format);
    d
      ..format = format
      ..groupSize = groupSize
      ..advance = advance
      ..published = false
      ..outdated = false
      ..firstScoreAt = null;
    _draws[categoryId] = d;
    _buildDraw(d);
    log(
      'make_draw',
      'tournament_category',
      categoryId,
      after: {'format': format.name, 'group_size': groupSize, 'advance': advance},
    );
    return _drawView(d, userId)!;
  }

  /// Swaps two entries of a draft: their seeds (knockout) or their groups.
  CategoryDraw swapEntries(String userId, String categoryId, String registrationA, String registrationB) {
    final d = _lockDraw(userId, categoryId) ?? _fail(TournamentError.notFound);
    if (d.published) _fail(TournamentError.drawPublished);
    if (registrationA == registrationB) _fail(TournamentError.invalidArgument);
    final a = d.entries.where((e) => e.registrationId == registrationA).firstOrNull ?? _fail(TournamentError.notFound);
    final b = d.entries.where((e) => e.registrationId == registrationB).firstOrNull ?? _fail(TournamentError.notFound);
    if (d.format == DrawFormat.knockout) {
      final seed = a.seed;
      a.seed = b.seed;
      b.seed = seed;
      d.entries.sort((x, y) => x.seed.compareTo(y.seed));
    } else {
      final group = a.groupId;
      a.groupId = b.groupId;
      b.groupId = group;
    }
    _buildMatches(d);
    log(
      'swap_draw_entries',
      'tournament_category',
      categoryId,
      after: {'registration_a': registrationA, 'registration_b': registrationB},
    );
    return _drawView(d, userId)!;
  }

  /// Shows the draft to everyone and locks the category's entries for good.
  /// Open waitlist offers and the waitlist lapse.
  CategoryDraw publish(String userId, String categoryId) {
    final d = _lockDraw(userId, categoryId) ?? _fail(TournamentError.notFound);
    if (d.published) _fail(TournamentError.drawPublished);
    if (d.outdated) _fail(TournamentError.drawOutdated);
    d
      ..published = true
      ..locked = true;
    tournaments.closeWaitlist(categoryId);
    final note = tournaments.note(d.tournamentId, categoryId);
    for (final p in _drawPlayers(d)) {
      notify(p, 'draw_published', 'tournaments', note);
    }
    log('publish_draw', 'tournament_category', categoryId);
    return _drawView(d, userId)!;
  }

  /// Throws a published draw away and makes a new draft from the entries
  /// still registered, until the first score. The category stays locked.
  CategoryDraw redo(String userId, String categoryId) {
    final d = _lockDraw(userId, categoryId) ?? _fail(TournamentError.notFound);
    if (!d.published) _fail(TournamentError.invalidArgument);
    if (d.firstScoreAt != null) _fail(TournamentError.drawFinal);
    _checkEntries(categoryId, d.format);
    final before = _drawPlayers(d);
    d
      ..published = false
      ..outdated = false;
    _buildDraw(d);
    final note = tournaments.note(d.tournamentId, categoryId);
    for (final p in {...before, ..._drawPlayers(d)}) {
      notify(p, 'draw_redone', 'tournaments', note);
    }
    log('redo_draw', 'tournament_category', categoryId);
    return _drawView(d, userId)!;
  }

  // ---- Scheduling (app.schedule_match, app.fill_day) ----

  /// Sets, moves or (a null [startsAt]) clears a match's court and time.
  TournamentMatch scheduleMatch(
    String userId,
    String matchId, {
    String? courtId,
    DateTime? startsAt,
    String? placeNote,
  }) {
    final (d, m) = _find(matchId) ?? _fail(TournamentError.notFound);
    _lockDraw(userId, d.categoryId);
    if (!d.published) _fail(TournamentError.notFound);
    if (m.status == MatchStatus.done) _fail(TournamentError.invalidArgument);
    final t = tournaments.info(d.tournamentId)!;
    // A hidden tournament has no schedule.
    if (!t.active) _fail(TournamentError.notFound);

    if (startsAt == null) {
      final before = {'court_id': m.courtId, 'starts_at': m.startsAt?.toIso8601String()};
      _release(m);
      m
        ..courtId = null
        ..startsAt = null
        ..placeNote = null;
      log('schedule_match', 'tournament_match', m.id, before: before);
      return _view(d, m);
    }

    final date = dateOnly(startsAt);
    if (date.isBefore(t.start) || date.isAfter(t.end)) _fail(TournamentError.invalidArgument);
    final trimmed = placeNote?.trim();
    final note = trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (note != null && note.length > 100) _fail(TournamentError.invalidArgument);
    if (startsAt.isBefore(_now(t.id))) _fail(TournamentError.inPast);

    final _Span span;
    Court? court;
    if (t.venueId == null) {
      if (courtId != null) _fail(TournamentError.invalidArgument);
      span = _Span(startsAt, startsAt, point: true);
    } else {
      final venue = venueOf(t.venueId!);
      court = courtId == null ? null : courtOf(courtId);
      if (venue == null || court == null || court.venueId != t.venueId || !courtActive(court.id)) {
        _fail(TournamentError.invalidArgument);
      }
      if (!generateSlots(venue, court, date).any((s) => s.start == startsAt)) _fail(TournamentError.invalidArgument);
      span = _Span(startsAt, startsAt.add(Duration(minutes: court.slotMinutes)));
    }

    if (_busy(t.id, m.id, _matchPlayers(m), span)) _fail(TournamentError.playerBusy);
    final changed = m.startsAt != startsAt || m.courtId != courtId;
    if (court != null && !engine.isFree(court.id, span.start, span.end, now: _now(t.id), except: m.blockId)) {
      _fail(TournamentError.slotTaken);
    }

    final before = {'court_id': m.courtId, 'starts_at': m.startsAt?.toIso8601String()};
    _release(m);
    if (court != null) m.blockId = _block(t, court, span);
    m
      ..courtId = courtId
      ..startsAt = startsAt
      ..placeNote = note;
    if (changed) _notifyScheduled(d, m);
    log(
      'schedule_match',
      'tournament_match',
      m.id,
      before: before,
      after: {'court_id': courtId, 'starts_at': startsAt.toIso8601String(), 'place_note': note},
    );
    return _view(d, m);
  }

  String _block(SampleTournamentInfo t, Court court, _Span span) {
    final title = t.title;
    return engine
        .blockMatch(
          venueId: court.venueId,
          courtId: court.id,
          start: span.start,
          end: span.end,
          reason: 'Tournament: ${title.uz ?? title.ru ?? title.en ?? title.kk ?? ''}',
          now: _now(t.id),
        )
        .id;
  }

  void _notifyScheduled(_Draw d, _Match m) {
    final payload = {
      ...tournaments.note(d.tournamentId, d.categoryId),
      'match_id': m.id,
      'starts_at': m.startsAt == null ? null : _local(m.startsAt!),
      'court_id': m.courtId,
      'court_name': switch (m.courtId == null ? null : courtOf(m.courtId!)) {
        final c? => {'uz': c.name.uz, 'ru': c.name.ru, 'kk': c.name.kk, 'en': c.name.en},
        null => null,
      },
      'place_note': m.placeNote,
    };
    for (final p in _matchPlayers(m).toSet()) {
      _notify(p, 'match_scheduled', payload);
    }
  }

  static String _local(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}T${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  /// "Fill the day": the unscheduled matches of the ticked categories (null:
  /// all) with a published draw, into free slots of [courtIds] on [day] from
  /// [from]. Group matches of every category first, round by round (with a
  /// free slot between an entry's matches, then without for those left),
  /// then knockout rounds in order.
  FillResult fillDay(
    String userId,
    String tournamentId,
    DateTime day,
    List<String> courtIds,
    TimeOfDay from, {
    List<String>? categoryIds,
  }) {
    final t = _tournament(tournamentId);
    _requireOrganizer(userId, tournamentId);
    if (!t.active) _fail(TournamentError.notFound);
    final date = dateOnly(day);
    final venue = t.venueId == null ? null : venueOf(t.venueId!);
    final courts = [for (final id in courtIds) courtOf(id)];
    final ownCategories = tournaments.categoryIds(tournamentId);
    if (venue == null ||
        date.isBefore(t.start) ||
        date.isAfter(t.end) ||
        courtIds.isEmpty ||
        courtIds.toSet().length != courtIds.length ||
        courts.any((c) => c == null || c.venueId != t.venueId || !courtActive(c.id)) ||
        (categoryIds ?? const []).any((id) => !ownCategories.contains(id))) {
      _fail(TournamentError.invalidArgument);
    }
    final start = date.add(Duration(hours: from.hour, minutes: from.minute));
    final ticked = [
      for (final (i, id) in ownCategories.indexed)
        if (categoryIds == null || categoryIds.contains(id))
          if (_draws[id] case final d? when d.published) (i, d),
    ];

    var scheduled = 0;
    final unscheduled = <String>[];
    final groupSort = {
      for (final (_, d) in ticked)
        for (final g in d.groups) g.id: g.sortOrder,
    };
    bool open(_Match m) =>
        m.startsAt == null && (m.status == MatchStatus.waiting || m.status == MatchStatus.ready) && m.outcome == null;
    final groupMatches =
        [
          for (final (i, d) in ticked)
            for (final m in d.matches)
              if (m.stage == MatchStage.group && open(m)) (i, d, m),
        ]..sort((x, y) {
          for (final c in [
            x.$3.round.compareTo(y.$3.round),
            x.$1.compareTo(y.$1),
            groupSort[x.$3.groupId]!.compareTo(groupSort[y.$3.groupId]!),
            x.$3.position.compareTo(y.$3.position),
          ]) {
            if (c != 0) return c;
          }
          return 0;
        });
    final retry = <(_Draw, _Match)>[];
    for (final (_, d, m) in groupMatches) {
      if (_place(t, venue, courts.cast<Court>(), d, m, date, start, gap: true)) {
        scheduled++;
      } else {
        retry.add((d, m));
      }
    }
    for (final (d, m) in retry) {
      if (_place(t, venue, courts.cast<Court>(), d, m, date, start, gap: false)) {
        scheduled++;
      } else {
        unscheduled.add(m.id);
      }
    }
    // A slot nobody fills (a bye still to settle) is no match.
    final knockout =
        [
          for (final (i, d) in ticked)
            for (final m in d.matches)
              if (m.stage == MatchStage.knockout && open(m) && !m.aEmpty && !m.bEmpty) (i, d, m),
        ]..sort((x, y) {
          for (final c in [
            x.$3.round.compareTo(y.$3.round),
            x.$1.compareTo(y.$1),
            x.$3.position.compareTo(y.$3.position),
          ]) {
            if (c != 0) return c;
          }
          return 0;
        });
    for (final (_, d, m) in knockout) {
      if (_place(t, venue, courts.cast<Court>(), d, m, date, start, gap: false)) {
        scheduled++;
      } else {
        unscheduled.add(m.id);
      }
    }
    log(
      'fill_day',
      'tournament',
      tournamentId,
      after: {
        'day': _local(date).substring(0, 10),
        'court_ids': courtIds,
        'from': _local(start).substring(11, 16),
        'category_ids': categoryIds,
        'scheduled': scheduled,
      },
    );
    return FillResult(scheduled: scheduled, unscheduled: unscheduled);
  }

  /// One match of "fill the day" into the earliest slot that fits (time, then
  /// court in the order given): free on the court; no player busy; after
  /// both feeder matches end; a first knockout round after the category's
  /// scheduled group matches; with [gap], a free slot between an entry's
  /// group matches. True when placed.
  bool _place(
    SampleTournamentInfo t,
    Venue venue,
    List<Court> courts,
    _Draw d,
    _Match m,
    DateTime date,
    DateTime from, {
    required bool gap,
  }) {
    final players = _matchPlayers(m);
    final now = _now(t.id);
    final slots =
        [
          for (final (ord, court) in courts.indexed)
            for (final s in generateSlots(venue, court, date))
              if (!s.start.isBefore(from)) (s, ord, court),
        ]..sort((x, y) {
          final byStart = x.$1.start.compareTo(y.$1.start);
          return byStart != 0 ? byStart : x.$2.compareTo(y.$2);
        });
    for (final (slot, _, court) in slots) {
      final span = _Span(slot.start, slot.end);
      if (span.start.isBefore(now)) continue;
      if (!engine.isFree(court.id, span.start, span.end, now: now)) continue;
      if (_busy(t.id, m.id, players, span)) continue;
      if (m.stage == MatchStage.knockout && m.round > 1) {
        final feeders = [_ko(d, m.round - 1, 2 * m.position - 1), _ko(d, m.round - 1, 2 * m.position)];
        if (feeders.any((f) => f != null && f.startsAt != null && _span(f)!.end.isAfter(span.start))) continue;
      }
      if (m.stage == MatchStage.knockout &&
          m.round == 1 &&
          d.matches.any(
            (g) => g.stage == MatchStage.group && g.startsAt != null && _span(g)!.end.isAfter(span.start),
          )) {
        continue;
      }
      if (gap && m.stage == MatchStage.group) {
        final pad = Duration(minutes: court.slotMinutes);
        final padded = _Span(span.start.subtract(pad), span.end.add(pad));
        final sides = {m.sideA, m.sideB};
        if (d.matches.any(
          (o) =>
              o.stage == MatchStage.group &&
              o.id != m.id &&
              o.startsAt != null &&
              (sides.contains(o.sideA) || sides.contains(o.sideB)) &&
              padded.overlaps(_span(o)!),
        )) {
          continue;
        }
      }
      if (!engine.isFree(court.id, span.start, span.end, now: now)) continue;
      m
        ..blockId = _block(t, court, span)
        ..courtId = court.id
        ..startsAt = span.start
        ..placeNote = null;
      _notifyScheduled(d, m);
      return true;
    }
    return false;
  }

  // ---- Settling a knockout (app.place_winner, app.settle_match) ----

  /// A match that will not be played: before its start its block goes and
  /// its court and time are cleared; from its start on both stay.
  void _notPlayed(_Draw d, _Match m) {
    final start = m.startsAt;
    if (start != null && start.isAfter(_now(d.tournamentId))) {
      _release(m);
      m
        ..courtId = null
        ..startsAt = null;
    }
  }

  /// Puts what a knockout match produced into its side of the next match,
  /// then settles that match.
  void _placeWinner(_Draw d, _Match m) {
    if (m.stage != MatchStage.knockout) return;
    final next = _next(d, m);
    if (next == null) return;
    String? entry;
    var empty = false;
    if (m.status == MatchStatus.done) {
      entry = m.winnerEntry;
      if (entry == null || _withdrawn(d, entry)) {
        entry = null;
        empty = true;
      }
    }
    if (m.position.isOdd) {
      if (next.sideA == entry && next.aEmpty == empty) return;
      next
        ..sideA = entry
        ..aEmpty = empty;
    } else {
      if (next.sideB == entry && next.bEmpty == empty) return;
      next
        ..sideB = entry
        ..bEmpty = empty;
    }
    // A next match that already has a result never changes a side under it.
    if (next.status == MatchStatus.done && _scored.contains(next.outcome)) _fail(TournamentError.nextMatchPlayed);
    _settle(d, next);
  }

  /// Recomputes a knockout match nobody has scored from its sides: one side
  /// gone and the other known is done for the known side (a bye in round 1,
  /// else a walkover); both gone is done with no winner.
  void _settle(_Draw d, _Match m) {
    if (m.stage != MatchStage.knockout) return;
    if (m.status == MatchStatus.done && m.outcome != MatchOutcome.bye && m.outcome != MatchOutcome.none) return;
    final aGone = m.aEmpty || (m.sideA != null && _withdrawn(d, m.sideA!));
    final bGone = m.bEmpty || (m.sideB != null && _withdrawn(d, m.sideB!));
    final freeWin = m.round == 1 ? MatchOutcome.bye : MatchOutcome.walkover;
    final (MatchStatus, MatchOutcome?, Side?) next;
    if (aGone && bGone) {
      next = (MatchStatus.done, MatchOutcome.none, null);
    } else if (aGone && m.sideB != null) {
      next = (MatchStatus.done, freeWin, Side.b);
    } else if (bGone && m.sideA != null) {
      next = (MatchStatus.done, freeWin, Side.a);
    } else if (m.sideA != null && m.sideB != null) {
      next = (MatchStatus.ready, null, null);
    } else {
      next = (MatchStatus.waiting, null, null);
    }
    final (status, outcome, winner) = next;
    if (status == m.status && outcome == m.outcome && winner == m.winner) return;
    m
      ..status = status
      ..outcome = outcome
      ..winner = winner
      ..sets = null
      ..scoredBy = null
      ..scoredAt = status == MatchStatus.done ? utcNow() : null;
    if (status == MatchStatus.done) _notPlayed(d, m);
    _placeWinner(d, m);
  }

  // ---- Groups into the knockout (app.group_table, app.fill_knockout) ----

  List<GroupStanding> _standings(_Draw d, _Group g) {
    final members = [
      for (final e in d.entries)
        if (e.groupId == g.id) e,
    ];
    return BracketRules.standings(
      [
        for (final m in d.matches)
          if (m.groupId == g.id) _plain(m),
      ],
      {for (final e in members) e.registrationId: e.seed},
      {
        for (final e in members)
          if (e.withdrawn) e.registrationId,
      },
      advance: d.advance ?? 0,
    );
  }

  /// Once every group match is done, and while the knockout has nothing but
  /// byes settled, (re)places the qualifiers in its first round. A withdrawn
  /// qualifier leaves its slot empty. Courts and times already set stay.
  void _fillKnockout(_Draw d) {
    if (d.format != DrawFormat.groups) return;
    if (d.matches.any((m) => m.stage == MatchStage.group && m.status != MatchStatus.done)) return;
    final count = d.groups.length * d.advance!;
    if (count < 2) return;
    final started = d.matches.any(
      (m) => m.stage == MatchStage.knockout && m.outcome != null && m.outcome != MatchOutcome.bye,
    );
    if (started) return;

    final groups = [for (final g in d.groups) DrawGroup(id: g.id, label: g.label, standings: _standings(d, g))];
    final ranked = BracketRules.rankQualifiers(groups, d.advance!, {
      for (final e in d.entries) e.registrationId: e.seed,
    });
    final groupOf = {for (final id in ranked) id: d.entries.firstWhere((e) => e.registrationId == id).groupId!};
    final size = BracketRules.bracketSize(count);
    final slots = [
      for (final id in BracketRules.placeQualifiers(ranked, groupOf, size)) id != null && _withdrawn(d, id) ? null : id,
    ];
    for (final m in d.matches.where((m) => m.stage == MatchStage.knockout)) {
      m
        ..sideA = null
        ..sideB = null
        ..aEmpty = false
        ..bEmpty = false
        ..status = MatchStatus.waiting
        ..outcome = null
        ..winner = null
        ..sets = null
        ..scoredBy = null
        ..scoredAt = null;
    }
    for (var i = 1; i <= size ~/ 2; i++) {
      final a = slots[2 * i - 2], b = slots[2 * i - 1];
      _ko(d, 1, i)!
        ..sideA = a
        ..sideB = b
        ..aEmpty = a == null
        ..bEmpty = b == null;
    }
    for (var i = 1; i <= size ~/ 2; i++) {
      _settle(d, _ko(d, 1, i)!);
    }
  }

  // ---- The category's result (app.category_result) ----

  ({String? winner, String? runnerUp, bool finished}) _result(_Draw d) {
    const none = (winner: null, runnerUp: null, finished: false);
    if (!d.published) return none;
    final knockout = d.matches.where((m) => m.stage == MatchStage.knockout).toList();
    if (knockout.isNotEmpty) {
      final last = knockout.reduce(
        (a, b) => b.round > a.round || (b.round == a.round && b.position < a.position) ? b : a,
      );
      if (last.status != MatchStatus.done) return none;
      final runnerUp = switch (last.winner) {
        Side.a => last.sideB,
        Side.b => last.sideA,
        _ => null,
      };
      return (winner: last.winnerEntry, runnerUp: runnerUp, finished: true);
    }
    final group = d.matches.where((m) => m.stage == MatchStage.group);
    if (group.isEmpty || group.any((m) => m.status != MatchStatus.done)) return none;
    final table = _standings(d, d.groups.first);
    String? at(int place) => table.where((s) => s.place == place && !s.withdrawn).firstOrNull?.registrationId;
    return (winner: at(1), runnerUp: at(2), finished: true);
  }

  /// `category_won` to the winner's players when the winner is new.
  void _announce(_Draw d, String? before) {
    final winner = _result(d).winner;
    if (winner == null || winner == before) return;
    final note = {...tournaments.note(d.tournamentId, d.categoryId), 'registration_id': winner};
    for (final p in _players(winner)) {
      _notify(p, 'category_won', note);
    }
  }

  void _notifyResult(_Draw d, _Match m, List<String> players, {required bool correction}) {
    final payload = {
      ...tournaments.note(d.tournamentId, d.categoryId),
      'match_id': m.id,
      'side_a': m.sideA,
      'side_b': m.sideB,
      'outcome': m.outcome?.name,
      'winner': m.winner?.name,
      'sets': m.sets,
      'correction': correction,
    };
    for (final p in players.toSet()) {
      _notify(p, 'match_result', payload);
    }
  }

  // ---- Scores (app.enter_match_score) ----

  /// A score as stored: a rated sport's M7 sets, or one pair 0–99.
  static List<List<int>> _checkedSets(List<List<int>>? sets, {required bool rated}) {
    if (sets == null || sets.any((s) => s.length != 2)) _fail(TournamentError.invalidArgument);
    if (rated) {
      if (!validSets([for (final s in sets) (s[0], s[1])])) _fail(TournamentError.invalidArgument);
    } else if (sets.length != 1 || sets.single.any((v) => v < 0 || v > 99)) {
      _fail(TournamentError.invalidArgument);
    }
    return [
      for (final s in sets) [s[0], s[1]],
    ];
  }

  /// Enters or corrects a match's result.
  CategoryDraw enterScore(String userId, String matchId, MatchOutcome outcome, {Side? winner, List<List<int>>? sets}) {
    final (d0, _) = _find(matchId) ?? _fail(TournamentError.notFound);
    _lockDraw(userId, d0.categoryId);
    return _txn(d0.categoryId, () {
      final d = _draws[d0.categoryId]!;
      if (!d.published) _fail(TournamentError.notFound);
      final m = d.matches.firstWhere((m) => m.id == matchId);
      if (m.sideA == null || m.sideB == null || m.outcome == MatchOutcome.bye || m.outcome == MatchOutcome.none) {
        _fail(TournamentError.notFound);
      }
      final sport = tournaments.info(d.tournamentId)!.sportId;
      final rated = isRated(sport);
      final bool named = winner == Side.a || winner == Side.b;
      final List<List<int>>? stored;
      final Side won;
      switch (outcome) {
        case MatchOutcome.played:
          stored = _checkedSets(sets, rated: rated);
          if (rated) {
            won = switch (matchWinner([for (final s in stored) (s[0], s[1])])) {
              MatchWinner.a => Side.a,
              MatchWinner.b => Side.b,
              MatchWinner.draw => Side.draw,
            };
          } else {
            final [a, b] = stored.single;
            won = a > b ? Side.a : (a < b ? Side.b : Side.draw);
          }
        case MatchOutcome.decider:
          if (rated || m.stage != MatchStage.knockout || !named) _fail(TournamentError.invalidArgument);
          stored = _checkedSets(sets, rated: false);
          if (stored.single[0] != stored.single[1]) _fail(TournamentError.invalidArgument);
          won = winner!;
        case MatchOutcome.walkover:
          if (!named) _fail(TournamentError.invalidArgument);
          stored = null;
          won = winner!;
        case MatchOutcome.retired:
          if (!named) _fail(TournamentError.invalidArgument);
          stored = _checkedSets(sets, rated: rated);
          won = winner!;
        case MatchOutcome.bye || MatchOutcome.none:
          _fail(TournamentError.invalidArgument);
      }
      if (won == Side.draw && m.stage == MatchStage.knockout) _fail(TournamentError.drawNotAllowed);

      // A withdrawn entry wins nothing it had not already won.
      final entry = switch (won) {
        Side.a => m.sideA,
        Side.b => m.sideB,
        Side.draw => null,
      };
      if (entry != null && _withdrawn(d, entry) && (m.status != MatchStatus.done || m.winner != won)) {
        _fail(TournamentError.invalidArgument);
      }

      final correction = m.status == MatchStatus.done;
      if (correction) {
        if (m.stage == MatchStage.knockout) {
          if (_next(d, m) case final next? when _scored.contains(next.outcome)) _fail(TournamentError.nextMatchPlayed);
        } else if (d.matches.any(
          (k) => k.stage == MatchStage.knockout && k.outcome != null && k.outcome != MatchOutcome.bye,
        )) {
          _fail(TournamentError.nextMatchPlayed);
        }
      }

      final wonBefore = _result(d).winner;
      final previous = m.copy();
      m
        ..status = MatchStatus.done
        ..outcome = outcome
        ..winner = won
        ..sets = stored
        ..scoredBy = userId
        ..scoredAt = utcNow();
      if (outcome == MatchOutcome.walkover) _notPlayed(d, m);
      d.firstScoreAt ??= utcNow();

      if (m.stage == MatchStage.knockout) {
        final before = previous.status == MatchStatus.done ? previous.winnerEntry : null;
        if (m.winnerEntry != before) {
          _placeWinner(d, m);
          // The next match's players hear that their opponent changed.
          if (correction) {
            if (_next(d, m) case final next?) {
              final mine = _matchPlayers(m);
              _notifyResult(d, m, [
                for (final p in _matchPlayers(next))
                  if (!mine.contains(p)) p,
              ], correction: true);
            }
          }
        }
      } else {
        _fillKnockout(d);
      }

      _notifyResult(d, m, _matchPlayers(m), correction: correction);
      _announce(d, wonBefore);
      log(
        'enter_match_score',
        'tournament_match',
        m.id,
        before: correction
            ? {'outcome': previous.outcome?.name, 'winner': previous.winner?.name, 'sets': previous.sets}
            : null,
        after: {'outcome': m.outcome?.name, 'winner': m.winner?.name, 'sets': m.sets},
      );
      _afterScored(d, m);
      return _drawView(d, userId)!;
    });
  }

  // ---- Ratings (app.after_match_scored) ----

  /// Rated sports: the result in force for the match is taken back (each
  /// player's stored change off their rating, one rated game fewer); then a
  /// played match writes a new result and applies it at once.
  void _afterScored(_Draw d, _Match m) {
    final t = tournaments.info(d.tournamentId)!;
    final sport = t.sportId;
    if (!isRated(sport)) return;
    final old = _results.remove(m.id);
    for (final MapEntry(key: id, value: change) in (old ?? const <String, RatingChange>{}).entries) {
      final current = ratingOf(id, sport);
      if (current == null) continue;
      final rating = math.min(RatingRules.max, math.max(RatingRules.min, roundRating(current.rating - change.delta)));
      setRating(id, sport, SportRating(rating: rating, ratedGames: math.max(0, current.ratedGames - 1)));
    }
    if (m.outcome != MatchOutcome.played) return;

    final sideA = _players(m.sideA), sideB = _players(m.sideB);
    final note = {
      'tournament_id': t.id,
      'category_id': d.categoryId,
      'match_id': m.id,
      'title_uz': t.title.uz,
      'title_ru': t.title.ru,
      'title_kk': t.title.kk,
      'title_en': t.title.en,
      'result_id': 'tr${_nextId++}',
    };
    final everyone = [...sideA, ...sideB];
    if (sideA.isEmpty || sideA.length != sideB.length || everyone.any(isDeleted)) {
      // Unplayable (app.result_unplayable): void, and the others hear.
      for (final p in everyone) {
        if (!isDeleted(p)) notify(p, 'score_resolved', 'ratings', {...note, 'action': 'void'});
      }
      return;
    }
    final changes = ratingChanges(
      sideA: [for (final p in sideA) ratingOf(p, sport)],
      sideB: [for (final p in sideB) ratingOf(p, sport)],
      sets: [for (final s in m.sets!) (s[0], s[1])],
    );
    final byPlayer = {
      for (final (i, p) in sideA.indexed) p: changes.a[i],
      for (final (i, p) in sideB.indexed) p: changes.b[i],
    };
    for (final MapEntry(key: p, value: change) in byPlayer.entries) {
      final played = ratingOf(p, sport)?.ratedGames ?? 0;
      setRating(p, sport, SportRating(rating: change.newRating, ratedGames: played + 1));
      notify(p, 'rating_updated', 'ratings', {...note, 'old': change.oldRating, 'new': change.newRating});
    }
    _results[m.id] = byPlayer;
  }

  // ---- Withdrawals (app.withdraw_locked) ----

  /// The organiser withdraws an entry of a locked category.
  CategoryDraw withdraw(String userId, String registrationId) {
    final e = tournaments.entry(registrationId) ?? _fail(TournamentError.notFound);
    _lockDraw(userId, e.categoryId);
    _txn(e.categoryId, () => _withdrawLocked(userId, registrationId, e.categoryId));
    return _drawView(_draws[e.categoryId]!, userId)!;
  }

  /// A deleted account leaves every locked category it is in the same way
  /// (`app.delete_account`, §14a.9).
  void accountDeleted(String userId) {
    for (final e in tournaments.registeredEntriesOf(userId)) {
      if (!locked(e.categoryId)) continue;
      _txn(e.categoryId, () => _withdrawLocked(null, e.id, e.categoryId));
    }
  }

  /// The registration becomes removed. In a published draw that is not
  /// finished, every unplayed match of the entry with the other side known is
  /// a walkover for that side; otherwise its side becomes empty and the match
  /// settles when the other side arrives. A knockout walkover it won over
  /// another withdrawn entry becomes a match with no winner.
  void _withdrawLocked(String? actor, String registrationId, String categoryId) {
    final d = _draws[categoryId];
    if (d == null || !d.locked) _fail(TournamentError.notFound);
    final e = tournaments.entry(registrationId);
    if (e == null || e.categoryId != categoryId || e.status != RegistrationStatus.registered) {
      _fail(TournamentError.notFound);
    }
    final result = _result(d);
    final groupsDone = !d.matches.any((m) => m.stage == MatchStage.group && m.status != MatchStatus.done);
    _later(() => tournaments.withdraw(registrationId));

    // A finished category keeps its result: the entry only leaves.
    if (d.published && !result.finished) {
      for (final entry in d.entries) {
        if (entry.registrationId == registrationId) entry.withdrawn = true;
      }
      final walkovers = d.matches.where((m) {
        if (m.stage != MatchStage.knockout ||
            m.status != MatchStatus.done ||
            m.outcome != MatchOutcome.walkover ||
            m.winnerEntry != registrationId) {
          return false;
        }
        final loser = m.winner == Side.a ? m.sideB : m.sideA;
        final next = _next(d, m);
        return loser != null && _withdrawn(d, loser) && next != null && next.status != MatchStatus.done;
      }).toList()..sort(_byRoundPosition);
      for (final m in walkovers) {
        m
          ..outcome = MatchOutcome.none
          ..winner = null
          ..scoredBy = actor
          ..scoredAt = utcNow();
        _placeWinner(d, m);
      }

      final open =
          d.matches
              .where((m) => m.status != MatchStatus.done && (m.sideA == registrationId || m.sideB == registrationId))
              .toList()
            ..sort((a, b) {
              final byStage = a.stage.index.compareTo(b.stage.index);
              if (byStage != 0) return byStage;
              final byRound = _byRoundPosition(a, b);
              return byRound != 0 ? byRound : a.id.compareTo(b.id);
            });
      for (final m in open) {
        // Settling an earlier one may have moved it on.
        if (m.status == MatchStatus.done || (m.sideA != registrationId && m.sideB != registrationId)) continue;
        final other = m.sideA == registrationId ? m.sideB : m.sideA;
        if (other != null) {
          m
            ..status = MatchStatus.done
            ..outcome = MatchOutcome.walkover
            ..winner = m.sideA == registrationId ? Side.b : Side.a
            ..sets = null
            ..scoredBy = actor
            ..scoredAt = utcNow();
          _notPlayed(d, m);
          _placeWinner(d, m);
        } else {
          if (m.sideA == registrationId) {
            m
              ..sideA = null
              ..aEmpty = true;
          }
          if (m.sideB == registrationId) {
            m
              ..sideB = null
              ..bEmpty = true;
          }
          _settle(d, m);
        }
      }
      // The walkovers may have finished the groups.
      if (!groupsDone) _fillKnockout(d);
    }

    final note = {...tournaments.note(d.tournamentId, categoryId), 'registration_id': registrationId};
    for (final p in _players(registrationId)) {
      _notify(p, 'entry_withdrawn', note);
    }
    _announce(d, result.winner);
    _later(() => log('withdraw_entry', 'tournament_registration', registrationId));
  }

  static int _byRoundPosition(_Match a, _Match b) {
    final byRound = a.round.compareTo(b.round);
    return byRound != 0 ? byRound : a.position.compareTo(b.position);
  }

  // ---- The entry lock and admin edits (SampleDrawGuard) ----

  @override
  bool locked(String categoryId) => _draws[categoryId]?.locked ?? false;

  @override
  bool hasDraw(String categoryId) => _draws.containsKey(categoryId);

  @override
  void entriesChanged(String categoryId) {
    final d = _draws[categoryId];
    if (d != null && !d.published) d.outdated = true;
  }

  @override
  bool scheduledOutside(String tournamentId, DateTime start, DateTime end) => _drawsOf(tournamentId).any(
    (d) => d.matches.any((m) {
      final s = m.startsAt;
      return s != null && (dateOnly(s).isBefore(start) || dateOnly(s).isAfter(end));
    }),
  );

  @override
  void hidden(String tournamentId) {
    for (final d in _drawsOf(tournamentId)) {
      for (final m in d.matches) {
        if (m.status == MatchStatus.done || (m.startsAt == null && m.courtId == null)) continue;
        _release(m);
        m
          ..courtId = null
          ..startsAt = null;
      }
    }
  }

  /// A tournament match's calendar block: the organiser's to move or clear,
  /// never the owner's.
  bool isMatchBlock(String bookingId) => matchBlock(bookingId) != null;

  /// The tournament match whose calendar block [bookingId] is, for the
  /// owner's calendar (`owner_calendar`'s `tournament`).
  TournamentBlockRef? matchBlock(String bookingId) {
    for (final d in _draws.values) {
      for (final m in d.matches) {
        if (m.blockId == bookingId) {
          return TournamentBlockRef(title: tournaments.info(d.tournamentId)!.title, matchId: m.id);
        }
      }
    }
    return null;
  }

  // ---- Views ----

  /// The match as the bracket rules read it (no court or clash).
  static TournamentMatch _plain(_Match m) => TournamentMatch(
    id: m.id,
    stage: m.stage,
    round: m.round,
    position: m.position,
    status: m.status,
    groupId: m.groupId,
    sideA: m.sideA,
    sideB: m.sideB,
    outcome: m.outcome,
    winner: m.winner,
    sets: m.sets,
  );

  TournamentMatch _view(_Draw d, _Match m) {
    final court = m.courtId == null ? null : courtOf(m.courtId!);
    final span = _span(m);
    return TournamentMatch(
      id: m.id,
      stage: m.stage,
      round: m.round,
      position: m.position,
      status: m.status,
      groupId: m.groupId,
      sideA: m.sideA,
      sideB: m.sideB,
      aEmpty: m.aEmpty,
      bEmpty: m.bEmpty,
      outcome: m.outcome,
      winner: m.winner,
      sets: m.sets == null ? null : [for (final s in m.sets!) List.unmodifiable(s)],
      courtId: m.courtId,
      courtName: court?.name,
      startsAt: m.startsAt,
      endsAt: court == null ? null : span?.end,
      placeNote: m.placeNote,
      clash: span != null && _busy(d.tournamentId, m.id, _matchPlayers(m), span),
    );
  }

  /// The category's draw as [userId] may see it: drafts only for organisers.
  CategoryDraw? _drawView(_Draw d, String userId) {
    if (!d.published && !isOrganizer(userId, d.tournamentId)) return null;
    final result = _result(d);
    final groupSort = {for (final g in d.groups) g.id: g.sortOrder};
    final matches = [...d.matches]
      ..sort((a, b) {
        for (final c in [
          a.stage.index.compareTo(b.stage.index),
          a.round.compareTo(b.round),
          (groupSort[a.groupId] ?? 0).compareTo(groupSort[b.groupId] ?? 0),
          a.position.compareTo(b.position),
        ]) {
          if (c != 0) return c;
        }
        return 0;
      });
    return CategoryDraw(
      categoryId: d.categoryId,
      format: d.format,
      published: d.published,
      groupSize: d.groupSize,
      advance: d.advance,
      outdated: d.outdated,
      entries: [
        for (final e in [...d.entries]..sort((a, b) => a.seed.compareTo(b.seed)))
          DrawEntry(
            registrationId: e.registrationId,
            seed: e.seed,
            strength: e.strength,
            groupId: e.groupId,
            withdrawn: e.withdrawn,
            players: [
              for (final p in _players(e.registrationId)) PlayerRef(id: p, name: nameOf(p), deleted: isDeleted(p)),
            ],
          ),
      ],
      groups: [for (final g in d.groups) DrawGroup(id: g.id, label: g.label, standings: _standings(d, g))],
      matches: [for (final m in matches) _view(d, m)],
      winner: result.winner,
      runnerUp: result.runnerUp,
      finished: result.finished,
    );
  }

  /// What the tournament page shows of the brackets.
  TournamentBracket bracket(String userId, String tournamentId) {
    final t = tournaments.info(tournamentId);
    final organizer = isOrganizer(userId, tournamentId);
    if (t == null || !(t.active || organizer)) _fail(TournamentError.notFound);
    final categories = tournaments.categoryIds(tournamentId);
    final venue = t.venueId == null ? null : venueOf(t.venueId!);

    final mine =
        [
          for (final (i, id) in categories.indexed)
            if (_draws[id] case final d? when d.published)
              for (final m in d.matches)
                if (m.status != MatchStatus.done && _matchPlayers(m).contains(userId)) (i, d, m),
        ]..sort((x, y) {
          final (xi, _, a) = x;
          final (yi, _, b) = y;
          for (final c in [
            _nullsLast(a.startsAt, b.startsAt),
            a.stage.index.compareTo(b.stage.index),
            a.round.compareTo(b.round),
            xi.compareTo(yi),
            a.position.compareTo(b.position),
          ]) {
            if (c != 0) return c;
          }
          return 0;
        });
    final drawn = [for (final id in categories) ?_draws[id]];
    return TournamentBracket(
      organizer: organizer,
      draws: [for (final d in drawn) ?_drawView(d, userId)],
      myNextMatch: mine.isEmpty
          ? null
          : NextMatch(match: _view(mine.first.$2, mine.first.$3), categoryId: mine.first.$2.categoryId),
      finished: drawn.isNotEmpty && drawn.every((d) => _result(d).finished),
      courts: !organizer || venue == null
          ? const []
          : [
              for (final c in venue.courts)
                if (courtActive(c.id)) CourtRef(id: c.id, name: c.name, slotMinutes: c.slotMinutes),
            ],
    );
  }

  static int _nullsLast(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  /// The player's matches in published draws of active tournaments (byes and
  /// matches without a winner left out): those to play first, by start
  /// time, then the finished ones, latest first.
  List<MyMatch> myMatches(String userId) {
    final rows =
        <(SampleTournamentInfo, _Draw, _Match)>[
          for (final d in _draws.values)
            if (d.published)
              if (tournaments.info(d.tournamentId) case final t? when t.active)
                for (final m in d.matches)
                  if (m.outcome != MatchOutcome.bye &&
                      m.outcome != MatchOutcome.none &&
                      _matchPlayers(m).contains(userId))
                    (t, d, m),
        ]..sort((x, y) {
          final (ta, _, a) = x;
          final (tb, _, b) = y;
          final aDone = a.status == MatchStatus.done, bDone = b.status == MatchStatus.done;
          for (final c in [
            (aDone ? 1 : 0).compareTo(bDone ? 1 : 0),
            _nullsLast(aDone ? null : a.startsAt, bDone ? null : b.startsAt),
            ta.start.compareTo(tb.start),
            // Latest first; none yet first, as the database sorts nulls.
            -_nullsLast(a.scoredAt, b.scoredAt),
            a.stage.index.compareTo(b.stage.index),
            a.round.compareTo(b.round),
            a.position.compareTo(b.position),
            a.id.compareTo(b.id),
          ]) {
            if (c != 0) return c;
          }
          return 0;
        });
    return [
      for (final (t, d, m) in rows)
        MyMatch(match: _view(d, m), tournamentId: t.id, title: t.title, categoryId: d.categoryId),
    ];
  }

  // ---- Sample data ----

  /// Tournament t1's men's pairs: a published 8-entry knockout whose
  /// quarter-finals were played on the first morning and whose semi-finals
  /// are on both courts at 10:00. The demo player (with Bekzod) is the first
  /// seed and plays the first semi-final; the demo player organises t1.
  void seed() {
    const categoryId = 't1c2';
    final t = tournaments.info('t1');
    if (t == null || tournaments.tournamentOf(categoryId) != 't1') return;
    _organizers['t1'] = {kMeId};
    for (final (i, (a, b)) in kSampleBracketPairs.indexed) {
      tournaments.seedEntry('t1c2-e${i + 1}', categoryId, a, partnerId: b, seq: i - kSampleBracketPairs.length);
    }
    final d = _Draw(categoryId, 't1', DrawFormat.knockout)
      ..entries = [
        for (var i = 0; i < kSampleBracketPairs.length; i++)
          _DrawEntry('t1c2-e${i + 1}', i + 1, _seedStrength(kSampleBracketPairs[i], t.sportId)),
      ];
    _draws[categoryId] = d;
    _buildMatches(d);
    d
      ..published = true
      ..locked = true
      ..firstScoreAt = utcNow();

    DateTime at(int hour, int minute) => t.start.add(Duration(hours: hour, minutes: minute));
    void place(_Match m, String courtId, DateTime start) {
      final court = courtOf(courtId);
      if (court == null) return;
      final span = _Span(start, start.add(Duration(minutes: court.slotMinutes)));
      m
        ..blockId = _block(t, court, span)
        ..courtId = courtId
        ..startsAt = start;
    }

    const quarterFinals = [
      (
        'v1c1',
        7,
        0,
        Side.a,
        [
          [6, 3],
          [6, 4],
        ],
      ),
      (
        'v1c2',
        7,
        0,
        Side.a,
        [
          [4, 6],
          [6, 3],
          [7, 5],
        ],
      ),
      (
        'v1c1',
        8,
        30,
        Side.a,
        [
          [6, 2],
          [6, 2],
        ],
      ),
      (
        'v1c2',
        8,
        30,
        Side.b,
        [
          [3, 6],
          [4, 6],
        ],
      ),
    ];
    for (final (i, (court, hour, minute, winner, sets)) in quarterFinals.indexed) {
      final m = _ko(d, 1, i + 1)!;
      place(m, court, at(hour, minute));
      m
        ..status = MatchStatus.done
        ..outcome = MatchOutcome.played
        ..winner = winner
        ..sets = sets
        ..scoredBy = kMeId
        ..scoredAt = utcNow();
      _placeWinner(d, m);
    }
    place(_ko(d, 2, 1)!, 'v1c1', at(10, 0));
    place(_ko(d, 2, 2)!, 'v1c2', at(10, 0));
  }

  double _seedStrength((String, String) pair, String sportId) =>
      ((strengthOf(pair.$1, sportId) + strengthOf(pair.$2, sportId)) / 2 * 100).round() / 100;
}

/// The pairs of the sample bracket in seed order: the demo player with
/// Bekzod first, then players who only appear in this draw.
const kSampleBracketPairs = [
  (kMeId, 'p7'),
  ('bp1', 'bp2'),
  ('bp3', 'bp4'),
  ('bp5', 'bp6'),
  ('bp7', 'bp8'),
  ('bp9', 'bp10'),
  ('bp11', 'bp12'),
  ('bp13', 'bp14'),
];

/// Names of the players who only appear in the sample bracket. Fictional.
const kSampleBracketPlayers = <String, String>{
  'bp1': 'Rustam',
  'bp2': 'Jasur',
  'bp3': 'Sherzod',
  'bp4': 'Otabek',
  'bp5': 'Farrukh',
  'bp6': 'Ulugbek',
  'bp7': 'Davron',
  'bp8': 'Akmal',
  'bp9': 'Bobur',
  'bp10': 'Nodir',
  'bp11': 'Shohruh',
  'bp12': 'Eldor',
  'bp13': 'Islom',
  'bp14': 'Kamron',
};

/// A stretch of time: one court slot `[start, end)`, or a single instant
/// (a match without a court).
class _Span {
  const _Span(this.start, this.end, {this.point = false});

  final DateTime start;
  final DateTime end;
  final bool point;

  bool overlaps(_Span o) {
    if (point && o.point) return start == o.start;
    if (point) return !o.start.isAfter(start) && start.isBefore(o.end);
    if (o.point) return o.overlaps(this);
    return start.isBefore(o.end) && o.start.isBefore(end);
  }
}

class _Draw {
  _Draw(this.categoryId, this.tournamentId, this.format);

  final String categoryId;
  final String tournamentId;
  DrawFormat format;
  int? groupSize;
  int? advance;
  bool published = false;

  /// Published once: the category's entries stay locked, a redo included.
  bool locked = false;
  bool outdated = false;
  DateTime? firstScoreAt;
  List<_DrawEntry> entries = [];
  List<_Group> groups = [];
  List<_Match> matches = [];

  _Draw copy() => _Draw(categoryId, tournamentId, format)
    ..groupSize = groupSize
    ..advance = advance
    ..published = published
    ..locked = locked
    ..outdated = outdated
    ..firstScoreAt = firstScoreAt
    ..entries = [
      for (final e in entries)
        _DrawEntry(e.registrationId, e.seed, e.strength)
          ..groupId = e.groupId
          ..withdrawn = e.withdrawn,
    ]
    ..groups = [...groups]
    ..matches = [for (final m in matches) m.copy()];
}

class _DrawEntry {
  _DrawEntry(this.registrationId, this.seed, this.strength);

  final String registrationId;
  int seed;
  final double strength;
  String? groupId;
  bool withdrawn = false;
}

class _Group {
  const _Group(this.id, this.label, this.sortOrder);

  final String id;
  final String label;
  final int sortOrder;
}

class _Match {
  _Match(this.id, this.stage, this.round, this.position, {this.groupId});

  final String id;
  final MatchStage stage;
  final String? groupId;
  final int round;
  final int position;
  String? sideA;
  String? sideB;
  bool aEmpty = false;
  bool bEmpty = false;
  MatchStatus status = MatchStatus.waiting;
  MatchOutcome? outcome;
  Side? winner;
  List<List<int>>? sets;
  String? courtId;
  DateTime? startsAt;
  String? placeNote;

  /// The calendar block of a scheduled match at a venue.
  String? blockId;
  String? scoredBy;
  DateTime? scoredAt;

  String? get winnerEntry => switch (winner) {
    Side.a => sideA,
    Side.b => sideB,
    _ => null,
  };

  _Match copy() => _Match(id, stage, round, position, groupId: groupId)
    ..sideA = sideA
    ..sideB = sideB
    ..aEmpty = aEmpty
    ..bEmpty = bEmpty
    ..status = status
    ..outcome = outcome
    ..winner = winner
    ..sets = sets
    ..courtId = courtId
    ..startsAt = startsAt
    ..placeNote = placeNote
    ..blockId = blockId
    ..scoredBy = scoredBy
    ..scoredAt = scoredAt;
}
