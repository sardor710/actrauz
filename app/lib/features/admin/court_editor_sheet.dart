import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../domain/admin.dart';
import '../../domain/booking_engine.dart';
import '../../state/admin_providers.dart';
import '../common/formatters.dart';
import 'admin_common.dart';
import 'localized_field.dart';

/// Creates or edits a court (product spec §12.2). Returns `true` when saved;
/// the caller refreshes and says so.
Future<bool?> showCourtEditor(BuildContext context, {required CourtDraft draft, required String cityId}) =>
    showAdminSheet(context, (context) => _CourtSheet(draft: draft, cityId: cityId));

class _CourtSheet extends ConsumerStatefulWidget {
  const _CourtSheet({required this.draft, required this.cityId});

  final CourtDraft draft;
  final String cityId;

  @override
  ConsumerState<_CourtSheet> createState() => _CourtSheetState();
}

class _CourtSheetState extends ConsumerState<_CourtSheet> {
  final _form = GlobalKey<FormState>();
  late final CourtDraft _draft = widget.draft;
  late final _price = TextEditingController(text: widget.draft.id == null ? '' : '${widget.draft.basePrice}');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    _draft.basePrice = int.parse(_price.text.trim());
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).saveCourt(_draft);
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
    final currency = cityById(widget.cityId).currency;
    final sports = (ref.watch(adminSportsProvider).valueOrNull ?? const <AdminSport>[])
        .where((s) => s.sport.bookable && (s.active || s.sport.id == _draft.sportId))
        .toList();

    return Form(
      key: _form,
      child: AdminSheetFrame(
        title: _draft.id == null ? l.newCourt : l.editCourt,
        saveKey: const ValueKey('save-court'),
        busy: _busy,
        error: _error,
        onSave: _save,
        children: [
          LocalizedField(
            fieldKey: 'court-name',
            label: l.nameLabel,
            initial: _draft.name,
            required: true,
            onChanged: (v) => _draft.name = v,
          ),
          const SizedBox(height: 12),
          FieldLabel(l.filterSport),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in sports)
                ChoiceChip(
                  key: ValueKey('court-sport-${s.sport.id}'),
                  label: Text(s.sport.name.resolve(context.lang)),
                  selected: s.sport.id == _draft.sportId,
                  onSelected: (_) => setState(() => _draft.sportId = s.sport.id),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FieldLabel(l.slotLengthLabel),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final minutes in const [60, 90, 120]) ButtonSegment(value: minutes, label: Text(l.slotLength(minutes))),
            ],
            selected: {_draft.slotMinutes},
            onSelectionChanged: (value) => setState(() => _draft.slotMinutes = value.first),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('court-price'),
            controller: _price,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l.basePrice,
              suffixText: currency == Currency.uzs ? l.currencyUzs : l.currencyKzt,
            ),
            validator: (value) {
              final price = int.tryParse(value?.trim() ?? '');
              return price == null || price < 0 || price > BookingEngine.maxPrice ? l.errPrice : null;
            },
          ),
          const SizedBox(height: 8),
          AdminSwitch(
            key: const ValueKey('court-indoor'),
            label: l.indoor,
            value: _draft.indoor,
            onChanged: (v) => setState(() => _draft.indoor = v),
          ),
          AdminSwitch(
            key: const ValueKey('court-active'),
            label: l.activeLabel,
            hint: l.activeHint,
            value: _draft.active,
            onChanged: (v) => setState(() => _draft.active = v),
          ),
        ],
      ),
    );
  }
}
