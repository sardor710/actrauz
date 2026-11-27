import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/community.dart';
import '../../domain/competitive.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'game_pickers.dart';

/// Post a Game Request: a sport, how many players are wanted, the window the
/// poster can play in and, if they like, an area or a venue.
class CreateRequestScreen extends ConsumerStatefulWidget {
  const CreateRequestScreen({super.key});

  @override
  ConsumerState<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends ConsumerState<CreateRequestScreen> {
  static const _days = 14;
  static const _maxNeeded = 29;

  final _area = TextEditingController();
  final _note = TextEditingController();

  String? _sportId;
  String? _venueId;
  int _dayOffset = 1;
  int _fromMinute = 18 * 60;
  int _toMinute = 21 * 60;
  int _needed = 2;
  RangeValues _levels = const RangeValues(1, 5);

  /// The range of a request in a rated sport (padel, tennis).
  RangeValues _ratings = kAllRatings;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _area.dispose();
    _note.dispose();
    super.dispose();
  }

  void _back() => context.canPop() ? context.pop() : context.go('/games');

  Future<void> _pickTime({required bool from}) async {
    final picked = await pickMinuteOfDay(context, from ? _fromMinute : _toMinute);
    if (picked != null) setState(() => from ? _fromMinute = picked : _toMinute = picked);
  }

  Future<void> _pickVenue(List<Venue> venues) async {
    final l = context.l;
    final picked = await showOptionSheet(
      context,
      title: l.chooseVenue,
      options: {'': l.anyVenue, for (final v in venues) v.id: v.name.resolve(context.lang)},
      current: _venueId ?? '',
    );
    if (picked != null) setState(() => _venueId = picked.isEmpty ? null : picked);
  }

  Future<void> _post(DateTime today) async {
    final l = context.l;
    final sportId = _sportId;
    if (sportId == null) return;
    if (_toMinute <= _fromMinute) {
      setState(() => _error = l.errInvalidArgument);
      return;
    }
    String? blank(String text) => text.trim().isEmpty ? null : text.trim();
    final day = today.add(Duration(days: _dayOffset));
    final sports = ref.read(sportsProvider).valueOrNull ?? const <Sport>[];
    final rated = sports.where((s) => s.id == sportId).firstOrNull?.competitiveRating ?? false;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await ref
          .read(gameRepositoryProvider)
          .createRequest(
            GameRequestDraft(
              sportId: sportId,
              playersNeeded: _needed,
              // In a rated sport the server derives the levels from the rating range, as here.
              minLevel: rated ? levelOfRating(_ratings.start) : _levels.start.round(),
              maxLevel: rated ? levelOfRating(_ratings.end) : _levels.end.round(),
              minRating: rated ? _ratings.start : null,
              maxRating: rated ? _ratings.end : null,
              start: day.add(Duration(minutes: _fromMinute)),
              end: day.add(Duration(minutes: _toMinute)),
              venueId: _venueId,
              area: blank(_area.text),
              note: blank(_note.text),
            ),
          );
      refreshGames(ref);
      // A request lives in the Games tab: go, not push.
      if (mounted) context.go('/games/requests/${request.id}');
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
    final now = ref.watch(cityNowProvider)();
    final today = dateOnly(now);
    final venues = [
      for (final v in ref.watch(venuesProvider).valueOrNull ?? const <Venue>[])
        if (v.cityId == city.id && (_sportId == null || v.sportIds.contains(_sportId))) v,
    ];
    final venueName = venues.where((v) => v.id == _venueId).firstOrNull?.name.resolve(context.lang);
    final day = today.add(Duration(days: _dayOffset));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(l.createRequestTitle),
      ),
      body: Column(
        children: [
          Expanded(
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
                          selected: s.id == _sportId,
                          onTap: () => setState(() {
                            _sportId = s.id;
                            _venueId = null;
                            _error = null;
                          }),
                        ),
                    ],
                  ),
                ),
                if (_sportId == null)
                  EmptyState(icon: Icons.sports_outlined, text: l.pickSportHint)
                else ...[
                  SectionCard(
                    title: l.requestPlayersNeeded,
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: l.fewerSpots,
                          onPressed: _needed > 1 ? () => setState(() => _needed--) : null,
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text('$_needed', textAlign: TextAlign.center, style: manrope(20, 800)),
                        ),
                        IconButton.filledTonal(
                          tooltip: l.moreSpots,
                          onPressed: _needed < _maxNeeded ? () => setState(() => _needed++) : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                  SectionCard(
                    title: l.requestWindowLabel,
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
                            Expanded(child: Text(l.requestFrom, style: AppText.bodyStrong)),
                            OutlinedButton.icon(
                              key: const ValueKey('request-from'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size(96, 44)),
                              onPressed: () => _pickTime(from: true),
                              icon: const Icon(Icons.schedule_rounded),
                              label: Text(hm(day.add(Duration(minutes: _fromMinute)))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: Text(l.requestTo, style: AppText.bodyStrong)),
                            OutlinedButton.icon(
                              key: const ValueKey('request-to'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size(96, 44)),
                              onPressed: () => _pickTime(from: false),
                              icon: const Icon(Icons.schedule_rounded),
                              label: Text(hm(day.add(Duration(minutes: _toMinute)))),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SectionCard(
                    title: l.gamePlaceLabel,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const ValueKey('request-area'),
                          controller: _area,
                          maxLength: 80,
                          decoration: InputDecoration(labelText: l.areaLabel, hintText: l.areaHint),
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          key: const ValueKey('request-venue'),
                          onPressed: () => _pickVenue(venues),
                          icon: const Icon(Icons.place_outlined),
                          label: Text(venueName ?? l.venueOptional),
                        ),
                      ],
                    ),
                  ),
                  if (sports.where((s) => s.id == _sportId).firstOrNull?.competitiveRating ?? false)
                    LevelRangeCard(rated: true, values: _ratings, onChanged: (v) => setState(() => _ratings = v))
                  else
                    LevelRangeCard(values: _levels, onChanged: (v) => setState(() => _levels = v)),
                  SectionCard(
                    title: l.noteLabel,
                    child: TextField(
                      key: const ValueKey('request-note'),
                      controller: _note,
                      maxLength: 200,
                      maxLines: 2,
                    ),
                  ),
                ],
              ],
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
                        key: const ValueKey('post-request-submit'),
                        onPressed: _sportId != null && !_busy ? () => _post(today) : null,
                        child: Text(l.postRequestCta),
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
}
