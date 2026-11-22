import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../domain/booking_engine.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// "My bookings": upcoming and past, with cancellation.
class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text(l.myBookings),
      ),
      body: AsyncBody(
        value: ref.watch(myBookingsProvider),
        builder: (bookings) => bookings.isEmpty
            ? Center(child: EmptyState(icon: Icons.event_available_outlined, text: l.noBookings))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: bookings.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _BookingCard(booking: bookings[i]),
              ),
      ),
    );
  }
}

class _BookingCard extends ConsumerWidget {
  const _BookingCard({required this.booking});

  final Booking booking;

  Future<void> _cancel(BuildContext context, WidgetRef ref, {required bool late}) async {
    final l = context.l;
    final hours = BookingEngine.freeCancelWindow.inHours;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.cancelConfirmTitle),
        content: Text(late ? l.cancelLateMsg(hours) : l.cancelFreeMsg),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.keepBooking)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.cancelBooking)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(bookingRepositoryProvider).cancel(booking.id);
      refreshBookings(ref);
      if (context.mounted) showMessage(context, l.bookingCancelled);
    } on BookingException catch (e) {
      if (context.mounted) showMessage(context, bookingErrorText(l, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final venue = ref.watch(venueProvider(booking.venueId)).valueOrNull;
    if (venue == null) return const SizedBox.shrink();

    final city = cityById(venue.cityId);
    final now = venueNow(city, utcNow: ref.watch(clockProvider)());
    final court = venue.court(booking.courtId);
    final cancelled =
        booking.status == BookingStatus.cancelledByPlayer || booking.status == BookingStatus.cancelledByVenue;
    final ended = !booking.end.isAfter(now);
    final canCancel = booking.status == BookingStatus.confirmed && booking.start.isAfter(now);
    final late = booking.start.difference(now) < BookingEngine.freeCancelWindow;

    final (String status, Color bg, Color fg) = cancelled
        ? (l.statusCancelled, scheme.errorContainer, scheme.onErrorContainer)
        : ended
        ? (l.statusCompleted, scheme.surfaceContainerHighest, scheme.onSurfaceVariant)
        : (l.statusConfirmed, scheme.primaryContainer, scheme.onPrimaryContainer);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    venue.name.resolve(context.lang),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Pill(text: status, color: bg, onColor: fg),
              ],
            ),
            const SizedBox(height: 6),
            Text(court.name.resolve(context.lang), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(
              '${dayLabel(l, context.lang, booking.start, now)}, ${timeRange(booking.start, booking.end)}',
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${money(l, booking.totalPrice, city.currency)} · ${l.payAtVenue}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                if (booking.lateCancellation) Pill(text: l.lateCancellation, icon: Icons.warning_amber_outlined),
              ],
            ),
            if (canCancel) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _cancel(context, ref, late: late),
                child: Text(l.cancelBooking),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
