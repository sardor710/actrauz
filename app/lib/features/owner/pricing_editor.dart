import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/pricing.dart';
import '../common/formatters.dart';
import 'hours_editor.dart';

/// What the owner saved in the price editor.
class PricingDraft {
  const PricingDraft({required this.slotMinutes, required this.basePrice, required this.rules});

  final int slotMinutes;
  final int basePrice;
  final List<PriceRule> rules;
}

/// Edits a court's slot length, base price and price rules (product spec
/// §11.4). Returns null when dismissed.
Future<PricingDraft?> showPricingEditor(BuildContext context, {required Court court, required Currency currency}) =>
    showModalBottomSheet<PricingDraft>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PricingSheet(court: court, currency: currency),
    );

class _RuleDraft {
  _RuleDraft({required this.weekdays, required this.from, required this.to, required int price})
    : price = TextEditingController(text: '$price');

  Set<int> weekdays;
  int from;
  int to;
  final TextEditingController price;
}

class _PricingSheet extends StatefulWidget {
  const _PricingSheet({required this.court, required this.currency});

  final Court court;
  final Currency currency;

  @override
  State<_PricingSheet> createState() => _PricingSheetState();
}

class _PricingSheetState extends State<_PricingSheet> {
  late int _slotMinutes = widget.court.slotMinutes;
  late final _base = TextEditingController(text: '${widget.court.basePrice}');
  late final List<_RuleDraft> _rules = [
    for (final rule in widget.court.priceRules)
      _RuleDraft(weekdays: {...rule.weekdays}, from: rule.fromMinute, to: rule.toMinute, price: rule.price),
  ];
  String? _error;

  @override
  void dispose() {
    _base.dispose();
    for (final rule in _rules) {
      rule.price.dispose();
    }
    super.dispose();
  }

  void _save() {
    final l = context.l;
    final base = int.tryParse(_base.text.trim());
    if (base == null || base < 0) return setState(() => _error = l.errPrice);

    final rules = <PriceRule>[];
    for (final draft in _rules) {
      final price = int.tryParse(draft.price.text.trim());
      if (price == null || price < 0) return setState(() => _error = l.errPrice);
      if (draft.weekdays.isEmpty) return setState(() => _error = l.errPickWeekday);
      if (draft.from >= draft.to) return setState(() => _error = l.errInvalidHours);
      rules.add(PriceRule(weekdays: draft.weekdays, fromMinute: draft.from, toMinute: draft.to, price: price));
    }
    // A slot must never have two prices.
    if (overlappingRules(rules).isNotEmpty) return setState(() => _error = l.errRulesOverlap);

    Navigator.of(context).pop(PricingDraft(slotMinutes: _slotMinutes, basePrice: base, rules: rules));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final currencyLabel = widget.currency == Currency.uzs ? l.currencyUzs : l.currencyKzt;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${l.pricesTitle} · ${widget.court.name.resolve(context.lang)}', style: AppText.title),
              const SizedBox(height: 16),
              Text(l.slotLengthLabel, style: AppText.bodyStrong),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final minutes in const [60, 90, 120])
                    ButtonSegment(value: minutes, label: Text(l.slotLength(minutes))),
                ],
                selected: {_slotMinutes},
                onSelectionChanged: (value) => setState(() => _slotMinutes = value.first),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('base-price'),
                controller: _base,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: l.basePrice, suffixText: currencyLabel),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 20),
              Text(l.priceRules.toUpperCase(), style: AppText.sectionTitle),
              const SizedBox(height: 8),
              if (_rules.isEmpty) Text(l.noRules, style: AppText.muted),
              for (var i = 0; i < _rules.length; i++) _ruleCard(i, currencyLabel),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _error = null;
                    _rules.add(
                      _RuleDraft(
                        weekdays: {1, 2, 3, 4, 5},
                        from: 18 * 60,
                        to: 24 * 60,
                        price: int.tryParse(_base.text.trim()) ?? widget.court.basePrice,
                      ),
                    );
                  }),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l.addRule),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: manrope(14, 600, color: AppColors.error)),
              ],
              const SizedBox(height: 14),
              FilledButton(onPressed: _save, child: Text(l.saveLabel)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ruleCard(int index, String currencyLabel) {
    final l = context.l;
    final rule = _rules[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.page,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      _DayToggle(
                        label: weekdayShortName(context.lang, d),
                        selected: rule.weekdays.contains(d),
                        onTap: () => setState(() {
                          _error = null;
                          rule.weekdays = rule.weekdays.contains(d)
                              ? ({...rule.weekdays}..remove(d))
                              : {...rule.weekdays, d};
                        }),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l.removeRule,
                onPressed: () => setState(() {
                  _error = null;
                  _rules.removeAt(index).price.dispose();
                }),
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: [
                Expanded(
                  child: TimeDropdown(
                    label: l.ruleFrom,
                    value: rule.from,
                    onChanged: (v) => setState(() {
                      rule.from = v;
                      _error = null;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TimeDropdown(
                    label: l.ruleTo,
                    value: rule.to,
                    onChanged: (v) => setState(() {
                      rule.to = v;
                      _error = null;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: TextField(
              controller: rule.price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: l.rulePrice, suffixText: currencyLabel),
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.primary : AppColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.line),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Text(label, style: manrope(12.5, 700, color: selected ? Colors.white : AppColors.ink)),
      ),
    ),
  );
}
