import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/brackets.dart';
import '../../domain/models.dart';
import '../../domain/slot_generator.dart';
import '../../domain/tournaments.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../games/game_pickers.dart' show pickMinuteOfDay;
import '../tournaments/tournament_tools.dart';
import 'match_tools.dart';
import 'scores_tab.dart' show bracketLoadState;

/// The manager's Schedule tab (M8a design §7.2, §11): a day of the
/// tournament, a column per court with the matches placed on it, and the
/// matches with no time yet. Tapping a match sets, moves or clears its court
/// and time; "Fill the day" places the rest. Without a venue a match gets a
/// time and a place note instead.
class ScheduleTab extends ConsumerStatefulWidget {
  const ScheduleTab({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  ConsumerState<ScheduleTab> createState() => _ScheduleTabState();
}

/// Kept alive: a tab flip keeps the day.
class _ScheduleTabState extends ConsumerState<ScheduleTab> with AutomaticKeepAliveClientMixin {
  String get tournamentId => widget.tournamentId;

  @override
  bool get wantKeepAlive => true;

  DateTime? _day;

  static List<DateTime> _days(Tournament t) => [
    for (var d = dateOnly(t.start); !d.isAfter(dateOnly(t.end)); d = d.add(const Duration(days: 1))) d,
  ];

  /// The picked day, else today while the tournament runs, else its first.
  DateTime _dayOf(Tournament t, DateTime now) {
    final days = _days(t);
    if (_day case final day? when days.contains(day)) return day;
    final today = dateOnly(now);
    return days.contains(today) ? today : days.first;
  }

  Future<void> _openMatch(Tournament tournament, TournamentBracket bracket, ManagedMatch m, DateTime day) async {
    final moved = await showModalBottomSheet<DateTime>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ClosesOnAccountChange(
        child: _MatchTimeSheet(tournament: tournament, bracket: bracket, match: m, day: day),
      ),
    );
    if (moved != null && mounted) setState(() => _day = moved);
  }

  Future<void> _fill(Tournament tournament, TournamentBracket bracket, DateTime day) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ClosesOnAccountChange(
      child: _FillDaySheet(tournament: tournament, bracket: bracket, day: day),
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = context.l;
    final bracketValue = ref.watch(bracketProvider(tournamentId));

    return KeyedSubtree(
      key: const ValueKey('manage-schedule'),
      child: AsyncBody(
        value: ref.watch(tournamentProvider(tournamentId)),
        onRetry: () => ref.invalidate(tournamentProvider(tournamentId)),
        errorText: (error) => organizerErrorText(l, error),
        canRetry: (error) => !(error is TournamentException && error.error == TournamentError.notFound),
        builder: (tournament) {
          // Kept through a failed refresh; never another account's.
          final bracket = currentData(bracketValue);
          if (bracket == null) {
            return bracketLoadState(context, bracketValue, () => ref.invalidate(bracketProvider(tournamentId)));
          }
          if (!bracket.organizer) return EmptyState(icon: Icons.lock_outline_rounded, text: l.notOrganizer);
          return _body(context, tournament, bracket);
        },
      ),
    );
  }

  Widget _body(BuildContext context, Tournament tournament, TournamentBracket bracket) {
    final l = context.l;
    if (!bracket.draws.any((d) => d.published)) {
      return EmptyState(icon: Icons.calendar_month_outlined, text: l.scheduleNoDraws);
    }
    final now = tournamentNow(ref, tournament.cityId);
    final day = _dayOf(tournament, now);
    final matches = managedMatches(tournament, bracket)..sort(playOrder);
    final onDay = [
      for (final m in matches)
        if (m.match.startsAt case final start? when dateOnly(start) == day) m,
    ];
    final unscheduled = [
      for (final m in matches)
        if (m.match.startsAt == null && m.schedulable) m,
    ];
    final hasVenue = tournament.venueId != null;
    void open(ManagedMatch m) => _openMatch(tournament, bracket, m, day);

    Widget tile(ManagedMatch m) =>
        _MatchTile(match: m, onTap: m.schedulable ? () => open(m) : null, showCourt: !hasVenue);

    return RefreshIndicator(
      onRefresh: () => pullToReload(context, ref.refresh(bracketProvider(tournamentId).future)),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in _days(tournament))
                ChoiceChip(
                  key: ValueKey('schedule-day-${dateKey(d)}'),
                  label: Text(dayLabel(l, context.lang, d, now)),
                  selected: d == day,
                  onSelected: (_) => setState(() => _day = d),
                ),
            ],
          ),
          if (hasVenue) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('fill-day'),
              onPressed: () => _fill(tournament, bracket, day),
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: Text(l.fillDay),
            ),
          ],
          const SizedBox(height: 16),
          if (hasVenue)
            _CourtColumns(courts: bracket.courts, matches: onDay, tile: tile)
          else if (onDay.isEmpty)
            Text(l.scheduleDayEmpty, style: AppText.muted)
          else
            for (final m in onDay) tile(m),
          if (unscheduled.isNotEmpty) ...[
            const SizedBox(height: 20),
            Column(
              key: const ValueKey('schedule-unscheduled'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.scheduleUnscheduled.toUpperCase(), style: AppText.sectionTitle),
                const SizedBox(height: 8),
                for (final m in unscheduled) tile(m),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A column per court, side by side; scrolls sideways when they do not fit.
class _CourtColumns extends StatelessWidget {
  const _CourtColumns({required this.courts, required this.matches, required this.tile});

  final List<CourtRef> courts;
  final List<ManagedMatch> matches;
  final Widget Function(ManagedMatch) tile;

  static const _minWidth = 160.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    if (courts.isEmpty) return Text(l.scheduleDayEmpty, style: AppText.muted);
    return LayoutBuilder(
      builder: (context, box) {
        final width = math.max(_minWidth, (box.maxWidth - _gap * (courts.length - 1)) / courts.length);
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, court) in courts.indexed) ...[
              if (i > 0) const SizedBox(width: _gap),
              SizedBox(
                width: width,
                child: Container(
                  key: ValueKey('schedule-court-${court.id}'),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                        child: Text(
                          court.name.resolve(context.lang),
                          style: AppText.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...[
                        for (final m in matches)
                          if (m.match.courtId == court.id) tile(m),
                      ].ifEmpty(
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(l.scheduleDayEmpty, style: AppText.caption),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
        final total = width * courts.length + _gap * (courts.length - 1);
        if (total <= box.maxWidth + 0.5) return row;
        return SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);
      },
    );
  }
}

extension on List<Widget> {
  List<Widget> ifEmpty(Widget placeholder) => isEmpty ? [placeholder] : this;
}

/// A match in the schedule: its time, where it is in the draw, the two
/// sides, a clash warning. Done matches are shown, not tappable.
class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match, required this.onTap, required this.showCourt});

  final ManagedMatch match;
  final VoidCallback? onTap;

  /// Without a venue: the place note next to the time.
  final bool showCourt;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final m = match.match;
    final done = m.status == MatchStatus.done;
    final start = m.startsAt;
    final place = showCourt ? m.placeNote : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: done ? AppColors.page : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('schedule-match-${m.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: m.clash ? AppColors.error : AppColors.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (start != null)
                  Text(
                    [hm(start), if (place != null && place.isNotEmpty) place].join(' · '),
                    style: manrope(14, 800, color: done ? AppColors.muted : AppColors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  matchStageText(l, context.lang, match),
                  style: AppText.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  matchSidesText(l, match),
                  style: manrope(13, 600, color: done ? AppColors.muted : AppColors.ink),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (m.clash) ClashNote(key: ValueKey('schedule-clash-${m.id}')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sets, moves or clears one match's court and time. At a venue: a day, a
/// court and one of its slots; without one: a day, a time and a place note.
/// Pops with the day the match is now on; a refusal shows in the sheet.
class _MatchTimeSheet extends ConsumerStatefulWidget {
  const _MatchTimeSheet({required this.tournament, required this.bracket, required this.match, required this.day});

  final Tournament tournament;
  final TournamentBracket bracket;
  final ManagedMatch match;
  final DateTime day;

  @override
  ConsumerState<_MatchTimeSheet> createState() => _MatchTimeSheetState();
}

class _MatchTimeSheetState extends ConsumerState<_MatchTimeSheet> {
  TournamentMatch get m => widget.match.match;

  late DateTime _day;
  String? _courtId;

  /// Minutes after midnight.
  int? _minute;
  late final TextEditingController _note;
  bool _busy = false;
  String? _error;

  bool get _hasVenue => widget.tournament.venueId != null;

  @override
  void initState() {
    super.initState();
    final start = m.startsAt;
    _day = start == null ? widget.day : dateOnly(start);
    _minute = start == null ? null : start.hour * 60 + start.minute;
    final courts = widget.bracket.courts;
    _courtId = m.courtId ?? (courts.isEmpty ? null : courts.first.id);
    _note = TextEditingController(text: m.placeNote ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run({required bool clear}) async {
    final l = context.l;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final organizer = ref.read(organizerRepositoryProvider);
    final startsAt = clear || _minute == null ? null : _day.add(Duration(minutes: _minute!));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (clear) {
        await organizer.scheduleMatch(m.id);
      } else {
        final note = _note.text.trim();
        await organizer.scheduleMatch(
          m.id,
          courtId: _hasVenue ? _courtId : null,
          startsAt: startsAt,
          placeNote: _hasVenue || note.isEmpty ? null : note,
        );
      }
      refreshTournamentsIn(container);
      if (mounted) Navigator.of(context).pop(clear ? null : _day);
    } on TournamentException catch (e) {
      refreshTournamentsIn(container);
      if (!mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(organizerErrorText(l, e)), behavior: SnackBarBehavior.floating));
        return;
      }
      setState(() {
        _busy = false;
        _error = organizerErrorText(l, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = widget.tournament;
    final now = tournamentNow(ref, t.cityId);
    final days = _ScheduleTabState._days(t);

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text.toUpperCase(), style: AppText.sectionTitle),
    );

    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.scheduleMatchTitle, style: AppText.title),
                const SizedBox(height: 4),
                Text(matchStageText(l, context.lang, widget.match), style: AppText.muted),
                Text(matchSidesText(l, widget.match), style: AppText.bodyStrong),
                if (m.clash) const ClashNote(),
                if (days.length > 1) ...[
                  label(l.dateLabel),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in days)
                        ChoiceChip(
                          key: ValueKey('sheet-day-${dateKey(d)}'),
                          label: Text(dayLabel(l, context.lang, d, now)),
                          selected: d == _day,
                          onSelected: (_) => setState(() {
                            _day = d;
                            if (_hasVenue) _minute = null;
                          }),
                        ),
                    ],
                  ),
                ],
                if (_hasVenue) ..._venuePart(context, label) else ..._noVenuePart(context, label),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: manrope(13.5, 600, color: AppColors.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('schedule-save'),
                  onPressed: !_busy && _minute != null && (!_hasVenue || _courtId != null)
                      ? () => _run(clear: false)
                      : null,
                  child: Text(l.saveLabel),
                ),
                if (m.startsAt != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    key: const ValueKey('schedule-clear'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    onPressed: _busy ? null : () => _run(clear: true),
                    child: Text(l.clearTime),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _venuePart(BuildContext context, Widget Function(String) label) {
    final l = context.l;
    final courts = widget.bracket.courts;
    final venue = ref.watch(venueProvider(widget.tournament.venueId!));
    return [
      label(l.courtLabel),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in courts)
            ChoiceChip(
              key: ValueKey('sheet-court-${c.id}'),
              label: Text(c.name.resolve(context.lang)),
              selected: c.id == _courtId,
              onSelected: (_) => setState(() {
                if (_courtId != c.id) _minute = null;
                _courtId = c.id;
              }),
            ),
        ],
      ),
      label(l.timeLabel),
      venue.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => _venueError(error),
        data: (venue) {
          final court = venue.courts.where((c) => c.id == _courtId).firstOrNull;
          final slots = court == null ? const <SlotTime>[] : generateSlots(venue, court, _day);
          if (slots.isEmpty) return Text(l.scheduleCourtClosed, style: AppText.muted);
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in slots)
                ChoiceChip(
                  key: ValueKey('sheet-slot-${hm(s.start)}'),
                  label: Text(hm(s.start)),
                  selected: _minute == s.start.hour * 60 + s.start.minute,
                  onSelected: (_) => setState(() => _minute = s.start.hour * 60 + s.start.minute),
                ),
            ],
          );
        },
      ),
    ];
  }

