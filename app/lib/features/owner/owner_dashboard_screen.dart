import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/owner.dart';
import '../../state/owner_providers.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'hours_editor.dart';

enum _Period { today, week, month }

/// Bookings, revenue and peak hours for one venue (product spec §11.1).
class OwnerDashboardScreen extends ConsumerStatefulWidget {
  const OwnerDashboardScreen({super.key, required this.venueId});

  final String venueId;

  @override
  ConsumerState<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends ConsumerState<OwnerDashboardScreen> {
  _Period _period = _Period.today;
  String? _courtId;

  @override
  Widget build(BuildContext context) {
    final l = context.l;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/owner/${widget.venueId}'),
        ),
        title: Text(l.ownerDashboard),
      ),
      body: AsyncBody(
        value: ref.watch(myVenuesProvider),
        builder: (venues) {
          final venue = venues.where((v) => v.id == widget.venueId).firstOrNull;
          if (venue == null) {
            return Center(child: EmptyState(icon: Icons.lock_outline_rounded, text: l.errNotAllowed));
          }
          final today = dateOnly(venueNow(cityById(venue.cityId), utcNow: ref.watch(clockProvider)()));
          final from = switch (_period) {
            _Period.today => today,
            _Period.week => today.subtract(const Duration(days: 6)),
            _Period.month => DateTime.utc(today.year, today.month),
          };
          final dashboard = ref.watch(
            ownerDashboardProvider((venueId: venue.id, courtId: _courtId, from: from, to: today)),
          );

          return ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(venue.name.resolve(context.lang), style: AppText.title),
              ),
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  children: [
                    for (final (period, label) in [
                      (_Period.today, l.today),
                      (_Period.week, l.period7),
                      (_Period.month, l.periodMonth),
                    ])
                      FilterChipButton(
                        label: label,
                        selected: _period == period,
                        onTap: () => setState(() => _period = period),
                      ),
                  ],
                ),
              ),
              if (venue.courts.length > 1)
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    children: [
                      FilterChipButton(
                        label: l.allCourts,
                        selected: _courtId == null,
                        onTap: () => setState(() => _courtId = null),
                      ),
                      for (final court in venue.courts)
                        FilterChipButton(
                          label: court.name.resolve(context.lang),
                          selected: _courtId == court.id,
                          onTap: () => setState(() => _courtId = court.id),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              AsyncBody(value: dashboard, builder: (data) => _Metrics(data: data)),
            ],
          );
        },
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.data});

  final OwnerDashboard data;

  static String _percent(double value) => '${(value * 100).round()}%';

  static String _average(double value) => value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final tiles = [
      _Tile(
        icon: Icons.event_available_outlined,
        label: l.statBookings,
        value: '${data.bookings}',
        note: l.metricSplit(data.bookingsApp, data.bookingsWalkIn),
        key: const ValueKey('metric-bookings'),
      ),
      _Tile(
        icon: Icons.payments_outlined,
        label: l.metricRevenue,
        value: money(l, data.revenuePaid, data.currency),
        accent: true,
        key: const ValueKey('metric-revenue'),
      ),
      _Tile(
        icon: Icons.hourglass_bottom_rounded,
        label: l.metricUnconfirmed,
        value: money(l, data.revenueUnconfirmed, data.currency),
      ),
      _Tile(icon: Icons.show_chart_rounded, label: l.metricDailyAvg, value: _average(data.dailyAverage)),
      _Tile(
        icon: Icons.donut_large_rounded,
        label: l.metricUtilisation,
        value: _percent(data.utilisation),
        note: '${data.slotsBooked}/${data.slotsAvailable}',
      ),
      _Tile(
        icon: Icons.person_off_outlined,
        label: l.metricNoShows,
        value: '${data.noShows}',
        note: _percent(data.noShowRate),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              // Two per row on a phone, three on a wide screen.
              final perRow = box.maxWidth >= 720 ? 3 : 2;
              final width = (box.maxWidth - 12 * (perRow - 1)) / perRow;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final tile in tiles) SizedBox(width: width, child: tile)],
              );
            },
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.peakHours.toUpperCase(), style: AppText.sectionTitle),
                  const SizedBox(height: 14),
                  if (data.heatmap.isEmpty)
                    Center(child: EmptyState(icon: Icons.insights_outlined, text: l.noDataPeriod))
                  else
                    _Heatmap(heatmap: data.heatmap),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    color: accent ? AppColors.primarySoft : AppColors.card,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: accent ? AppColors.primaryDark : AppColors.muted),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: manrope(22, 800, color: accent ? AppColors.primaryDark : AppColors.ink)),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
          // One line reserved, so tiles in a row keep the same height.
          SizedBox(
            height: 20,
            child: note == null
                ? null
                : Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      note!,
                      style: manrope(12, 700, color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

/// Bookings by weekday (rows) and start hour (columns); darker = busier.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.heatmap});

  final Map<({int weekday, int hour}), int> heatmap;

  @override
  Widget build(BuildContext context) {
    final hours = heatmap.keys.map((k) => k.hour);
    final first = hours.reduce((a, b) => a < b ? a : b);
    final last = hours.reduce((a, b) => a > b ? a : b);
    final peak = heatmap.values.reduce((a, b) => a > b ? a : b);
    const cell = 30.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 44),
              for (var h = first; h <= last; h++)
                SizedBox(
                  width: cell,
                  child: Text('$h', textAlign: TextAlign.center, style: manrope(11, 700, color: AppColors.muted)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var d = 1; d <= 7; d++)
            Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(weekdayShortName(context.lang, d), style: manrope(12, 700, color: AppColors.muted)),
                ),
                for (var h = first; h <= last; h++)
                  Builder(
                    builder: (context) {
                      final count = heatmap[(weekday: d, hour: h)] ?? 0;
                      return Container(
                        width: cell - 4,
                        height: cell - 4,
                        margin: const EdgeInsets.all(2),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: count == 0
                              ? AppColors.page
                              : Color.lerp(AppColors.primarySoft, AppColors.primaryDark, count / peak),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: count == 0
                            ? null
                            : Text(
                                '$count',
                                style: manrope(11, 800, color: count / peak > 0.5 ? Colors.white : AppColors.primaryDark),
                              ),
                      );
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
