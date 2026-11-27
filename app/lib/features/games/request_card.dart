import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/community.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/rating_pill.dart';
import '../common/widgets.dart';

/// One Game Request: the window, who wants to play what, how many are in.
class GameRequestCard extends ConsumerWidget {
  const GameRequestCard({super.key, required this.request, this.compact = false});

  final GameRequest request;

  /// For the fixed-height strip on the home tab.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final sport = sports.where((s) => s.id == request.sportId).firstOrNull;
    final now = ref.watch(cityNowProvider)();
    final where = request.area ?? '';

    return Card(
      child: InkWell(
        onTap: () => context.go('/games/requests/${request.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Pill(
                        text:
                            '${dayLabel(l, context.lang, request.start, now)} · ${timeRange(request.start, request.end)}',
                        color: AppColors.blue,
                        onColor: Colors.white,
                        large: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SportBadge(sportId: request.sportId, size: 30),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  AvatarStack(
                    names: [for (final m in request.interested) playerName(l, m.name, deleted: m.deleted)],
                    deleted: [for (final m in request.interested) m.deleted],
                  ),
                  if (request.interested.isNotEmpty) const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.interestedOf(request.interestedCount, request.playersNeeded),
                      style: manrope(15, 600, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l.requestTitle(
                  playerName(l, request.hostName, deleted: request.hostDeleted),
                  sport?.name.resolve(context.lang) ?? '',
                ),
                style: AppText.cardTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 18, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(where, style: AppText.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Pill(
                    text: gameRangeText(
                      l,
                      minLevel: request.minLevel,
                      maxLevel: request.maxLevel,
                      minRating: request.minRating,
                      maxRating: request.maxRating,
                    ),
                    icon: Icons.bar_chart_rounded,
                    color: AppColors.primarySoft,
                    onColor: AppColors.primaryDark,
                  ),
                ],
              ),
              if (!compact && (request.isMine || request.imIn)) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (request.isMine)
                      Pill(text: l.host, color: AppColors.primarySoft, onColor: AppColors.primaryDark)
                    else
                      Pill(text: l.imIn, color: AppColors.amber, onColor: AppColors.ink),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
