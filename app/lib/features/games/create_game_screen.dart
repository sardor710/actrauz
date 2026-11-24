import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/booking_engine.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/owner.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'host_tools.dart';

/// One of the player's own bookings a game can sit on.
typedef _Choice = ({Booking booking, Venue venue, Court court, DateTime now});

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
  final _meeting = TextEditingController();
  final _distance = TextEditingController();
  final _pace = TextEditingController();
  final _note = TextEditingController();

  String? _sportId;
  late String? _bookingId = widget.bookingId;
  bool _atMeetingPoint = true;
  String? _venueId;
  int _dayOffset = 1;
  int _startMinute = 18 * 60;
  int _duration = 60;
  int? _spots;
  RangeValues _levels = const RangeValues(1, 5);
  GameVisibility _visibility = GameVisibility.public;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _meeting.dispose();
    _distance.dispose();
    _pace.dispose();
    _note.dispose();
    super.dispose();
  }

  void _back() => context.canPop() ? context.pop() : context.go('/games');

  Future<void> _pickVenue(List<Venue> venues) async {
    final l = context.l;
    final picked = await showOptionSheet(
      context,
      title: l.chooseVenue,
      options: {for (final v in venues) v.id: v.name.resolve(context.lang)},
      current: _venueId,
    );
    if (picked != null) setState(() => _venueId = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _startMinute ~/ 60, minute: _startMinute % 60),
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked != null) setState(() => _startMinute = picked.hour * 60 + picked.minute);
  }

  Future<void> _create({required Sport sport, required String? bookingId, required DateTime today}) async {
    final l = context.l;
    if (!sport.bookable && !_form.currentState!.validate()) return;
    if (!sport.bookable && !_atMeetingPoint && _venueId == null) {
      setState(() => _error = l.venueRequired);
      return;
    }
    final distanceText = _distance.text.trim().replaceAll(',', '.');
    final distance = distanceText.isEmpty ? null : double.tryParse(distanceText);
    if (distanceText.isNotEmpty && (distance == null || distance <= 0)) {
      setState(() => _error = l.errInvalidArgument);
      return;
    }

    String? blank(String text) => text.trim().isEmpty ? null : text.trim();
    final start = today.add(Duration(days: _dayOffset, minutes: _startMinute));
    final draft = GameDraft(
      sportId: sport.id,
      spots: _spots ?? sport.defaultPlayers.clamp(SpotsStepper.min, SpotsStepper.max),
      minLevel: _levels.start.round(),
      maxLevel: _levels.end.round(),
      visibility: _visibility,
      note: blank(_note.text),
      pace: sport.bookable ? null : blank(_pace.text),
      distanceKm: sport.bookable ? null : distance,
      bookingId: sport.bookable ? bookingId : null,
      venueId: !sport.bookable && !_atMeetingPoint ? _venueId : null,
      meetingPoint: !sport.bookable && _atMeetingPoint ? blank(_meeting.text) : null,
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
    final bookings = ref.watch(myBookingsProvider).valueOrNull ?? const <Booking>[];
    final taken = {
      for (final g in ref.watch(gamesProvider).valueOrNull ?? const <Game>[])
        if (g.bookingId != null && !g.cancelled) g.bookingId,
    };
    final choices = <_Choice>[];
    var loadingVenues = false;
    for (final b in bookings) {
      if (b.source != BookingSource.app || b.status != BookingStatus.confirmed || taken.contains(b.id)) continue;
      final venue = ref.watch(venueProvider(b.venueId)).valueOrNull;
      if (venue == null) {
        loadingVenues = true;
        continue;
      }
      final now = venueNow(cityById(venue.cityId), utcNow: ref.watch(clockProvider)());
      if (!b.start.isAfter(now)) continue;
      choices.add((booking: b, venue: venue, court: venue.court(b.courtId), now: now));
    }

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
                                    _BookingTile(
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
                    SectionCard(
                      title: l.levelRangeLabel,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.levelRange(_levels.start.round(), _levels.end.round()), style: AppText.bodyStrong),
                          RangeSlider(
                            values: _levels,
                            min: 1,
                            max: 5,
                            divisions: 4,
                            labels: RangeLabels('${_levels.start.round()}', '${_levels.end.round()}'),
                            onChanged: (v) => setState(() => _levels = v),
                          ),
                        ],
                      ),
                    ),
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
    final l = context.l;
    final venues = [
      for (final v in ref.watch(venuesProvider).valueOrNull ?? const <Venue>[])
        if (v.cityId == cityId) v,
    ];
    final forSport = venues.where((v) => v.sportIds.contains(sport.id)).toList();
    final options = forSport.isEmpty ? venues : forSport;
    final venueName = options.where((v) => v.id == _venueId).firstOrNull?.name.resolve(context.lang);

    return SectionCard(
      title: l.gamePlaceLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, label: Text(l.placeMeetingPoint)),
              ButtonSegment(value: false, label: Text(l.placeVenue)),
            ],
            selected: {_atMeetingPoint},
            onSelectionChanged: (v) => setState(() {
              _atMeetingPoint = v.first;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          if (_atMeetingPoint)
            TextFormField(
              key: const ValueKey('meeting-point'),
              controller: _meeting,
              maxLength: 120,
              decoration: InputDecoration(labelText: l.placeMeetingPoint, hintText: l.meetingPointHint),
              validator: (v) => (v ?? '').trim().isEmpty ? l.meetingPointRequired : null,
            )
          else
            OutlinedButton.icon(
              key: const ValueKey('pick-venue'),
              onPressed: () => _pickVenue(options),
              icon: const Icon(Icons.place_outlined),
              label: Text(venueName ?? l.chooseVenue),
            ),
          if (sport.id == 'running') ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('distance-km'),
              controller: _distance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l.distanceLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('pace'),
              controller: _pace,
              maxLength: 30,
              decoration: InputDecoration(labelText: l.paceLabel, hintText: l.paceHint),
            ),
          ],
        ],
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
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i <= _days; i++)
                  FilterChipButton(
                    label: dayLabel(l, context.lang, today.add(Duration(days: i)), now),
                    selected: _dayOffset == i,
                    onTap: () => setState(() => _dayOffset = i),
                  ),
              ],
            ),
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

class _BookingTile extends StatelessWidget {
  const _BookingTile({super.key, required this.choice, required this.selected, required this.onTap});

  final _Choice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final booking = choice.booking;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? AppColors.primary : AppColors.line, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(choice.venue.name.resolve(context.lang), style: manrope(15.5, 700)),
                      const SizedBox(height: 2),
                      Text(
                        '${choice.court.name.resolve(context.lang)} · '
                        '${dayLabel(l, context.lang, booking.start, choice.now)}, '
                        '${timeRange(booking.start, booking.end)}',
                        style: AppText.muted,
                      ),
                    ],
                  ),
                ),
                if (selected) const Icon(Icons.check_circle, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
