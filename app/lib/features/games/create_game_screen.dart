import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/competitive.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/teams.dart';
import '../../state/providers.dart';
import '../../state/ui_providers.dart';
import '../common/formatters.dart';
import '../common/rating_pill.dart';
import '../common/widgets.dart';
import 'game_pickers.dart';
import 'host_tools.dart';

/// Start a game. The sport comes first: a bookable sport sits on one of the
/// player's own upcoming bookings, a place-only one on a venue or a meeting
/// point. A captain may post it for a team of theirs in that sport and city.
/// Opens the new game when it is created.
class CreateGameScreen extends ConsumerStatefulWidget {
  const CreateGameScreen({super.key, this.bookingId, this.teamId});

  /// A booking to start from, when the player came from "My bookings".
  final String? bookingId;

  /// A team to post for, when the captain came from the team page; it
  /// chooses the sport too.
  final String? teamId;

  @override
  ConsumerState<CreateGameScreen> createState() => _CreateGameScreenState();
}

class _CreateGameScreenState extends ConsumerState<CreateGameScreen> {
  static const _days = 14;
  static const _durations = [30, 60, 90, 120, 180];

  final _form = GlobalKey<FormState>();
  final _place = PlaceController();
  final _note = TextEditingController();

  String? _sportId;
  late String? _bookingId = widget.bookingId;
  int _dayOffset = 1;
  int _startMinute = 18 * 60;
  int _duration = 60;
  int? _spots;
  RangeValues _levels = const RangeValues(1, 5);

  /// The range of a game in a rated sport (padel, tennis).
  RangeValues _ratings = kAllRatings;
  GameVisibility _visibility = GameVisibility.public;

  /// The team the game is for: one the player captains in the sport and city.
  late String? _teamId = widget.teamId;

  /// Hours before the start a team game opens to everyone; null for never.
  int? _openHours;
  bool _busy = false;
  String? _error;

  @override
  void didUpdateWidget(CreateGameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The open form reached again by "Post a game": it is now for that team,
    // in the team's sport.
    if (widget.teamId != null && widget.teamId != oldWidget.teamId) {
      _teamId = widget.teamId;
      _openHours = null;
      _sportId = null;
    }
  }

  @override
  void dispose() {
    _place.dispose();
    _note.dispose();
    super.dispose();
  }

  void _back() => context.canPop() ? context.pop() : context.go('/games');

  Future<void> _pickTime() async {
    final picked = await pickMinuteOfDay(context, _startMinute);
    if (picked != null) setState(() => _startMinute = picked);
  }