/// A venue that failed to load: the reason and Try again (it never spins
  /// for ever).
  Widget _venueError(Object error) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(organizerErrorText(context.l, error), style: AppText.muted),
      TextButton(
        key: const ValueKey('venue-retry'),
        onPressed: () => ref.invalidate(venueProvider(widget.tournament.venueId!)),
        child: Text(context.l.tryAgain),
      ),
    ],
  );

  List<Widget> _noVenuePart(BuildContext context, Widget Function(String) label) {
    final l = context.l;
    return [
      label(l.timeLabel),
      OutlinedButton.icon(
        key: const ValueKey('schedule-pick-time'),
        onPressed: () async {
          final picked = await pickMinuteOfDay(context, _minute ?? 10 * 60);
          if (picked != null && mounted) setState(() => _minute = picked);
        },
        icon: const Icon(Icons.schedule_rounded),
        label: Text(_minute == null ? l.pickTime : minutesHm(_minute!)),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('schedule-place-note'),
        controller: _note,
        maxLength: 100,
        decoration: InputDecoration(labelText: l.placeNoteLabel),
      ),
    ];
  }
}

/// "Fill the day": the courts, the time to start from and the categories;
/// then what was placed and what did not fit.
class _FillDaySheet extends ConsumerStatefulWidget {
  const _FillDaySheet({required this.tournament, required this.bracket, required this.day});

