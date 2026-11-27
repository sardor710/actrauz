import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/admin_providers.dart';
import '../common/formatters.dart';
import 'admin_common.dart';

/// The admin's start page (product spec §12): venues, sports, banners and
/// the audit log.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      AdminScaffold(title: context.l.adminTitle, fallback: '/profile', body: (_) => const _Sections());
}

class _Sections extends ConsumerWidget {
  const _Sections();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final venues = ref.watch(adminVenuesProvider).valueOrNull;
    final sports = ref.watch(adminSportsProvider).valueOrNull;
    final banners = ref.watch(adminBannersProvider).valueOrNull;
    final review = ref.watch(adminReviewProvider).valueOrNull;

    final entries = [
      _Entry('admin-venues', Icons.stadium_outlined, l.tabVenues, venues == null ? null : l.venuesCount(venues.length), '/admin/venues'),
      _Entry('admin-sports', Icons.sports_tennis_rounded, l.adminSports, sports == null ? null : l.sportsCount(sports.length), '/admin/sports'),
      _Entry('admin-banners', Icons.view_carousel_outlined, l.adminBanners, banners == null ? null : l.bannersCount(banners.length), '/admin/banners'),
      _Entry('admin-tournaments', Icons.emoji_events_outlined, l.adminTournaments, l.adminTournamentsHint, '/admin/tournaments'),
      _Entry('admin-review', Icons.fact_check_outlined, l.adminReview, review == null ? null : l.adminReviewOpen(review.openCount), '/admin/review'),
      _Entry('admin-dashboard', Icons.insights_outlined, l.adminDashboard, l.adminDashboardHint, '/admin/dashboard'),
      _Entry('admin-audit', Icons.history_rounded, l.adminAudit, l.adminAuditHint, '/admin/audit'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = adminGutter(constraints.maxWidth);
        final inner = constraints.maxWidth - side * 2;
        // Two cards per row once there is room for them.
        final columns = inner >= 600 ? 2 : 1;
        const gap = 12.0;
        final width = (inner - gap * (columns - 1)) / columns;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(side, 4, side, 24),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final e in entries) SizedBox(width: width, child: _EntryCard(entry: e))],
          ),
        );
      },
    );
  }
}

class _Entry {
  const _Entry(this.key, this.icon, this.title, this.subtitle, this.route);

  final String key;
  final IconData icon;
  final String title;

  /// A count, or null while it loads.
  final String? subtitle;
  final String route;
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      key: ValueKey(entry.key),
      onTap: () => context.push(entry.route),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
              child: Icon(entry.icon, color: AppColors.primaryDark, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title, style: AppText.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(entry.subtitle ?? ' ', style: AppText.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
          ],
        ),
      ),
    ),
  );
}
