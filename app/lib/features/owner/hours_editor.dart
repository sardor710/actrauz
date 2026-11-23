import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../common/formatters.dart';

/// Half-hour steps from 00:00 to 24:00, in minutes from midnight.
final kHalfHours = [for (var m = 0; m <= 24 * 60; m += 30) m];

/// Full weekday name in the app language; [weekday] 1 = Monday.
String weekdayName(String lang, int weekday) {
  // 5 January 2026 is a Monday.
  final name = DateFormat('EEEE', lang).format(DateTime.utc(2026, 1, 4 + weekday));
  return name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
}

String weekdayShortName(String lang, int weekday) => DateFormat('EEE', lang).format(DateTime.utc(2026, 1, 4 + weekday));

/// Edits opening hours for the seven weekdays.
///
/// For a venue ([inherited] null) every day is open or closed, and the result
/// has all seven days. For a court, [inherited] is the venue's hours: a day
/// can also follow the venue, and the result holds only the days that differ.
/// Returns null when dismissed.
Future<WeekHours?> showHoursEditor(
  BuildContext context, {
  required String title,
  required WeekHours initial,
  WeekHours? inherited,
}) => showModalBottomSheet<WeekHours>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _HoursSheet(title: title, initial: initial, inherited: inherited),
);

enum _DayMode { inherit, open, closed }

class _Day {
  _Day(this.mode, this.open, this.close);

  _DayMode mode;
  int open;
  int close;
}

class _HoursSheet extends StatefulWidget {
  const _HoursSheet({required this.title, required this.initial, required this.inherited});

  final String title;
  final WeekHours initial;
  final WeekHours? inherited;

  @override
  State<_HoursSheet> createState() => _HoursSheetState();
}

class _HoursSheetState extends State<_HoursSheet> {
  late final Map<int, _Day> _days;
  String? _error;

  bool get _forCourt => widget.inherited != null;

  @override
  void initState() {
    super.initState();
    _days = {
      for (var d = 1; d <= 7; d++)
        d: () {
          final own = widget.initial[d];
          final fallback = widget.inherited?[d] ?? const DayHours.hm(8, 0, 22, 0);
          if (_forCourt && !widget.initial.containsKey(d)) {
            return _Day(_DayMode.inherit, fallback.openMinute, fallback.closeMinute);
          }
          if (own == null) return _Day(_DayMode.closed, fallback.openMinute, fallback.closeMinute);
          return _Day(_DayMode.open, own.openMinute, own.closeMinute);
        }(),
    };
  }

  void _save() {
    final l = context.l;
    final result = <int, DayHours?>{};
    for (final entry in _days.entries) {
      final day = entry.value;
      switch (day.mode) {
        case _DayMode.inherit:
          break;
        case _DayMode.closed:
          result[entry.key] = null;
        case _DayMode.open:
          if (day.open >= day.close) {
            setState(() => _error = '${weekdayName(context.lang, entry.key)}: ${l.errInvalidHours}');
            return;
          }
          result[entry.key] = DayHours(day.open, day.close);
      }
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: AppText.title),
            const SizedBox(height: 10),
            for (var d = 1; d <= 7; d++) _row(d),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: manrope(14, 600, color: AppColors.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: Text(l.saveLabel)),
          ],
        ),
      ),
    );
  }

  Widget _row(int weekday) {
    final l = context.l;
    final day = _days[weekday]!;
    final inheritedText = hoursText(l, widget.inherited?[weekday]);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(weekdayName(context.lang, weekday), style: manrope(15.5, 700))),
              if (_forCourt)
                DropdownButton<_DayMode>(
                  key: ValueKey('hours-mode-$weekday'),
                  value: day.mode,
                  underline: const SizedBox.shrink(),
                  style: manrope(14, 700),
                  items: [
                    DropdownMenuItem(value: _DayMode.inherit, child: Text(l.sameAsVenue)),
                    DropdownMenuItem(value: _DayMode.open, child: Text(l.openLabel)),
                    DropdownMenuItem(value: _DayMode.closed, child: Text(l.closed)),
                  ],
                  onChanged: (mode) => setState(() {
                    day.mode = mode!;
                    _error = null;
                  }),
                )
              else ...[
                Text(day.mode == _DayMode.open ? l.openLabel : l.closed, style: AppText.muted),
                const SizedBox(width: 8),
                Switch(
                  key: ValueKey('hours-open-$weekday'),
                  value: day.mode == _DayMode.open,
                  onChanged: (open) => setState(() {
                    day.mode = open ? _DayMode.open : _DayMode.closed;
                    _error = null;
                  }),
                ),
              ],
            ],
          ),
          if (day.mode == _DayMode.open)
            Row(
              children: [
                Expanded(
                  child: _TimeDropdown(
                    key: ValueKey('hours-from-$weekday'),
                    value: day.open,
                    onChanged: (v) => setState(() {
                      day.open = v;
                      _error = null;
                    }),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('–')),
                Expanded(
                  child: _TimeDropdown(
                    key: ValueKey('hours-to-$weekday'),
                    value: day.close,
                    onChanged: (v) => setState(() {
                      day.close = v;
                      _error = null;
                    }),
                  ),
                ),
              ],
            )
          else if (day.mode == _DayMode.inherit)
            Text(inheritedText, style: AppText.muted),
          const Divider(height: 18),
        ],
      ),
    );
  }
}

/// A time of day in half-hour steps.
class _TimeDropdown extends StatelessWidget {
  const _TimeDropdown({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => TimeDropdown(value: value, onChanged: onChanged);
}

/// A time of day in half-hour steps; shared with the price rule editor.
class TimeDropdown extends StatelessWidget {
  const TimeDropdown({super.key, required this.value, required this.onChanged, this.label});

  final int value;
  final ValueChanged<int> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    // Hours saved outside the half-hour grid still show up as an option.
    final options = kHalfHours.contains(value) ? kHalfHours : ([...kHalfHours, value]..sort());
    return DropdownButtonFormField<int>(
      value: value,
      isDense: true,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      style: manrope(15, 700),
      items: [for (final m in options) DropdownMenuItem(value: m, child: Text(minutesHm(m)))],
      onChanged: (v) => onChanged(v!),
    );
  }
}