  final Tournament tournament;
  final TournamentBracket bracket;
  final DateTime day;

  @override
  ConsumerState<_FillDaySheet> createState() => _FillDaySheetState();
}

class _FillDaySheetState extends ConsumerState<_FillDaySheet> {
  late final Set<String> _courts = {for (final c in widget.bracket.courts) c.id};
  late final List<TournamentCategory> _categories = [
    for (final c in widget.tournament.categories)
      if (widget.bracket.draw(c.id)?.published ?? false) c,
  ];
  late final Set<String> _ticked = {for (final c in _categories) c.id};

  /// Minutes after midnight; the first slot of the picked courts until chosen.
  int? _from;
  bool _busy = false;
  String? _error;
  FillResult? _result;

  /// The matches as they were when the sheet opened, to name what did not fit.
  late final Map<String, ManagedMatch> _matches = {
    for (final m in managedMatches(widget.tournament, widget.bracket)) m.id: m,
  };

  Future<void> _run(int from) async {
    final l = context.l;
    final container = ProviderScope.containerOf(context, listen: false);
    final organizer = ref.read(organizerRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await organizer.fillDay(
        widget.tournament.id,
        widget.day,
        [
          for (final c in widget.bracket.courts)
            if (_courts.contains(c.id)) c.id,
        ],
        TimeOfDay(hour: from ~/ 60, minute: from % 60),
        categoryIds: _ticked.length == _categories.length
            ? null
            : [
                for (final c in _categories)
                  if (_ticked.contains(c.id)) c.id,
              ],
      );
      refreshTournamentsIn(container);
      if (mounted) {
        setState(() {
          _busy = false;
          _result = result;
        });
      }
    } on TournamentException catch (e) {
      refreshTournamentsIn(container);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = organizerErrorText(l, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final now = tournamentNow(ref, widget.tournament.cityId);

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text.toUpperCase(), style: AppText.sectionTitle),
    );

    final result = _result;
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.fillDay, style: AppText.title),
              const SizedBox(height: 4),
              Text(dayLabel(l, context.lang, widget.day, now), style: AppText.muted),
              if (result != null) ..._report(context, result) else ..._form(context, label),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _form(BuildContext context, Widget Function(String) label) {
    final l = context.l;
    final venueValue = ref.watch(venueProvider(widget.tournament.venueId!));
    final venue = venueValue.valueOrNull;
    // Every slot start of the picked courts that day.
    final starts = <int>{
      if (venue != null)
        for (final c in venue.courts)
          if (_courts.contains(c.id))
            for (final s in generateSlots(venue, c, widget.day)) s.start.hour * 60 + s.start.minute,
    }.toList()..sort();
    final from = _from != null && starts.contains(_from) ? _from : starts.firstOrNull;

    return [
      const SizedBox(height: 8),
      Text(l.fillDayHint, style: AppText.caption),
      label(l.fillCourts),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in widget.bracket.courts)
            FilterChip(
              key: ValueKey('fill-court-${c.id}'),
              label: Text(c.name.resolve(context.lang)),
              selected: _courts.contains(c.id),
              onSelected: (on) => setState(() => on ? _courts.add(c.id) : _courts.remove(c.id)),
            ),
        ],
      ),
      label(l.fillFrom),
      if (venue == null)
        venueValue.hasError && !venueValue.isLoading ? _venueError(venueValue.error!) : const LinearProgressIndicator()
      else if (starts.isEmpty)
        Text(l.scheduleCourtClosed, style: AppText.muted)
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in starts)
              ChoiceChip(
                key: ValueKey('fill-from-${minutesHm(s)}'),
                label: Text(minutesHm(s)),
                selected: s == from,
                onSelected: (_) => setState(() => _from = s),
              ),
          ],
        ),
      if (_categories.length > 1) ...[
        label(l.tournamentCategories),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _categories)
              FilterChip(
                key: ValueKey('fill-category-${c.id}'),
                label: Text(c.name.resolve(context.lang)),
                selected: _ticked.contains(c.id),
                onSelected: (on) => setState(() => on ? _ticked.add(c.id) : _ticked.remove(c.id)),
              ),
          ],
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: manrope(13.5, 600, color: AppColors.error)),
      ],
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const ValueKey('fill-run'),
        onPressed: !_busy && from != null && _courts.isNotEmpty && _ticked.isNotEmpty ? () => _run(from) : null,
        icon: const Icon(Icons.auto_fix_high_rounded),
        label: Text(l.fillRun),
      ),
    ];
  }

