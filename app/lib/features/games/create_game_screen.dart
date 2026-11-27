import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/competitive.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/rating_pill.dart';
import '../common/widgets.dart';
import 'game_pickers.dart';
import 'host_tools.dart';

/// Start a game. The sport comes first: a bookable sport sits on one of the
/// player's own upcoming bookings, a place-only one on a venue or a meeting
/// point. Opens the new game when it is created.
class CreateGameScreen extends ConsumerStatefulWidget {
  const CreateGameScreen({super.key, this.bookingId});

  /// A booking to start from, when the player came from "My bookings".
  final String? bookingId;

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
  bool _busy = false;
  String? _error;

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

  Future<void> _create({required Sport sport, required String? bookingId, required DateTime today}) async {
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
      visibility: _visibility,
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

    // Coming from a booking chooses its sport too.
    final fromBooking = choices.where((c) => c.booking.id == widget.bookingId).firstOrNull;
    final sportId = _sportId ?? fromBooking?.court.sportId;
    final sport = sports.where((s) => s.id == sportId).firstOrNull;
    final forSport = [
      for (final c in choices)
        if (c.court.sportId == sportId) c,
    ];
    final chosen = forSport.where((c) => c.booking.id == _bookingId).firstOrNull;
    final spots = _spots ?? (sport?.defaultPlayers ?? 4).clamp(SpotsStepper.min, SpotsStepper.max);
    final canCreate = sport != null && !_busy && (!sport.bookable || chosen != null);

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
                          const Spacer(),
                          if (chosen != null)
                            Text(
                              l.perPlayer(
                                money(
                                  l,
                                  (chosen.booking.totalPrice + spots - 1) ~/ spots,
                                  cityById(chosen.venue.cityId).currency,
                                ),
                              ),
                              style: AppText.bodyStrong,
                            ),
                        ],
                      ),
                    ),
                    if (sport.competitiveRating)
                      LevelRangeCard(rated: true, values: _ratings, onChanged: (v) => setState(() => _ratings = v))
                    else
                      LevelRangeCard(values: _levels, onChanged: (v) => setState(() => _levels = v)),
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
                    ),
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
                            ? () => _create(sport: sport, bookingId: chosen?.booking.id, today: today)
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
