import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/booking_engine.dart';
import '../../domain/models.dart';
import '../../domain/owner.dart';
import '../../state/owner_providers.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'booking_details_sheet.dart';
import 'walk_in_sheet.dart';

/// Key of one calendar cell, e.g. `owner-cell-2026-11-22T11:30`.
String ownerCellKey(DateTime start) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'owner-cell-${start.year}-${two(start.month)}-${two(start.day)}T${hm(start)}';
}

/// The owner's weekly calendar for one court (product spec §11.5): days across,
/// slot times down. Free cells take a new booking, booked cells open details.
class OwnerCalendarScreen extends ConsumerStatefulWidget {
  const OwnerCalendarScreen({super.key, required this.venueId});

  final String venueId;

  @override
  ConsumerState<OwnerCalendarScreen> createState() => _OwnerCalendarScreenState();
}

class _OwnerCalendarScreenState extends ConsumerState<OwnerCalendarScreen> {
  String? _courtId;

  /// Weeks from the current one: 0 = this week.
  int _weekOffset = 0;

  static DateTime _monday(DateTime day) => dateOnly(day).subtract(Duration(days: day.weekday - 1));

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final venue = ref.watch(myVenuesProvider).valueOrNull?.where((v) => v.id == widget.venueId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text(venue?.name.resolve(context.lang) ?? l.ownerCalendar),
        actions: [
          IconButton(
            tooltip: l.ownerDashboard,
            onPressed: () => context.push('/owner/${widget.venueId}/dashboard'),
            icon: const Icon(Icons.insights_rounded),
          ),
          IconButton(
            tooltip: l.ownerSettings,
            onPressed: () => context.push('/owner/${widget.venueId}/settings'),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AsyncBody(
        value: ref.watch(myVenuesProvider),
        builder: (venues) {
          final venue = venues.where((v) => v.id == widget.venueId).firstOrNull;
          if (venue == null || venue.courts.isEmpty) {
            return Center(
              child: EmptyState(icon: Icons.lock_outline_rounded, text: l.errNotAllowed),
            );
          }
          final court = venue.courts.where((c) => c.id == _courtId).firstOrNull ?? venue.courts.first;
          final now = venueNow(cityById(venue.cityId), utcNow: ref.watch(clockProvider)());
          final weekStart = _monday(now).add(Duration(days: 7 * _weekOffset));
          final weekEnd = weekStart.add(const Duration(days: 6));
          final calendar = ref.watch(ownerCalendarProvider((venueId: venue.id, courtId: court.id, from: weekStart)));
          final range =
              '${DateFormat('d MMM', context.lang).format(weekStart)} – '
              '${DateFormat('d MMM', context.lang).format(weekEnd)}';

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (venue.courts.length > 1)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final c in venue.courts)
                        FilterChipButton(
                          label: c.name.resolve(context.lang),
                          selected: c.id == court.id,
                          onTap: () => setState(() => _courtId = c.id),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: l.prevWeek,
                      onPressed: () => setState(() => _weekOffset--),
                      icon: const Icon(Icons.chevron_left_rounded, size: 28),
                    ),
                    Expanded(
                      child: Text(range, textAlign: TextAlign.center, style: manrope(16.5, 800), maxLines: 1),
                    ),
                    IconButton(
                      tooltip: l.nextWeek,
                      onPressed: () => setState(() => _weekOffset++),
                      icon: const Icon(Icons.chevron_right_rounded, size: 28),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                      onPressed: _weekOffset == 0 ? null : () => setState(() => _weekOffset = 0),
                      child: Text(l.today),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _Legend(color: AppColors.primarySoft, border: AppColors.primary, text: l.slotFree),
                    _Legend(color: AppColors.ink, border: AppColors.ink, text: l.slotBooked),
                    _Legend(color: AppColors.amberSoft, border: AppColors.amber, text: l.slotBlocked),
                  ],
                ),
              ),
              AsyncBody(
                value: calendar,
                builder: (data) => _WeekGrid(
                  calendar: data,
                  weekStart: weekStart,
                  now: now,
                  onFree: (slot, following) => _newBooking(venue, court, slot, following),
                  onBooking: (booking, tournament) => _details(venue, court, booking, tournament, now),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _newBooking(Venue venue, Court court, OwnerSlot slot, List<OwnerSlot> following) async {
    final saved = await showWalkInSheet(context, venue: venue, court: court, slots: [slot, ...following]);
    if (saved == true && mounted) refreshOwner(ref);
  }

  Future<void> _details(
    Venue venue,
    Court court,
    OwnerBooking booking,
    TournamentBlockRef? tournament,
    DateTime now,
  ) async {
    final changed = await showBookingDetailsSheet(
      context,
      venue: venue,
      court: court,
      booking: booking,
      tournament: tournament,
      now: now,
    );
    if (changed == true && mounted) refreshOwner(ref);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.border, required this.text});

  final Color color;
  final Color border;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border),
        ),
      ),
      const SizedBox(width: 6),
      Text(text, style: AppText.caption),
    ],
  );
}

