import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/sample/sample_data.dart';
import '../../domain/community.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../state/ui_providers.dart';
import '../common/formatters.dart';
import '../common/reliability_badge.dart';
import '../common/widgets.dart';
import 'convert_request_sheet.dart';
import 'host_tools.dart';

/// A Game Request: the window and area, who is in, and what the signed-in
/// player can do about it ("I'm in" / "Leave") or, for the poster, remove
/// players, cancel it or turn it into a game.
class GameRequestScreen extends ConsumerWidget {
  const GameRequestScreen({super.key, required this.requestId});

  final String requestId;

  void _back(BuildContext context) => context.canPop() ? context.pop() : context.go('/games');

  /// Leaves for the Requests list, the way back after cancelling.
  void _toList(BuildContext context, WidgetRef ref) {
    ref.read(gamesTabProvider.notifier).state = 1;
    context.go('/games');
  }

  Future<void> _in(BuildContext context, WidgetRef ref) =>
      runGameAction(context, ref, () => ref.read(gameRepositoryProvider).imIn(requestId));

  Future<void> _leave(BuildContext context, WidgetRef ref) =>
      runGameAction(context, ref, () => ref.read(gameRepositoryProvider).withdrawInterest(requestId));

  Future<void> _remove(BuildContext context, WidgetRef ref, GameMember member) async {
    final l = context.l;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.removePlayerTitle(playerName(l, member.name, deleted: member.deleted))),
        content: Text(l.removeInterestedMsg),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.removeLabel)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runGameAction(context, ref, () => ref.read(gameRepositoryProvider).removeInterested(requestId, member.id));
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.cancelRequestTitle),
        content: Text(l.cancelRequestMsg),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.keepRequest)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.cancelRequestLabel),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final done = await runGameAction(context, ref, () => ref.read(gameRepositoryProvider).cancelRequest(requestId));
    if (!done || !context.mounted) return;
    showMessage(context, l.requestCancelledMsg);
    _toList(context, ref);
  }

  Future<void> _convert(BuildContext context, GameRequest request) async {
    final game = await showConvertRequestSheet(context, request);
    // A game lives in the Games tab: go, not push, so the stack is Games then the game.
    if (game != null && context.mounted) context.go('/games/${game.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => _back(context)),
        title: Text(l.createRequestTitle),
      ),
      body: AsyncBody(
        value: ref.watch(gameRequestProvider(requestId)),
        builder: (request) {
          final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
          final sport = sports.where((s) => s.id == request.sportId).firstOrNull;
          final venueId = request.venueId;
          final venue = venueId == null ? null : ref.watch(venueProvider(venueId)).valueOrNull;
          final now = ref.watch(cityNowProvider)();
          // Open, and its window has not ended.
          final active = request.isOpen && request.end.isAfter(now);
          final converted = request.status == GameRequestStatus.converted && request.gameId != null;
          final where = [
            if (venue != null) venue.name.resolve(context.lang),
            if (request.area != null) request.area!,
          ].join(' · ');

          final Widget? bar;
          if (!active) {
            bar = converted
                ? FilledButton(onPressed: () => context.go('/games/${request.gameId}'), child: Text(l.openGameCta))
                : null;
          } else if (request.isMine) {
            bar = Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                    onPressed: () => _cancel(context, ref),
                    child: Text(l.cancelRequestLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('convert-open'),
                    onPressed: () => _convert(context, request),
                    child: Text(l.makeItAGame),
                  ),
                ),
              ],
            );
          } else if (request.imIn) {
            bar = OutlinedButton(onPressed: () => _leave(context, ref), child: Text(l.leaveRequest));
          } else {
            bar = FilledButton(onPressed: () => _in(context, ref), child: Text(l.imIn));
          }

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  children: [
                    if (converted)
                      _Banner(icon: Icons.check_circle_outline_rounded, text: l.requestConvertedBanner)
                    else if (!active)
                      _Banner(icon: Icons.event_busy_outlined, text: l.requestClosedBanner, error: true),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SportBadge(sportId: request.sportId, size: 36),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      l.requestTitle(
                                        playerName(l, request.hostName, deleted: request.hostDeleted),
                                        sport?.name.resolve(context.lang) ?? '',
                                      ),
                                      style: manrope(19, 800, height: 1.2),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Pill(
                                text:
                                    '${dayLabel(l, context.lang, request.start, now)} · ${timeRange(request.start, request.end)}',
                                color: AppColors.blue,
                                onColor: Colors.white,
                                large: true,
                              ),
                              if (where.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    const Icon(Icons.place_outlined, color: AppColors.muted),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(where, style: manrope(16, 700))),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Pill(
                                    text: l.interestedOf(request.interestedCount, request.playersNeeded),
                                    color: AppColors.amber,
                                    onColor: AppColors.ink,
                                  ),
                                  Pill(
                                    text: l.levelRange(request.minLevel, request.maxLevel),
                                    icon: Icons.bar_chart_rounded,
                                    color: AppColors.primarySoft,
                                    onColor: AppColors.primaryDark,
                                  ),
                                ],
                              ),
                              if (request.note != null) ...[
                                const SizedBox(height: 14),
                                Text(request.note!, style: AppText.body),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    SectionCard(
                      title: '${l.interestedPlayers} · ${request.interestedCount}',
                      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: request.interested.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(l.noInterestedYet, style: AppText.muted.copyWith(fontSize: 15)),
                            )
                          : Column(
                              children: [
                                for (final member in request.interested)
                                  _MemberTile(
                                    member: member,
                                    onRemove: request.isMine && active ? () => _remove(context, ref, member) : null,
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              if (bar != null)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.card,
                    border: Border(top: BorderSide(color: AppColors.line)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: SizedBox(width: double.infinity, child: bar),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.error = false});

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: error ? AppColors.errorSoft : AppColors.primarySoft,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(icon, color: error ? AppColors.error : AppColors.primaryDark),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: manrope(14.5, 700, color: error ? AppColors.error : AppColors.primaryDark)),
        ),
      ],
    ),
  );
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, this.onRemove});

  final GameMember member;

  /// Set for the poster.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final isMe = member.id == kMeId;
    final name = isMe ? l.you : playerName(l, member.name, deleted: member.deleted);
    return InkWell(
      onTap: isMe ? null : () => context.push('/players/${member.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            InitialAvatar(name: name, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: manrope(15.5, 700)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Pill(
                        text: l.level(member.level),
                        icon: Icons.bar_chart_rounded,
                        color: AppColors.primarySoft,
                        onColor: AppColors.primaryDark,
                      ),
                      ReliabilityPill(reliability: member.reliability),
                    ],
                  ),
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: l.removePlayer,
                onPressed: onRemove,
                icon: const Icon(Icons.person_remove_outlined, color: AppColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}
