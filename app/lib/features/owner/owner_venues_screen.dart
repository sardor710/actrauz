import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/sample/sample_media.dart';
import '../../state/owner_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// The venues this person manages. Opens the calendar of the one they pick.
class OwnerVenuesScreen extends ConsumerWidget {
  const OwnerVenuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text(l.myVenues),
      ),
      body: AsyncBody(
        value: ref.watch(myVenuesProvider),
        builder: (venues) => venues.isEmpty
            ? Center(
                child: EmptyState(icon: Icons.stadium_outlined, text: l.noVenuesAssigned),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: venues.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final venue = venues[i];
                  return Card(
                    child: InkWell(
                      onTap: () => context.push('/owner/${venue.id}'),
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
                                  const SizedBox(height: 3),
                                  Text(
                                    '${venue.district.resolve(context.lang)} · ${l.courts}: ${venue.courts.length}',
                                    style: AppText.muted,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Pill(
                                    text: l.ownerCalendar,
                                    icon: Icons.calendar_month_outlined,
                                    color: AppColors.primarySoft,
                                    onColor: AppColors.primaryDark,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