class _WeekGrid extends StatefulWidget {
  const _WeekGrid({
    required this.calendar,
    required this.weekStart,
    required this.now,
    required this.onFree,
    required this.onBooking,
  });

  final OwnerCalendar calendar;
  final DateTime weekStart;
  final DateTime now;

  /// The tapped free slot and the free slots that follow it without a gap.
  final void Function(OwnerSlot slot, List<OwnerSlot> following) onFree;

  /// The tapped booked or blocked slot's row, and its tournament match if it
  /// holds the court for one.
  final void Function(OwnerBooking booking, TournamentBlockRef? tournament) onBooking;

  static const _timeWidth = 50.0;
  static const _headerHeight = 50.0;
  static const _cellHeight = 54.0;
  static const _minColumn = 76.0;

  @override
  State<_WeekGrid> createState() => _WeekGridState();
}

class _WeekGridState extends State<_WeekGrid> {
  static const _timeWidth = _WeekGrid._timeWidth;
  static const _headerHeight = _WeekGrid._headerHeight;
  static const _cellHeight = _WeekGrid._cellHeight;
  static const _minColumn = _WeekGrid._minColumn;

  final _scroll = ScrollController();

  /// The week the view was last scrolled for, so it happens once per week.
  DateTime? _scrolledFor;

  OwnerCalendar get calendar => widget.calendar;
  DateTime get weekStart => widget.weekStart;
  DateTime get now => widget.now;
  void Function(OwnerSlot slot, List<OwnerSlot> following) get onFree => widget.onFree;
  void Function(OwnerBooking booking, TournamentBlockRef? tournament) get onBooking => widget.onBooking;