  Future<void> _create({
    required Sport sport,
    required String? bookingId,
    required Team? team,
    required DateTime today,
  }) async {
    final l = context.l;
    if (!sport.bookable && !_form.currentState!.validate()) return;
    if (!sport.bookable && !_place.atMeetingPoint && _place.venueId == null) {
      setState(() => _error = l.venueRequired);
      return;
    }
    final distanceText = _place.distance.text.trim().replaceAll(',', '.');
    final distance = distanceText.isEmpty ? null : double.tryParse(distanceText);
    if (distanceText.isNotEmpty && (distance == null || distance <= 0)) {
      setState(() => _error = l.errInvalidArgument);
      return;
    }
    // A padel or tennis host answers the questionnaire first.
    if (!await ensureRated(context, ref, sport) || !mounted) return;

    String? blank(String text) => text.trim().isEmpty ? null : text.trim();
    final start = today.add(Duration(days: _dayOffset, minutes: _startMinute));
    final rated = sport.competitiveRating;
    final draft = GameDraft(
      sportId: sport.id,
      spots: _spots ?? sport.defaultPlayers.clamp(SpotsStepper.min, SpotsStepper.max),
      // In a rated sport the server derives the levels from the rating range, as here.
      minLevel: rated ? levelOfRating(_ratings.start) : _levels.start.round(),
      maxLevel: rated ? levelOfRating(_ratings.end) : _levels.end.round(),
      minRating: rated ? _ratings.start : null,
      maxRating: rated ? _ratings.end : null,
      // A team game is stored invite-only whatever is sent.
      visibility: team == null ? _visibility : GameVisibility.inviteOnly,
      teamId: team?.id,
      openHoursBefore: team == null ? null : _openHours,
      note: blank(_note.text),
      pace: sport.bookable ? null : blank(_place.pace.text),
      distanceKm: sport.bookable ? null : distance,
      bookingId: sport.bookable ? bookingId : null,
      venueId: !sport.bookable && !_place.atMeetingPoint ? _place.venueId : null,
      meetingPoint: !sport.bookable && _place.atMeetingPoint ? blank(_place.meeting.text) : null,
      start: sport.bookable ? null : start,
      end: sport.bookable ? null : start.add(Duration(minutes: _duration)),
    );

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final game = await ref.read(gameRepositoryProvider).create(draft);
      refreshGames(ref);
      // The team's tiles count its upcoming games.
      if (team != null) refreshTeams(ref);
      // A game lives in the Games tab: go, not push, so the stack is Games then the game.
      if (mounted) context.go('/games/${game.id}');
    } on JoinException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = joinErrorText(l, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final city = ref.watch(currentCityProvider);
    final today = dateOnly(ref.watch(cityNowProvider)());

    // The player's own upcoming confirmed bookings that have no game yet.
    final (:choices, loading: loadingVenues) = bookingChoices(ref);

    // Coming from a booking or a team chooses its sport too.
    final teams = ref.watch(teamsProvider).valueOrNull ?? const <Team>[];
    final fromBooking = choices.where((c) => c.booking.id == widget.bookingId).firstOrNull;
    final fromTeam = teams.where((t) => t.id == widget.teamId && t.isCaptain).firstOrNull;
    final sportId = _sportId ?? fromBooking?.court.sportId ?? fromTeam?.sportId;
    final sport = sports.where((s) => s.id == sportId).firstOrNull;
    final forSport = [
      for (final c in choices)
        if (c.court.sportId == sportId) c,
    ];
    final chosen = forSport.where((c) => c.booking.id == _bookingId).firstOrNull;
    // Teams the player captains in this sport, in the game's city: the
    // booking's venue, or the current city until one is chosen.
    final gameCityId = chosen?.venue.cityId ?? city.id;
    final myTeams = [
      for (final t in teams)
        if (t.isCaptain && t.sportId == sportId && t.cityId == gameCityId) t,
    ];
    final team = myTeams.where((t) => t.id == _teamId).firstOrNull;
    // A team chosen before (or by "Post a game") that this game cannot be
    // for: the booking or the current city is not the team's. It stays in
    // view, and nothing is created until the player picks a booking there or
    // chooses who else can join: never silently a public game.
    final stranded = team == null
        ? teams.where((t) => t.id == _teamId && t.isCaptain && t.sportId == sportId).firstOrNull
        : null;
    final spots = _spots ?? (sport?.defaultPlayers ?? 4).clamp(SpotsStepper.min, SpotsStepper.max);
    final canCreate = sport != null && !_busy && (!sport.bookable || chosen != null) && stranded == null;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(l.createGame),
      ),
      body: Column(
        children: [
          Expanded(
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                children: [
                  SectionCard(
                    title: l.gameSportLabel,
                    child: Wrap(
                      runSpacing: 8,
                      children: [
                        for (final s in sports)
                          FilterChipButton(
                            label: s.name.resolve(context.lang),
                            selected: s.id == sportId,
                            onTap: () => setState(() {
                              // Another sport has other teams.
                              if (s.id != sportId) _clearTeam();
                              _sportId = s.id;
                              _error = null;
                            }),
                          ),
                      ],
                    ),
                  ),
                  if (sport == null)
                    EmptyState(icon: Icons.sports_outlined, text: l.pickSportHint)
                  else ...[
                    if (sport.bookable)
                      SectionCard(
                        title: l.gameBookingLabel,
                        child: loadingVenues
                            ? const Center(child: CircularProgressIndicator())
                            : forSport.isEmpty
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.noBookingForSport, style: AppText.muted.copyWith(fontSize: 15)),
                                  const SizedBox(height: 12),
                                  OutlinedButton(onPressed: () => context.go('/venues'), child: Text(l.bookACourt)),
                                ],
                              )
                            : Column(
                                children: [
                                  for (final c in forSport)
                                    BookingTile(
                                      key: ValueKey('booking-${c.booking.id}'),
                                      choice: c,
                                      selected: c.booking.id == chosen?.booking.id,
                                      onTap: () => setState(() => _bookingId = c.booking.id),
                                    ),
                                ],
                              ),
                      )
                    else ...[
                      _placeSection(sport, city.id),
                      _whenSection(today),
                    ],
                    SectionCard(
                      title: l.spotsLabel,
                      child: Row(
                        children: [
                          SpotsStepper(value: spots, onChanged: (v) => setState(() => _spots = v)),
                          const SizedBox(width: 12),
                          // Wraps on a narrow phone in Russian or Kazakh.
                          if (chosen != null)
                            Expanded(
                              child: Text(
                                l.perPlayer(
                                  money(
                                    l,
                                    (chosen.booking.totalPrice + spots - 1) ~/ spots,
                                    cityById(chosen.venue.cityId).currency,
                                  ),
                                ),
                                textAlign: TextAlign.end,
                                style: AppText.bodyStrong,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (sport.competitiveRating)
                      LevelRangeCard(rated: true, values: _ratings, onChanged: (v) => setState(() => _ratings = v))
                    else
                      LevelRangeCard(values: _levels, onChanged: (v) => setState(() => _levels = v)),
                    if (myTeams.isEmpty && stranded == null)
                      SectionCard(
                        title: l.visibilityLabel,
                        child: SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<GameVisibility>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(value: GameVisibility.public, label: Text(l.visibilityPublic)),
                              ButtonSegment(value: GameVisibility.inviteOnly, label: Text(l.visibilityInviteOnly)),
                            ],
                            selected: {_visibility},
                            onSelectionChanged: (v) => setState(() => _visibility = v.first),
                          ),
                        ),
                      )
                    else ...[
                      _whoSection(myTeams, team, stranded: stranded),
                      if (team != null) _opensSection(),
                    ],
                    SectionCard(
                      title: l.noteLabel,
                      child: TextField(
                        key: const ValueKey('game-note'),
                        controller: _note,
                        maxLength: 200,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: manrope(13.5, 600, color: AppColors.error),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('create-game-submit'),
                        onPressed: canCreate
                            ? () => _create(sport: sport, bookingId: chosen?.booking.id, team: team, today: today)
                            : null,
                        child: Text(l.createGame),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _public = '_public';
  static const _inviteOnly = '_invite';

  /// No team any more: nor its opening time.
  void _clearTeam() {
    _teamId = null;
    _openHours = null;
  }

  /// Everyone, invite only, or one of the teams the player captains.
  /// [stranded]: the team chosen before that plays in another city; shown
  /// chosen but disabled, with where it plays.
  Widget _whoSection(List<Team> teams, Team? team, {Team? stranded}) {
    final l = context.l;
    final selected = team?.id ?? stranded?.id ?? (_visibility == GameVisibility.public ? _public : _inviteOnly);
    Widget choice(String key, String value, String label, IconData icon, {String? note}) => RadioListTile<String>(
      key: ValueKey(key),
      contentPadding: EdgeInsets.zero,
      value: value,
      groupValue: selected,
      onChanged: note != null
          ? null
          : (v) => setState(() {
              if (v == _public || v == _inviteOnly) {
                _clearTeam();
                _visibility = v == _public ? GameVisibility.public : GameVisibility.inviteOnly;
              } else {
                _teamId = v;
              }
            }),
      title: Text(label, style: AppText.bodyStrong),
      subtitle: note == null ? null : Text(note, style: manrope(13.5, 600, color: AppColors.error)),
      secondary: Icon(icon, color: AppColors.muted),
    );

    return SectionCard(
      title: l.whoCanJoin,
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          choice('who-public', _public, l.visibilityPublic, Icons.public_rounded),
          choice('who-invite', _inviteOnly, l.visibilityInviteOnly, Icons.lock_outline_rounded),
          for (final t in teams) choice('who-team-${t.id}', t.id, l.teamGameChoice(t.name), Icons.groups_outlined),
          if (stranded != null)
            choice(
              'who-team-${stranded.id}',
              stranded.id,
              l.teamGameChoice(stranded.name),
              Icons.groups_outlined,
              note: l.teamPlaysIn(cityById(stranded.cityId).name.resolve(context.lang)),
            ),
        ],
      ),
    );
  }

  /// When a team game opens to everyone while spots remain: never, or some
  /// hours before the start.
  Widget _opensSection() {
    final l = context.l;
    return SectionCard(
      title: l.openToEveryoneLabel,
      child: Wrap(
        runSpacing: 8,
        children: [
          FilterChipButton(
            key: const ValueKey('open-hours-never'),
            label: l.openNever,
            selected: _openHours == null,
            onTap: () => setState(() => _openHours = null),
          ),
          for (final hours in GameDraft.openHoursChoices)
            FilterChipButton(
              key: ValueKey('open-hours-$hours'),
              label: l.openHoursBefore(hours),
              selected: _openHours == hours,
              onTap: () => setState(() => _openHours = hours),
            ),
        ],
      ),
    );
  }

  /// Venue or meeting point, plus distance and pace for running.
  Widget _placeSection(Sport sport, String cityId) {
    return SectionCard(
      title: context.l.gamePlaceLabel,
      child: PlaceFields(
        sport: sport,
        cityId: cityId,
        controller: _place,
        onModeChanged: () => setState(() => _error = null),
      ),
    );
  }

  /// The day, the start and how long, for a game that has no booking.
  Widget _whenSection(DateTime today) {
    final l = context.l;
    final now = ref.watch(cityNowProvider)();
    final start = today.add(Duration(days: _dayOffset, minutes: _startMinute));

    return SectionCard(
      title: l.gameWhenLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DayStrip(
            today: today,
            now: now,
            selected: _dayOffset,
            onSelected: (i) => setState(() => _dayOffset = i),
            days: _days,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(l.gameStartTime, style: AppText.bodyStrong)),
              OutlinedButton.icon(
                key: const ValueKey('pick-time'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(96, 44)),
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_rounded),
                label: Text(hm(start)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l.gameDuration, style: AppText.bodyStrong),
          const SizedBox(height: 8),
          Wrap(
            runSpacing: 8,
            children: [
              for (final m in _durations)
                FilterChipButton(
                  label: l.minutesShort(m),
                  selected: _duration == m,
                  onTap: () => setState(() => _duration = m),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
