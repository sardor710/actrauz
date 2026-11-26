import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/booking_engine.dart';
import '../../domain/models.dart';
import '../../domain/owner.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/owner_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// Opens a booked or blocked cell: who, when, how much, and the owner's
/// actions. Returns `true` when the booking was changed.
Future<bool?> showBookingDetailsSheet(
  BuildContext context, {
  required Venue venue,
  required Court court,
  required OwnerBooking booking,
  required DateTime now,
}) => showModalBottomSheet<bool>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _DetailsSheet(venue: venue, court: court, booking: booking, now: now),
);

String ownerStatusText(AppLocalizations l, OwnerBooking booking) => switch (booking.status) {
  BookingStatus.paid => l.statusPaid,
  BookingStatus.noShow => l.statusNoShow,
  BookingStatus.completed => l.statusCompleted,
  BookingStatus.cancelledByVenue => l.statusCancelledByVenue,
  BookingStatus.cancelledByPlayer => l.statusCancelled,
  _ => l.statusConfirmed,
};

String ownerSourceText(AppLocalizations l, BookingSource source) => switch (source) {
  BookingSource.app => l.sourceApp,
  BookingSource.walkIn => l.sourceWalkIn,
  BookingSource.block => l.sourceBlock,
};

String walkInPaymentText(AppLocalizations l, WalkInPayment payment) => switch (payment) {
  WalkInPayment.cash => l.payCash,
  WalkInPayment.card => l.payCard,
  WalkInPayment.transfer => l.payTransfer,
};

class _DetailsSheet extends ConsumerStatefulWidget {
  const _DetailsSheet({required this.venue, required this.court, required this.booking, required this.now});

  final Venue venue;
  final Court court;
  final OwnerBooking booking;
  final DateTime now;

  @override
  ConsumerState<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends ConsumerState<_DetailsSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<OwnerBooking> Function() action) async {
    final l = context.l;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = bookingErrorText(l, e);
        });
      }
    }
  }

  Future<void> _cancel() async {
    final l = context.l;
    final isBlock = widget.booking.source == BookingSource.block;
    final repo = ref.read(ownerRepositoryProvider);
    if (!isBlock) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.cancelConfirmTitle),
          content: Text(l.cancelByVenueMsg),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.keepBooking)),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.cancelBooking)),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _run(() => repo.cancel(widget.booking.id));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final booking = widget.booking;
    final repo = ref.read(ownerRepositoryProvider);
    final currency = cityById(widget.venue.cityId).currency;
    final isBlock = booking.source == BookingSource.block;
    final started = !booking.start.isAfter(widget.now);
    final ended = !booking.end.isAfter(widget.now);
    final canCancel = booking.status == BookingStatus.confirmed && !ended;
    final canMark = !isBlock && started;

    final (Color statusBg, Color statusFg) = switch (booking.status) {
      BookingStatus.paid => (AppColors.primarySoft, AppColors.primaryDark),
      BookingStatus.noShow => (AppColors.errorSoft, AppColors.error),
      _ => (AppColors.field, AppColors.ink),
    };

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isBlock
                        ? l.slotBlocked
                        : booking.customerDeleted
                        ? l.deletedPlayer
                        : (booking.customerName ?? l.summaryTitle),
                    style: AppText.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isBlock) Pill(text: ownerStatusText(l, booking), color: statusBg, onColor: statusFg, large: true),
              ],
            ),
            const SizedBox(height: 14),
            _Line(label: l.courtLabel, value: widget.court.name.resolve(context.lang)),
            _Line(label: l.dateLabel, value: dayLabel(l, context.lang, booking.start, widget.now)),
            _Line(label: l.timeLabel, value: timeRange(booking.start, booking.end)),
            _Line(label: l.sourceLabel, value: ownerSourceText(l, booking.source)),
            if (isBlock && (booking.reason ?? '').isNotEmpty) _Line(label: l.reasonLabel, value: booking.reason!),
            if (!isBlock) ...[
              if ((booking.customerPhone ?? '').isNotEmpty) _Line(label: l.phone, value: booking.customerPhone!),
              if (booking.players != null) _Line(label: l.playersCount, value: '${booking.players}'),
              _Line(
                label: l.paymentMethod,
                value: booking.walkInPayment == null ? l.payAtVenue : walkInPaymentText(l, booking.walkInPayment!),
              ),
              if ((booking.note ?? '').isNotEmpty) _Line(label: l.noteLabel, value: booking.note!),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(child: Text(l.total, style: AppText.muted.copyWith(fontSize: 15))),
                  Text(money(l, booking.totalPrice, currency), style: manrope(19, 800)),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: manrope(14, 600, color: AppColors.error)),
            ],
            const SizedBox(height: 18),
            if (!isBlock) ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: canMark && !_busy && booking.status != BookingStatus.paid
                          ? () => _run(() => repo.mark(booking.id, BookingOutcome.paid))
                          : null,
                      child: Text(l.markPaid, textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: canMark && !_busy && booking.status != BookingStatus.noShow
                          ? () => _run(() => repo.mark(booking.id, BookingOutcome.noShow))
                          : null,
                      child: Text(l.markNoShow, textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ),
              if (!started)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l.markAfterStart, style: AppText.caption, textAlign: TextAlign.center),
                ),
            ],
            if (canCancel) ...[
              const SizedBox(height: 10),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.error, minimumSize: const Size(64, 48)),
                onPressed: _busy ? null : _cancel,
                child: Text(isBlock ? l.unblock : l.cancelBooking),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 132, child: Text(label, style: AppText.muted.copyWith(fontSize: 15))),
        Expanded(
          child: Text(value, style: manrope(15, 700), textAlign: TextAlign.end),
        ),
      ],
    ),
  );
}
