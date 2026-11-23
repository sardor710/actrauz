import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/owner.dart';
import '../../state/owner_providers.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';

/// Opens the form for a free cell: a walk-in or phone booking, or a block.
///
/// [slots] is the tapped slot followed by the free slots right after it, so the
/// owner can extend the booking. Returns `true` when something was saved.
Future<bool?> showWalkInSheet(
  BuildContext context, {
  required Venue venue,
  required Court court,
  required List<OwnerSlot> slots,
}) => showModalBottomSheet<bool>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _WalkInSheet(venue: venue, court: court, slots: slots),
);

enum _Mode { booking, block }

class _WalkInSheet extends ConsumerStatefulWidget {
  const _WalkInSheet({required this.venue, required this.court, required this.slots});

  final Venue venue;
  final Court court;
  final List<OwnerSlot> slots;

  @override
  ConsumerState<_WalkInSheet> createState() => _WalkInSheetState();
}

class _WalkInSheetState extends ConsumerState<_WalkInSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _reason = TextEditingController();

  _Mode _mode = _Mode.booking;
  WalkInPayment _payment = WalkInPayment.cash;
  int _players = 2;
  int _count = 1;
  bool _busy = false;
  String? _error;

  List<OwnerSlot> get _chosen => widget.slots.take(_count).toList();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l;
    if (_mode == _Mode.booking && !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(ownerRepositoryProvider);
    final times = [for (final slot in _chosen) slot.time];
    try {
      if (_mode == _Mode.booking) {
        final phone = _phone.text.trim();
        await repo.createWalkIn(
          widget.venue.id,
          widget.court.id,
          times,
          name: _name.text.trim(),
          phone: phone.isEmpty ? null : phone,
          players: _players,
          payment: _payment,
        );
      } else {
        final reason = _reason.text.trim();
        await repo.blockSlots(widget.venue.id, widget.court.id, times, reason: reason.isEmpty ? null : reason);
      }
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

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final currency = cityById(widget.venue.cityId).currency;
    final chosen = _chosen;
    final total = chosen.fold<int>(0, (sum, s) => sum + s.price);
    final now = venueNow(cityById(widget.venue.cityId), utcNow: ref.watch(clockProvider)());

    return Padding(
      // Keeps the form above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_mode == _Mode.booking ? l.newBooking : l.blockTime, style: AppText.title),
                const SizedBox(height: 4),
                Text(
                  '${widget.court.name.resolve(context.lang)} · '
                  '${dayLabel(l, context.lang, chosen.first.time.start, now)} · '
                  '${timeRange(chosen.first.time.start, chosen.last.time.end)}',
                  style: AppText.muted.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 16),
                SegmentedButton<_Mode>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: _Mode.booking, label: Text(l.newBooking)),
                    ButtonSegment(value: _Mode.block, label: Text(l.blockTime)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) => setState(() {
                    _mode = value.first;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 16),
                if (_mode == _Mode.booking) ...[
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: l.customerName),
                    validator: (value) => (value == null || value.trim().isEmpty) ? l.customerNameRequired : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: l.customerPhone),
                  ),
                  const SizedBox(height: 16),
                  Text(l.paymentMethod, style: AppText.bodyStrong),
                  const SizedBox(height: 8),
                  SegmentedButton<WalkInPayment>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: WalkInPayment.cash, label: Text(l.payCash)),
                      ButtonSegment(value: WalkInPayment.card, label: Text(l.payCard)),
                      ButtonSegment(value: WalkInPayment.transfer, label: Text(l.payTransfer)),
                    ],
                    selected: {_payment},
                    onSelectionChanged: (value) => setState(() => _payment = value.first),
                  ),
                  const SizedBox(height: 12),
                  _Stepper(
                    label: l.playersCount,
                    value: _players,
                    min: 1,
                    max: 30,
                    onChanged: (v) => setState(() => _players = v),
                  ),
                ] else
                  TextFormField(
                    controller: _reason,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: l.blockReason),
                  ),
                if (widget.slots.length > 1) ...[
                  const SizedBox(height: 4),
                  _Stepper(
                    label: l.slotsCountLabel,
                    value: _count,
                    min: 1,
                    max: widget.slots.length,
                    onChanged: (v) => setState(() => _count = v),
                  ),
                ],
                if (_mode == _Mode.booking) ...[
                  const Divider(height: 28),
                  Row(
                    children: [
                      Expanded(child: Text(l.total, style: AppText.muted.copyWith(fontSize: 15))),
                      Text(money(l, total, currency), style: manrope(19, 800)),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: manrope(14, 600, color: AppColors.error)),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_mode == _Mode.booking ? l.saveBooking : l.blockConfirm),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: AppText.bodyStrong)),
      IconButton.filledTonal(
        onPressed: value > min ? () => onChanged(value - 1) : null,
        icon: const Icon(Icons.remove_rounded),
      ),
      SizedBox(
        width: 40,
        child: Text('$value', textAlign: TextAlign.center, style: manrope(17, 800)),
      ),
      IconButton.filledTonal(
        onPressed: value < max ? () => onChanged(value + 1) : null,
        icon: const Icon(Icons.add_rounded),
      ),
    ],
  );
}