  static int _minuteOf(DateTime t) => t.hour * 60 + t.minute;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// On a narrow screen the week does not fit: bring today into view when the
  /// current week opens, and start other weeks from Monday.
  void _showToday(double column) {
    if (_scrolledFor == weekStart) return;
    _scrolledFor = weekStart;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final index = dateOnly(now).difference(weekStart).inDays;
      final target = index >= 0 && index < 7 ? (index - 1) * column : 0.0;
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final days = [for (var d = 0; d < 7; d++) weekStart.add(Duration(days: d))];
    final byDay = [for (final day in days) calendar.slotsOn(day)];
    // Rows are every slot time any day of the week offers: only operating hours.
    final minutes = {for (final slots in byDay) ...slots.map((s) => _minuteOf(s.time.start))}.toList()..sort();

    if (minutes.isEmpty) {
      return EmptyState(icon: Icons.event_busy_outlined, text: l.closedThatWeek);
    }

    OwnerSlot? at(int day, int minute) => byDay[day].where((s) => _minuteOf(s.time.start) == minute).firstOrNull;

    List<OwnerSlot> followingFree(int day, OwnerSlot slot) {
      final rest = byDay[day].where((s) => s.time.start.isAfter(slot.time.start)).toList()
        ..sort((a, b) => a.time.start.compareTo(b.time.start));
      final run = <OwnerSlot>[];
      var end = slot.time.end;
      for (final next in rest) {
        if (next.state != OwnerSlotState.free || next.time.start != end) break;
        run.add(next);
        end = next.time.end;
      }
      return run;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: LayoutBuilder(
          builder: (context, box) {
            final column = math.max(_minColumn, (box.maxWidth - _timeWidth) / 7);
            _showToday(column);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Slot times stay put while the days scroll sideways.
                SizedBox(
                  width: _timeWidth,
                  child: Column(
                    children: [
                      const SizedBox(height: _headerHeight),
                      for (final minute in minutes)
                        SizedBox(
                          height: _cellHeight,
                          child: Center(
                            child: Text(minutesHm(minute), style: manrope(12, 700, color: AppColors.muted)),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: column * 7,
                      child: Column(
                        children: [
                          SizedBox(
                            height: _headerHeight,
                            child: Row(
                              children: [
                                for (final day in days)
                                  SizedBox(
                                    width: column,
                                    child: _DayHeader(day: day, today: dateOnly(day) == dateOnly(now)),
                                  ),
                              ],
                            ),
                          ),
                          for (final minute in minutes)
                            SizedBox(
                              height: _cellHeight,
                              child: Row(
                                children: [
                                  for (var d = 0; d < 7; d++)
                                    SizedBox(
                                      width: column,
                                      child: Builder(
                                        builder: (context) {
                                          final slot = at(d, minute);
                                          if (slot == null) return const SizedBox.shrink();
                                          final booking = slot.bookingId == null
                                              ? null
                                              : calendar.bookings[slot.bookingId];
                                          return _Cell(
                                            key: ValueKey(ownerCellKey(slot.time.start)),
                                            slot: slot,
                                            booking: booking,
                                            onTap: switch (slot.state) {
                                              OwnerSlotState.free => () => onFree(slot, followingFree(d, slot)),
                                              OwnerSlotState.booked || OwnerSlotState.blocked =>
                                                booking == null ? null : () => onBooking(booking, slot.tournament),
                                              OwnerSlotState.past => null,
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.today});

  final DateTime day;
  final bool today;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: today ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            weekdayShort(context.lang, day),
            style: manrope(11.5, 600, color: today ? Colors.white : AppColors.muted),
            maxLines: 1,
          ),
          Text('${day.day}', style: manrope(15, 800, color: today ? Colors.white : AppColors.ink)),
        ],
      ),
    ),
  );
}

class _Cell extends StatelessWidget {
  const _Cell({super.key, required this.slot, required this.booking, required this.onTap});

  final OwnerSlot slot;
  final OwnerBooking? booking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final Color background;
    final Widget content;
    final String label;

    switch (slot.state) {
      case OwnerSlotState.free:
        background = AppColors.primarySoft;
        label = l.slotFree;
        content = const Icon(Icons.add_rounded, size: 18, color: AppColors.primaryDark);
      case OwnerSlotState.past:
        background = AppColors.page;
        label = '';
        content = const SizedBox.shrink();
      case OwnerSlotState.blocked:
        background = AppColors.amberSoft;
        if (slot.tournament case final tournament?) {
          // A tournament match: "Tournament: <title>".
          label = l.calendarTournament(tournament.title.resolve(context.lang));
          content = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: manrope(11, 700, color: const Color(0xFF7A4B00), height: 1.15),
            ),
          );
        } else {
          label = l.slotBlocked;
          content = const Icon(Icons.lock_outline_rounded, size: 17, color: Color(0xFF7A4B00));
        }
      case OwnerSlotState.booked:
        final status = booking?.status;
        background = switch (status) {
          BookingStatus.paid => AppColors.primaryDark,
          BookingStatus.noShow => AppColors.error,
          _ => AppColors.ink,
        };
        label = (booking?.customerDeleted ?? false) ? l.deletedPlayer : booking?.customerName ?? l.slotBooked;
        content = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: manrope(11.5, 700, color: Colors.white, height: 1.15),
          ),
        );
    }

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: onTap != null,
        label: '${hm(slot.time.start)} $label',
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}