/// A venue that failed to load: the reason and Try again (it never spins
  /// for ever).
  Widget _venueError(Object error) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(organizerErrorText(context.l, error), style: AppText.muted),
      TextButton(
        key: const ValueKey('venue-retry'),
        onPressed: () => ref.invalidate(venueProvider(widget.tournament.venueId!)),
        child: Text(context.l.tryAgain),
      ),
    ],
  );

  List<Widget> _report(BuildContext context, FillResult result) {
    final l = context.l;
    return [
      const SizedBox(height: 16),
      Column(
        key: const ValueKey('fill-result'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.fillPlaced(result.scheduled), style: AppText.bodyStrong),
          const SizedBox(height: 8),
          if (result.unscheduled.isEmpty)
            Text(l.fillAllFitted, style: AppText.muted)
          else ...[
            Text(l.fillNotFitted.toUpperCase(), style: AppText.sectionTitle),
            const SizedBox(height: 6),
            for (final id in result.unscheduled)
              Padding(
                key: ValueKey('fill-unscheduled-$id'),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: switch (_matches[id]) {
                  final m? => Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${matchStageText(l, context.lang, m)}\n', style: AppText.caption),
                        TextSpan(text: matchSidesText(l, m), style: AppText.bodyStrong),
                      ],
                    ),
                  ),
                  null => Text(l.matchTbd, style: AppText.bodyStrong),
                },
              ),
          ],
        ],
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('fill-done'),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l.doneLabel),
      ),
    ];
  }
}
