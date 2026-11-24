import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/community.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import 'game_pickers.dart';
import 'host_tools.dart';

/// Turns a Game Request into a game: a booking of the poster's own for a
/// bookable sport, a venue or meeting point for a place-only one. Returns the
/// new game, or null when the poster closes the sheet.
Future<Game?> showConvertRequestSheet(BuildContext context, GameRequest request) => showModalBottomSheet<Game>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => ConvertRequestSheet(request: request),
);

class ConvertRequestSheet extends ConsumerStatefulWidget {
  const ConvertRequestSheet({super.key, required this.request});

  final GameRequest request;

  @override
  ConsumerState<ConvertRequestSheet> createState() => _ConvertRequestSheetState();
}

class _ConvertRequestSheetState extends ConsumerState<ConvertRequestSheet> {
  final _form = GlobalKey<FormState>();
  late final _place = PlaceController(atMeetingPoint: widget.request.venueId == null, venueId: widget.request.venueId);

  /// Both default to the request's window; a place-only game may need other
  /// times when the window has already started.
  late DateTime _start = widget.request.start;
  late DateTime _end = widget.request.end;
  late int _spots = (1 + widget.request.playersNeeded).clamp(SpotsStepper.min, SpotsStepper.max);
  String? _bookingId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await pickMinuteOfDay(context, _start.hour * 60 + _start.minute);
    if (picked != null) setState(() => _start = dateOnly(_start).add(Duration(minutes: picked)));
  }

  Future<void> _pickEnd() async {
    final picked = await pickMinuteOfDay(context, _end.hour * 60 + _end.minute);
    if (picked != null) setState(() => _end = dateOnly(_end).add(Duration(minutes: picked)));
  }

  Future<void> _convert(Sport sport) async {
    final l = context.l;
    if (!sport.bookable) {
      if (!_form.currentState!.validate()) return;
      if (!_place.atMeetingPoint && _place.venueId == null) {
        setState(() => _error = l.venueRequired);
        return;
      }
      if (!_end.isAfter(_start)) {
        setState(() => _error = l.errInvalidArgument);
        return;
      }
    }
    final distanceText = _place.distance.text.trim().replaceAll(',', '.');
    final distance = distanceText.isEmpty ? null : double.tryParse(distanceText);
    if (!sport.bookable && distanceText.isNotEmpty && (distance == null || distance <= 0)) {
      setState(() => _error = l.errInvalidArgument);
      return;
    }
    String? blank(String text) => text.trim().isEmpty ? null : text.trim();

    final place = sport.bookable
        ? PlacePick(bookingId: _bookingId, spots: _spots)
        : PlacePick(
            venueId: _place.atMeetingPoint ? null : _place.venueId,
            meetingPoint: _place.atMeetingPoint ? blank(_place.meeting.text) : null,
            spots: _spots,
            start: _start,
            end: _end,
            pace: blank(_place.pace.text),
            distanceKm: distance,
          );

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final game = await ref.read(gameRepositoryProvider).convertRequest(widget.request.id, place);
      refreshGames(ref);
      if (mounted) Navigator.of(context).pop(game);
    } on JoinException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = joinErrorText(l, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final request = widget.request;
    final sport = (ref.watch(sportsProvider).valueOrNull ?? const <Sport>[])
        .where((s) => s.id == request.sportId)
        .firstOrNull;
    final (:choices, loading: loadingVenues) = bookingChoices(ref);
    final forSport = [
      for (final c in choices)
        if (c.court.sportId == request.sportId) c,
    ];
    final chosen = forSport.where((c) => c.booking.id == _bookingId).firstOrNull;
    final canConvert = sport != null && !_busy && (!sport.bookable || chosen != null);

    return Padding(
      // Keeps the form above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.makeItAGame, style: AppText.title),
                  const SizedBox(height: 4),
                  Text(l.convertHint, style: AppText.muted),
                  const SizedBox(height: 16),
                  if (sport != null && sport.bookable) ...[
                    Text(l.gameBookingLabel, style: AppText.bodyStrong),
                    const SizedBox(height: 8),
                    if (loadingVenues)
                      const Center(child: CircularProgressIndicator())
                    else if (forSport.isEmpty) ...[
                      Text(l.noBookingForSport, style: AppText.muted.copyWith(fontSize: 15)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          context.go('/venues');
                        },
                        child: Text(l.bookACourt),
                      ),
                    ] else
                      for (final c in forSport)
                        BookingTile(
                          key: ValueKey('booking-${c.booking.id}'),
                          choice: c,
                          selected: c.booking.id == chosen?.booking.id,
                          onTap: () => setState(() => _bookingId = c.booking.id),
                        ),
                  ] else if (sport != null) ...[
                    Text(l.gamePlaceLabel, style: AppText.bodyStrong),
                    const SizedBox(height: 8),
                    PlaceFields(
                      sport: sport,
                      cityId: request.cityId,
                      controller: _place,
                      onModeChanged: () => setState(() => _error = null),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: Text(l.gameStartTime, style: AppText.bodyStrong)),
                        OutlinedButton.icon(
                          key: const ValueKey('convert-start'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(96, 44)),
                          onPressed: _pickStart,
                          icon: const Icon(Icons.schedule_rounded),
                          label: Text(hm(_start)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: Text(l.gameEndTime, style: AppText.bodyStrong)),
                        OutlinedButton.icon(
                          key: const ValueKey('convert-end'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(96, 44)),
                          onPressed: _pickEnd,
                          icon: const Icon(Icons.schedule_rounded),
                          label: Text(hm(_end)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Text(l.spotsLabel, style: AppText.bodyStrong)),
                      if (chosen != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            l.perPlayer(
                              money(
                                l,
                                (chosen.booking.totalPrice + _spots - 1) ~/ _spots,
                                cityById(chosen.venue.cityId).currency,
                              ),
                            ),
                            style: AppText.bodyStrong,
                          ),
                        ),
                      SpotsStepper(value: _spots, onChanged: (v) => setState(() => _spots = v)),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: manrope(13.5, 600, color: AppColors.error)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('convert-submit'),
                    onPressed: canConvert ? () => _convert(sport) : null,
                    child: Text(l.makeItAGame),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
