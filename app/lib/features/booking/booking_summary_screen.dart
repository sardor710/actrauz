import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../domain/booking_engine.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// Step 3–5 of booking: the slots are held while the player reviews the
/// summary and confirms. Leaving without confirming releases the hold.
///
/// Pops with `true` when the booking was confirmed.
class BookingSummaryScreen extends ConsumerStatefulWidget {
  const BookingSummaryScreen({super.key, required this.booking, required this.venue, required this.court});

  final Booking booking;
  final Venue venue;
  final Court court;

  @override
  ConsumerState<BookingSummaryScreen> createState() => _BookingSummaryScreenState();
}

class _BookingSummaryScreenState extends ConsumerState<BookingSummaryScreen> {
  final _note = TextEditingController();
  Timer? _ticker;
  int _players = 2;
  bool _busy = false;
  bool _done = false;

  City get _city => cityById(widget.venue.cityId);

  Duration get _remaining {
    final now = venueNow(_city, utcNow: ref.read(clockProvider)());
    return widget.booking.holdExpiresAt!.difference(now);
  }

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _done) return;
      if (_remaining <= Duration.zero) {
        _expire();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _note.dispose();
    super.dispose();
  }

  void _expire() {
    _done = true;
    _ticker?.cancel();
    final l = context.l;
    Navigator.of(context).pop(false);
    showMessage(context, l.holdExpiredMsg);
  }

  Future<void> _release() async {
    if (_done) return;
    _done = true;
    await ref.read(bookingRepositoryProvider).release(widget.booking.id);
  }

  Future<void> _confirm() async {
    final l = context.l;
    setState(() => _busy = true);
    try {
      final note = _note.text.trim();
      await ref
          .read(bookingRepositoryProvider)
          .confirm(widget.booking.id, players: _players, note: note.isEmpty ? null : note);
      _done = true;
      _ticker?.cancel();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(Icons.check_circle, size: 48, color: Theme.of(context).colorScheme.primary),
          title: Text(l.bookingConfirmed),
          content: Text(l.payAtVenueHint, textAlign: TextAlign.center),
          actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.myBookings))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on BookingException catch (e) {
      if (!mounted) return;
      _done = true;
      Navigator.of(context).pop(false);
      showMessage(context, bookingErrorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final booking = widget.booking;
    final now = venueNow(_city, utcNow: ref.read(clockProvider)());
    final remaining = _remaining.isNegative ? Duration.zero : _remaining;
    final countdown =
        '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _release();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.summaryTitle)),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        Icon(Icons.timer_outlined, color: scheme.onTertiaryContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(l.heldFor(countdown), style: TextStyle(color: scheme.onTertiaryContainer)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.venue.name.resolve(context.lang),
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          _Row(label: l.courtLabel, value: widget.court.name.resolve(context.lang)),
                          _Row(label: l.dateLabel, value: dayLabel(l, context.lang, booking.start, now)),
                          _Row(label: l.timeLabel, value: timeRange(booking.start, booking.end)),
                          const Divider(height: 24),
                          _Row(label: l.total, value: money(l, booking.totalPrice, _city.currency), strong: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(l.paymentMethod, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Card(
                    color: scheme.primaryContainer,
                    child: ListTile(
                      leading: Icon(Icons.payments_outlined, color: scheme.onPrimaryContainer),
                      title: Text(l.payAtVenue, style: TextStyle(color: scheme.onPrimaryContainer)),
                      subtitle: Text(l.payAtVenueHint, style: TextStyle(color: scheme.onPrimaryContainer)),
                      trailing: Icon(Icons.radio_button_checked, color: scheme.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Text(l.playersCount, style: theme.textTheme.titleMedium)),
                      IconButton.filledTonal(
                        onPressed: _players > 1 ? () => setState(() => _players--) : null,
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text('$_players', textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                      ),
                      IconButton.filledTonal(
                        onPressed: _players < 30 ? () => setState(() => _players++) : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _note,
                    maxLength: 200,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: l.noteLabel),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: _busy ? null : _confirm, child: Text(l.confirmBooking)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Text(
            value,
            style: strong
                ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)
                : theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
