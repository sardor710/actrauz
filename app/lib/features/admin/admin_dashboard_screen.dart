import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/tournaments.dart';
import '../../state/admin_providers.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../tournaments/tournament_tools.dart';
import 'admin_common.dart';

enum _Period { today, week, month, custom }

/// Users, revenue and activity across the app (product spec §12.5): filter by
/// city, pick a period. Revenue is one row per currency and is never added up
/// across currencies.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      AdminScaffold(title: context.l.adminDashboard, fallback: '/admin', body: (_) => const _Dashboard());
}

class _Dashboard extends ConsumerStatefulWidget {
  const _Dashboard();

  @override
  ConsumerState<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<_Dashboard> {
  /// `null` = every city.
  String? _cityId;
  _Period _period = _Period.today;
  DateTimeRange? _custom;

  DateTime _today() {
    final city = _cityId == null ? ref.read(currentCityProvider) : cityById(_cityId!);
    return dateOnly(venueNow(city, utcNow: ref.read(clockProvider)()));
  }

  (DateTime, DateTime) _range() {
    final today = _today();
    return switch (_period) {
      _Period.today => (today, today),
      _Period.week => (today.subtract(const Duration(days: 6)), today),
      _Period.month => (DateTime.utc(today.year, today.month), today),
      _Period.custom => (dateOnly(_custom?.start ?? today), dateOnly(_custom?.end ?? today)),
    };
  }

  Future<void> _pickCity() async {
    final l = context.l;
    final picked = await showOptionSheet(
      context,
      title: l.city,
      options: {'': l.allCities, for (final c in kCities) c.id: c.name.resolve(context.lang)},
      current: _cityId ?? '',
    );
    if (picked != null) setState(() => _cityId = picked.isEmpty ? null : picked);
  }

  Future<void> _pickCustom() async {
    final today = _today();
    final (from, to) = _range();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today,
      initialDateRange: DateTimeRange(start: from, end: to),
    );
    if (picked != null) {
      setState(() {
        _custom = picked;
        _period = _Period.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final lang = context.lang;
    final (from, to) = _range();
    final now = _today();
    final data = ref.watch(adminDashboardProvider((cityId: _cityId, from: from, to: to)));

    String periodLabel(_Period p) => switch (p) {
      _Period.today => l.today,
      _Period.week => l.period7,
      _Period.month => l.periodMonth,
      _Period.custom => _period == _Period.custom ? datesText(l, lang, from, to, now) : l.periodCustom,
    };

    return AdminListView(
      bottom: 24,
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              FilterChipButton(
                key: const ValueKey('dash-city'),
                icon: Icons.place_outlined,
                label: _cityId == null ? l.allCities : cityById(_cityId!).name.resolve(lang),
                selected: _cityId != null,
                dropdown: true,
                onTap: _pickCity,
              ),
              for (final period in _Period.values)
                FilterChipButton(
                  key: ValueKey('dash-period-${period.name}'),
                  icon: period == _Period.custom ? Icons.date_range_outlined : null,
                  label: periodLabel(period),
                  selected: _period == period,
                  onTap: period == _Period.custom ? _pickCustom : () => setState(() => _period = period),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // A reload keeps the numbers on screen.
        if (data.valueOrNull == null)
          AsyncBody(value: data, builder: (_) => const SizedBox.shrink())
        else
          _Metrics(data: data.requireValue),
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.data});

  final AdminDashboard data;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final users = [
      _Tile(key: const ValueKey('stat-users-total'), icon: Icons.groups_outlined, label: l.usersTotal, value: '${data.users.total}', accent: true),
      _Tile(key: const ValueKey('stat-users-active'), icon: Icons.bolt_outlined, label: l.usersActive, value: '${data.users.active30d}'),
      _Tile(key: const ValueKey('stat-users-today'), icon: Icons.person_add_alt_outlined, label: l.usersNewToday, value: '${data.users.newToday}'),
      _Tile(key: const ValueKey('stat-users-7d'), icon: Icons.person_add_alt_outlined, label: l.usersNew7, value: '${data.users.new7d}'),
      _Tile(key: const ValueKey('stat-users-month'), icon: Icons.person_add_alt_outlined, label: l.usersNewMonth, value: '${data.users.newMonth}'),
    ];
    final counts = [
      _Tile(
        key: const ValueKey('count-bookings'),
        icon: Icons.event_available_outlined,
        label: l.countBookings,
        note: l.countBookingsNote,
        value: '${data.counts.bookings}',
      ),
      _Tile(key: const ValueKey('count-games'), icon: Icons.sports_tennis_rounded, label: l.countGames, value: '${data.counts.games}'),
      _Tile(
        key: const ValueKey('count-registrations'),
        icon: Icons.emoji_events_outlined,
        label: l.countRegistrations,
        value: '${data.counts.registrations}',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(title: l.usersTitle, tiles: users),
        SectionCard(title: l.revenueTitle, child: _RevenueTable(rows: data.revenue)),
        _Section(title: l.activityTitle, tiles: counts),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.tiles});

  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text(title.toUpperCase(), style: AppText.sectionTitle),
        ),
        LayoutBuilder(
          builder: (context, box) {
            // Two per row on a phone, three on a wide screen.
            final perRow = box.maxWidth >= 600 ? 3 : 2;
            final width = (box.maxWidth - 12 * (perRow - 1)) / perRow;
            return Wrap(spacing: 12, runSpacing: 12, children: [for (final t in tiles) SizedBox(width: width, child: t)]);
          },
        ),
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.icon, required this.label, required this.value, this.note, this.accent = false});

  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final bool accent;

  @override
  Widget build(BuildContext context) => Card(
    color: accent ? AppColors.primarySoft : null,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primaryDark),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: AppText.muted, maxLines: 2, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: manrope(24, 800)),
          if (note != null) Text(note!, style: AppText.caption),
        ],
      ),
    ),
  );
}

/// One row per currency: venue bookings and tournament entry fees, side by
/// side. There is no total row and no total column.
class _RevenueTable extends StatelessWidget {
  const _RevenueTable({required this.rows});

  final List<CurrencyRevenue> rows;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    Widget line(Key? key, List<Widget> cells) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 2, child: cells[0]),
          Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: cells[1])),
          Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: cells[2])),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line(null, [
          Text(l.revenueCurrency, style: AppText.caption),
          Text(l.revenueVenues, style: AppText.caption),
          Text(l.revenueTournaments, style: AppText.caption),
        ]),
        const Divider(height: 1),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(l.noRevenue, style: AppText.muted))
        else
          for (final row in rows)
            line(ValueKey('revenue-${row.currency.name.toUpperCase()}'), [
              Text(row.currency.name.toUpperCase(), style: AppText.bodyStrong),
              Text(groupThousands(row.venues), style: AppText.bodyStrong),
              Text(groupThousands(row.tournaments), style: AppText.bodyStrong),
            ]),
        const SizedBox(height: 8),
        Text(l.revenueNote, style: AppText.caption),
      ],
    );
  }
}
