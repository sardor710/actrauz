import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/tournaments.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'registration_block.dart';
import 'tournament_tools.dart';

/// The player's entries in tournaments that have not ended, newest first,
/// with what each can do: cancel, answer a partner invite, claim an offered
/// spot.
class MyTournamentsScreen extends ConsumerWidget {
  const MyTournamentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text(l.tournamentsMine),
      ),
      body: ref
          .watch(myRegistrationsProvider)
          .when(
            skipLoadingOnReload: true,
            data: (entries) => entries.isEmpty
                ? EmptyState(icon: Icons.emoji_events_outlined, text: l.myTournamentsEmpty)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      for (final entry in entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _EntryCard(entry: entry),
                        ),
                    ],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => EmptyState(icon: Icons.error_outline, text: tournamentErrorText(l, error)),
          ),
    );
  }
}

class _EntryCard extends ConsumerWidget {
  const _EntryCard({required this.entry});

  final Registration entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final lang = context.lang;
    final summary = entry.tournament;
    // The deadline decides what the entry can still do; until the tournament
    // loads, nothing is offered.
    final open = ref.watch(tournamentProvider(entry.tournamentId)).valueOrNull?.registrationOpen ?? false;
    final cityId = summary?.cityId ?? ref.watch(currentCityProvider).id;
    final now = tournamentNow(ref, cityId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => context.go('/tournaments/${entry.tournamentId}'),
              child: Row(
                children: [
                  if (summary != null) ...[
                    TournamentCover(
                      id: summary.id,
                      sportId: summary.sportId,
                      coverUrl: summary.coverUrl,
                      colorSeed: summary.colorSeed,
                      width: 64,
                      height: 64,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary?.title.resolve(lang) ?? '',
                          style: AppText.cardTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(entry.categoryName.resolve(lang), style: AppText.bodyStrong),
                        if (summary != null) Text(datesText(l, lang, summary.start, summary.end, now), style: AppText.muted),
                        Text(feeText(l, entry.fee, entry.currency), style: AppText.muted),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
                ],
              ),
            ),
            const Divider(height: 24),
            RegistrationBlock(registration: entry, cityId: cityId, registrationOpen: open),
          ],
        ),
      ),
    );
  }
}
