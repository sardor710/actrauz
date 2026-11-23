import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../data/sample/sample_media.dart';
import '../../domain/admin.dart';
import '../../state/admin_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'admin_common.dart';

/// Every venue, active or not (product spec §12.2). Opens the editor.
class AdminVenuesScreen extends StatelessWidget {
  const AdminVenuesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      AdminScaffold(title: context.l.tabVenues, fallback: '/admin', body: (_) => const _VenueList());
}

class _VenueList extends ConsumerWidget {
  const _VenueList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return AsyncBody(
      value: ref.watch(adminVenuesProvider),
      builder: (venues) => AdminListView(
        bottom: 24,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('add-venue'),
              style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: () => context.push('/admin/venues/new'),
              icon: const Icon(Icons.add_rounded),
              label: Text(l.addVenue),
            ),
          ),
          const SizedBox(height: 12),
          if (venues.isEmpty) EmptyState(icon: Icons.stadium_outlined, text: l.noVenues),
          for (final venue in venues) ...[_VenueCard(admin: venue), const SizedBox(height: 12)],
        ],
      ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  const _VenueCard({required this.admin});

  final AdminVenue admin;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final venue = admin.venue;
    final city = kCities.where((c) => c.id == venue.cityId).firstOrNull;
    final place = [
      if (city != null) city.name.resolve(context.lang),
      if (venue.district.resolve(context.lang).isNotEmpty) venue.district.resolve(context.lang),
    ].join(' · ');

    return Card(
      child: InkWell(
        key: ValueKey('admin-venue-${venue.id}'),
        onTap: () => context.push('/admin/venues/${venue.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              PhotoBox(asset: venuePhoto(venue.id), width: 72, height: 72, radius: 14),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venue.name.resolve(context.lang),
                      style: AppText.cardTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(place, style: AppText.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      '${l.courtsCount(venue.courts.length)} · ${l.ownersCount(admin.owners.length)}',
                      style: AppText.muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!admin.active) ...[const SizedBox(height: 8), const InactivePill()],
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
}
