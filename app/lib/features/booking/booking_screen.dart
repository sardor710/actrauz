import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../data/sample/sample_media.dart';
import '../../domain/booking_engine.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'booking_summary_screen.dart';

/// Step 1–2 of booking: pick a date, a court and one or more back-to-back
/// slots. "Continue" holds them and opens the summary.
class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.venueId, required this.courtId});

  final String venueId;
  final String courtId;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  late String _courtId = widget.courtId;
  int _dayOffset = 0;
  List<SlotTime> _selected = [];
  bool _busy = false;

  /// Keeps the selection one unbroken run: tapping next to it extends it,
  /// tapping either end shrinks it, tapping elsewhere starts over.
  void _toggle(SlotTime slot) {
    setState(() {
      if (_selected.isEmpty) {
        _selected = [slot];
      } else if (slot == _selected.first || slot == _selected.last) {
        _selected = _selected.where((s) => s != slot).toList();
      } else if (slot.start == _selected.last.end) {
        _selected = [..._selected, slot];
      } else if (slot.end == _selected.first.start) {
        _selected = [slot, ..._selected];
      } else {
        _selected = [slot];
      }
    });
  }

  Future<void> _continue(Venue venue, Court court) async {
    final l = context.l;
    setState(() => _busy = true);
    try {
      final held = await ref.read(bookingRepositoryProvider).hold(venue.id, court.id, _selected);
      if (!mounted) return;
      final confirmed = await Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute(
          builder: (_) => BookingSummaryScreen(booking: held, venue: venue, court: court),
        ),
      );
      if (!mounted) return;
      setState(() => _selected = []);
      refreshBookings(ref);
      if (confirmed == true) context.push('/bookings');
    } on BookingException catch (e) {
      if (!mounted) return;
      setState(() => _selected = []);
      refreshBookings(ref);
      showMessage(context, bookingErrorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final now = ref.watch(cityNowProvider)();
    final today = dateOnly(now);
    final date = today.add(Duration(days: _dayOffset));
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];

    return Scaffold(
      appBar: AppBar(title: Text(l.bookingTitle)),
      body: AsyncBody(
        value: ref.watch(venueProvider(widget.venueId)),
        builder: (venue) {
          final court = venue.court(_courtId);
          final currency = cityById(venue.cityId).currency;
          final sport = sports.where((s) => s.id == court.sportId).firstOrNull;
          final slots = ref.watch(availabilityProvider((venueId: venue.id, courtId: court.id, date: date)));
          final total =
              slots.valueOrNull?.where((s) => _selected.contains(s.time)).fold<int>(0, (sum, s) => sum + s.price) ?? 0;
          final courtLine = [
            if (sport != null) sport.name.resolve(context.lang),
            court.indoor ? l.indoor : l.outdoor,
            l.slotLength(court.slotMinutes),
          ].join(' · ');

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    // What is being booked.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              PhotoBox(asset: venuePhoto(venue.id), width: 64, height: 64, radius: 14),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      venue.name.resolve(context.lang),
                                      style: manrope(16, 800),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(courtLine, style: AppText.muted, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SportBadge(sportId: court.sportId, size: 38),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 74,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: BookingEngine.maxDaysAhead + 1,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final day = today.add(Duration(days: i));
                          return _DayChip(
                            top: i == 0 ? l.today : weekdayShort(context.lang, day),
                            bottom: '${day.day}',
                            selected: i == _dayOffset,
                            onTap: () => setState(() {
                              _dayOffset = i;
                              _selected = [];
                            }),
                          );
                        },
                      ),
                    ),
                    if (venue.courts.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          height: 44,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              for (final c in venue.courts)
                                FilterChipButton(
                                  label: c.name.resolve(context.lang),
                                  selected: c.id == _courtId,
                                  onTap: () => setState(() {
                                    _courtId = c.id;
                                    _selected = [];
                                  }),
                                ),
                            ],
                          ),
                        ),
                      ),
                    AsyncBody(
                      value: slots,
                      builder: (views) {
                        if (views.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: EmptyState(icon: Icons.event_busy_outlined, text: l.closedThatDay),
                          );
                        }
                        // Morning before 12:00, evening from 17:00.
                        final groups = [
                          (l.morning, Icons.wb_twilight_rounded, views.where((v) => v.time.start.hour < 12).toList()),
                          (
                            l.afternoon,
                            Icons.wb_sunny_outlined,
                            views.where((v) => v.time.start.hour >= 12 && v.time.start.hour < 17).toList(),
                          ),
                          (l.evening, Icons.nights_stay_outlined, views.where((v) => v.time.start.hour >= 17).toList()),
                        ];
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                              child: LayoutBuilder(
                                builder: (context, box) {
                                  final tileWidth = (box.maxWidth - 20) / 3;
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      for (final (title, icon, items) in groups)
                                        if (items.isNotEmpty) ...[
                                          Padding(
                                            padding: const EdgeInsets.only(top: 14, bottom: 10),
                                            child: Row(
                                              children: [
                                                Icon(icon, size: 18, color: AppColors.muted),
                                                const SizedBox(width: 6),
                                                Text(
                                                  title.toUpperCase(),
                                                  style: AppText.sectionTitle.copyWith(fontSize: 12.5),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 10,
                                            children: [
                                              for (final view in items)
                                                _SlotTile(
                                                  view: view,
                                                  width: tileWidth,
                                                  priceText: money(l, view.price, currency),
                                                  selected: _selected.contains(view.time),
                                                  onTap: () => _toggle(view.time),
                                                ),
                                            ],
                                          ),
                                        ],
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Always visible, so the next step is never hidden.
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _selected.isEmpty
                              ? Text(l.selectHint, style: AppText.muted)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${l.slotsSelected(_selected.length)} · '
                                      '${timeRange(_selected.first.start, _selected.last.end)}',
                                      style: AppText.muted,
                                    ),
                                    Text('${l.total}: ${money(l, total, currency)}', style: manrope(17, 800)),
                                  ],
                                ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _selected.isEmpty || _busy ? null : () => _continue(venue, court),
                          child: Text(l.continueLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.top, required this.bottom, required this.selected, required this.onTap});

  final String top;
  final String bottom;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.ink;
    return Material(
      color: selected ? AppColors.primary : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 62),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(top, style: manrope(12.5, 600, color: selected ? Colors.white : AppColors.muted)),
              const SizedBox(height: 2),
              Text(bottom, style: manrope(19, 800, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.view,
    required this.width,
    required this.priceText,
    required this.selected,
    required this.onTap,
  });

  final SlotView view;
  final double width;
  final String priceText;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A slot this player is still holding is theirs to pick again.
    final available = view.state == SlotState.free || view.state == SlotState.mine;

    final Color background;
    final Color foreground;
    final Color border;
    if (selected) {
      background = AppColors.primary;
      foreground = Colors.white;
      border = AppColors.primary;
    } else if (available) {
      background = AppColors.primarySoft;
      foreground = AppColors.primaryDark;
      border = AppColors.primarySoft;
    } else {
      background = AppColors.page;
      foreground = AppColors.faint;
      border = AppColors.page;
    }

    return Semantics(
      button: true,
      enabled: available,
      selected: selected,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: available ? onTap : null,
          child: SizedBox(
            width: width,
            height: 62,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  hm(view.time.start),
                  style: manrope(
                    16.5,
                    800,
                    color: foreground,
                  ).copyWith(decoration: available ? null : TextDecoration.lineThrough, decorationColor: foreground),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    priceText,
                    style: manrope(
                      11.5,
                      600,
                      color: selected ? Colors.white : (available ? AppColors.ink : foreground),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
