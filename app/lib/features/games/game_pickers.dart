import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/booking_engine.dart';
import '../../domain/competitive.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/owner.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/rating_pill.dart';
import '../common/widgets.dart';

// Pieces the create-game form shares with the Game Request screens: a booking
// to put a game on, where a place-only game happens, the level range and the
// day strip.

/// One of the player's own bookings a game can sit on.
typedef BookingChoice = ({Booking booking, Venue venue, Court court, DateTime now});

/// The player's own upcoming confirmed app bookings that have no game yet.
/// [loading] is true while some venue is still loading. Call from `build`.
({List<BookingChoice> choices, bool loading}) bookingChoices(WidgetRef ref) {
  final bookings = ref.watch(myBookingsProvider).valueOrNull ?? const <Booking>[];
  final taken = {
    for (final g in ref.watch(gamesProvider).valueOrNull ?? const <Game>[])
      if (g.bookingId != null && !g.cancelled) g.bookingId,
  };
  final choices = <BookingChoice>[];
  var loading = false;
  for (final b in bookings) {
    if (b.source != BookingSource.app || b.status != BookingStatus.confirmed || taken.contains(b.id)) continue;
    final venue = ref.watch(venueProvider(b.venueId)).valueOrNull;
    if (venue == null) {
      loading = true;
      continue;
    }
    final now = venueNow(cityById(venue.cityId), utcNow: ref.watch(clockProvider)());
    if (!b.start.isAfter(now)) continue;
    choices.add((booking: b, venue: venue, court: venue.court(b.courtId), now: now));
  }
  return (choices: choices, loading: loading);
}

class BookingTile extends StatelessWidget {
  const BookingTile({super.key, required this.choice, required this.selected, required this.onTap});

  final BookingChoice choice;
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

/// What the player chose for where a place-only game happens: a venue or a
/// meeting point, plus distance and pace for running. Dispose it with its owner.
class PlaceController extends ChangeNotifier {
  PlaceController({this.atMeetingPoint = true, this.venueId});

  final meeting = TextEditingController();
  final distance = TextEditingController();
  final pace = TextEditingController();

  bool atMeetingPoint;
  String? venueId;

  void setAtMeetingPoint(bool value) {
    atMeetingPoint = value;
    notifyListeners();
  }

  void setVenue(String id) {
    venueId = id;
    notifyListeners();
  }

  @override
  void dispose() {
    meeting.dispose();
    distance.dispose();
    pace.dispose();
    super.dispose();
  }
}

/// Venue or meeting point, plus distance and pace for running. Put it under a
/// `Form` to have the meeting point validated.
class PlaceFields extends ConsumerWidget {
  const PlaceFields({
    super.key,
    required this.sport,
    required this.cityId,
    required this.controller,
    this.onModeChanged,
  });

  final Sport sport;
  final String cityId;
  final PlaceController controller;

  /// Called when the player switches between meeting point and venue.
  final VoidCallback? onModeChanged;

  Future<void> _pickVenue(BuildContext context, List<Venue> venues) async {
    final picked = await showOptionSheet(
      context,
      title: context.l.chooseVenue,
      options: {for (final v in venues) v.id: v.name.resolve(context.lang)},
      current: controller.venueId,
    );
    if (picked != null) controller.setVenue(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final venues = [
      for (final v in ref.watch(venuesProvider).valueOrNull ?? const <Venue>[])
        if (v.cityId == cityId) v,
    ];
    final forSport = venues.where((v) => v.sportIds.contains(sport.id)).toList();
    final options = forSport.isEmpty ? venues : forSport;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final venueName = options.where((v) => v.id == controller.venueId).firstOrNull?.name.resolve(context.lang);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: true, label: Text(l.placeMeetingPoint)),
                ButtonSegment(value: false, label: Text(l.placeVenue)),
              ],
              selected: {controller.atMeetingPoint},
              onSelectionChanged: (v) {
                controller.setAtMeetingPoint(v.first);
                onModeChanged?.call();
              },
            ),
            const SizedBox(height: 12),
            if (controller.atMeetingPoint)
              TextFormField(
                key: const ValueKey('meeting-point'),
                controller: controller.meeting,
                maxLength: 120,
                decoration: InputDecoration(labelText: l.placeMeetingPoint, hintText: l.meetingPointHint),
                validator: (v) => (v ?? '').trim().isEmpty ? l.meetingPointRequired : null,
              )
            else
              OutlinedButton.icon(
                key: const ValueKey('pick-venue'),
                onPressed: () => _pickVenue(context, options),
                icon: const Icon(Icons.place_outlined),
                label: Text(venueName ?? l.chooseVenue),
              ),
            if (sport.id == 'running') ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('distance-km'),
                controller: controller.distance,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: l.distanceLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('pace'),
                controller: controller.pace,
                maxLength: 30,
                decoration: InputDecoration(labelText: l.paceLabel, hintText: l.paceHint),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The whole range of a rating slider.
const kAllRatings = RangeValues(RatingRules.min, RatingRules.max);

/// "Level 2–4" and the slider that sets it, inside a card. [rated] (padel,
/// tennis) makes it a rating range, 1.0–7.0 in half steps.
class LevelRangeCard extends StatelessWidget {
  const LevelRangeCard({super.key, required this.values, required this.onChanged, this.rated = false});

  final RangeValues values;
  final ValueChanged<RangeValues> onChanged;
  final bool rated;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return SectionCard(
      title: rated ? l.ratingRangeLabel : l.levelRangeLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rated ? formatRatingRange(values.start, values.end) : l.levelRange(values.start.round(), values.end.round()),
            style: AppText.bodyStrong,
          ),
          if (rated)
            RangeSlider(
              key: const ValueKey('rating-range'),
              values: values,
              min: RatingRules.min,
              max: RatingRules.max,
              divisions: ((RatingRules.max - RatingRules.min) * 2).round(),
              labels: RangeLabels(formatRatingBound(values.start), formatRatingBound(values.end)),
              onChanged: onChanged,
            )
          else
            RangeSlider(
              key: const ValueKey('level-range'),
              values: values,
              min: 1,
              max: 5,
              divisions: 4,
              labels: RangeLabels('${values.start.round()}', '${values.end.round()}'),
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

/// A horizontal strip of days from today: [selected] is the offset in days.
class DayStrip extends StatelessWidget {
  const DayStrip({
    super.key,
    required this.today,
    required this.now,
    required this.selected,
    required this.onSelected,
    this.days = 14,
  });

  final DateTime today;
  final DateTime now;
  final int selected;
  final ValueChanged<int> onSelected;
  final int days;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i <= days; i++)
            FilterChipButton(
              label: dayLabel(l, context.lang, today.add(Duration(days: i)), now),
              selected: selected == i,
              onTap: () => onSelected(i),
            ),
        ],
      ),
    );
  }
}

/// A 24-hour time picker returning minutes after midnight.
Future<int?> pickMinuteOfDay(BuildContext context, int initial) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    builder: (context, child) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
  );
  return picked == null ? null : picked.hour * 60 + picked.minute;
}
