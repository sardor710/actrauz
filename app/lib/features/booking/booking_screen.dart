import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
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
      if (confirmed == true) context.go('/profile/bookings');
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
    final theme = Theme.of(context);
    final now = ref.watch(cityNowProvider)();
    final today = dateOnly(now);
    final date = today.add(Duration(days: _dayOffset));

    return Scaffold(
      appBar: AppBar(title: Text(l.bookingTitle)),
      body: AsyncBody(
        value: ref.watch(venueProvider(widget.venueId)),
        builder: (venue) {
          final court = venue.court(_courtId);
          final currency = cityById(venue.cityId).currency;
          final slots = ref.watch(availabilityProvider((venueId: venue.id, courtId: court.id, date: date)));
          final total = slots.valueOrNull
              ?.where((s) => _selected.contains(s.time))
              .fold<int>(0, (sum, s) => sum + s.price);

          return Column(
            children: [
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final c in venue.courts)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c.name.resolve(context.lang)),
                            selected: c.id == _courtId,
                            onSelected: (_) => setState(() {
                              _courtId = c.id;
                              _selected = [];
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: AsyncBody(
                  value: slots,
                  builder: (views) {
                    if (views.isEmpty) {
                      return Center(child: EmptyState(icon: Icons.event_busy_outlined, text: l.closedThatDay));
                    }
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          l.selectHint,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final view in views)
                              _SlotTile(
                                view: view,
                                priceText: money(l, view.price, currency),
                                selected: _selected.contains(view.time),
                                onTap: () => _toggle(view.time),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (_selected.isNotEmpty && total != null)
                Material(
                  elevation: 8,
                  color: theme.colorScheme.surfaceContainer,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${l.slotsSelected(_selected.length)} · '
                                  '${timeRange(_selected.first.start, _selected.last.end)}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                Text(
                                  '${l.total}: ${money(l, total, currency)}',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: _busy ? null : () => _continue(venue, court),
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
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 60),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(top, style: TextStyle(color: fg, fontSize: 12)),
              Text(bottom, style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.view, required this.priceText, required this.selected, required this.onTap});

  final SlotView view;
  final String priceText;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A slot this player is still holding is theirs to pick again.
    final available = view.state == SlotState.free || view.state == SlotState.mine;

    final Color background;
    final Color foreground;
    if (selected) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
    } else if (available) {
      background = scheme.surfaceContainerHigh;
      foreground = scheme.onSurface;
    } else {
      background = scheme.surfaceContainerLowest;
      foreground = scheme.outline;
    }

    return Semantics(
      button: true,
      enabled: available,
      selected: selected,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: available ? scheme.outlineVariant : Colors.transparent),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: available ? onTap : null,
          child: SizedBox(
            width: 104,
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  hm(view.time.start),
                  style: TextStyle(
                    color: foreground,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    decoration: available ? null : TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 2),
                Text(priceText, style: TextStyle(color: foreground, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
