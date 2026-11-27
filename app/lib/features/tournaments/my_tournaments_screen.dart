import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/brackets.dart';
import '../../domain/tournaments.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'bracket_view.dart';
import 'next_match_card.dart';
import 'registration_block.dart';
import 'tournament_tools.dart';

/// The player's next tournament match, their matches (M8a), and their entries
/// in tournaments that have not ended, newest first, with what each can do:
/// cancel, answer a partner invite, claim an offered spot.
///
/// Reloads on opening, on coming back to the app (app.dart) and by pulling
/// down; a failed reload keeps what was shown.
class MyTournamentsScreen extends ConsumerStatefulWidget {
  const MyTournamentsScreen({super.key});

  @override
  ConsumerState<MyTournamentsScreen> createState() => _MyTournamentsScreenState();
}

class _MyTournamentsScreenState extends ConsumerState<MyTournamentsScreen> {
  /// Previous data that belongs to another account until fresh data arrives
  /// (also when that load fails): the matches, and each tournament's bracket
  /// (for the names). Noted on every build, also while the list shows a
  /// spinner.
  final _matchesTracker = StaleTracker();
  final _bracketTrackers = <String, StaleTracker>{};

  @override
  void initState() {
    super.initState();
    // Opened again: organisers may have set times and scores meanwhile.
    final cached = [myRegistrationsProvider, myMatchesProvider].where(ref.exists).toList();
    if (cached.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final provider in cached) {
        ref.invalidate(provider);
      }
      // The names in the matches come from the brackets.
      ref.invalidate(bracketProvider);
    });
  }

  Future<void> _reload() {
    ref.invalidate(bracketProvider);
    return pullToReload(
      context,
      Future.wait([ref.refresh(myRegistrationsProvider.future), ref.refresh(myMatchesProvider.future)]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final matchesValue = ref.watch(myMatchesProvider);
    final matchesStale = _matchesTracker.update(matchesValue);
    final drawOf = <(String, String), CategoryDraw?>{};
    for (final m in matchesValue.valueOrNull ?? const <MyMatch>[]) {
      final bracketValue = ref.watch(bracketProvider(m.tournamentId));
      final stale = _bracketTrackers.putIfAbsent(m.tournamentId, StaleTracker.new).update(bracketValue);
      drawOf[(m.tournamentId, m.categoryId)] = stale ? null : bracketValue.valueOrNull?.draw(m.categoryId);
    }
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text(l.tournamentsMine),
      ),
      // A failed refresh keeps the list (the pull that failed says so); a
      // reload for another account never shows the previous one's.
      body: AsyncBody(
        value: ref.watch(myRegistrationsProvider),
        onRetry: () => ref.invalidate(myRegistrationsProvider),
        errorText: (error) => tournamentErrorText(l, error),
        builder: (entries) {
          final matches = (matchesStale ? null : matchesValue.valueOrNull) ?? const <MyMatch>[];
          final next = matches.where((m) => m.match.status != MatchStatus.done).firstOrNull;
          String? categoryName(String categoryId) =>
              entries.where((e) => e.categoryId == categoryId).firstOrNull?.categoryName.resolve(context.lang);
          String? cityOf(String tournamentId) =>
              entries.where((e) => e.tournamentId == tournamentId).firstOrNull?.tournament?.cityId;
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (entries.isEmpty && matches.isEmpty)
                  EmptyState(icon: Icons.emoji_events_outlined, text: l.myTournamentsEmpty),
                if (next != null) ...[
                  _MatchOf(
                    myMatch: next,
                    draw: drawOf[(next.tournamentId, next.categoryId)],
                    categoryName: categoryName(next.categoryId),
                    cityId: cityOf(next.tournamentId),
                    next: true,
                  ),
                  const SizedBox(height: 12),
                ],
                if (matches.isNotEmpty) ...[
                  Card(
                    key: const ValueKey('my-matches'),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.myMatchesTitle.toUpperCase(), style: AppText.sectionTitle),
                          const SizedBox(height: 12),
                          for (final m in matches)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _MatchOf(
                                myMatch: m,
                                draw: drawOf[(m.tournamentId, m.categoryId)],
                                categoryName: categoryName(m.categoryId),
                                cityId: cityOf(m.tournamentId),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EntryCard(entry: entry),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One of the player's matches, as the next-match card or a row of My
/// matches. The entries' names come from the tournament's bracket.
class _MatchOf extends ConsumerWidget {
  const _MatchOf({
    required this.myMatch,
    required this.draw,
    required this.categoryName,
    required this.cityId,
    this.next = false,
  });

  final MyMatch myMatch;

  /// From the tournament's bracket, for the names; null while there is none
  /// to show.
  final CategoryDraw? draw;
  final String? categoryName;

  /// The tournament's city, for its wall-clock; the current city without an
  /// entry listed.
  final String? cityId;
  final bool next;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = myMatch;
    final draw = this.draw ?? CategoryDraw(categoryId: m.categoryId, format: DrawFormat.knockout, published: true);
    final now = tournamentNow(ref, cityId ?? ref.watch(currentCityProvider).id);
    final title = [m.title.resolve(context.lang), ?categoryName].join(' · ');
    void open() => context.go('/tournaments/${m.tournamentId}');

    if (next) return NextMatchCard(match: m.match, draw: draw, now: now, subtitle: title, onTap: open);
    return InkWell(
      onTap: open,
      borderRadius: BorderRadius.circular(12),
      child: MatchCard(match: m.match, draw: draw, now: now, header: title),
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
    // The deadline decides what the entry can still do; my_registrations
    // says whether it has passed.
    final open = summary?.registrationOpen ?? false;
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
                        if (summary != null)
                          Text(datesText(l, lang, summary.start, summary.end, now), style: AppText.muted),
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
