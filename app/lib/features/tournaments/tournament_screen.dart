import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/tournaments.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'register_sheet.dart';
import 'registration_block.dart';
import 'tournament_tools.dart';

/// One tournament: when and where, the registration deadline, and its
/// categories with how full they are. Each category offers Register, or the
/// waitlist once it is full; the player's own entries show with what they can
/// do about them.
class TournamentScreen extends ConsumerWidget {
  const TournamentScreen({super.key, required this.tournamentId});

  final String tournamentId;

  void _back(BuildContext context) => context.canPop() ? context.pop() : context.go('/tournaments');

  Future<void> _register(
    BuildContext context,
    WidgetRef ref,
    Tournament tournament,
    TournamentCategory category, {
    required bool waitlist,
  }) async {
    final choice = await showRegisterSheet(context, tournament: tournament, category: category, waitlist: waitlist);
    if (choice == null || !context.mounted) return;
    final repo = ref.read(tournamentRepositoryProvider);
    await runTournamentAction(
      context,
      ref,
      () => waitlist
          ? repo.joinWaitlist(category.id, partnerId: choice.partnerId)
          : repo.register(category.id, partnerId: choice.partnerId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(tournamentProvider(tournamentId));
    return Scaffold(
      key: const ValueKey('tournament-detail'),
      appBar: value.hasValue ? null : AppBar(leading: BackButton(onPressed: () => _back(context))),
      body: value.when(
        skipLoadingOnReload: true,
        data: (tournament) => _body(context, ref, tournament),
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => EmptyState(icon: Icons.error_outline, text: tournamentErrorText(context.l, error)),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, Tournament t) {
    final l = context.l;
    final lang = context.lang;
    final now = tournamentNow(ref, t.cityId);
    final sport = ref.watch(sportsProvider).valueOrNull?.where((s) => s.id == t.sportId).firstOrNull;
    final description = t.description.resolve(lang);
    final deadline = '${dayLabel(l, lang, t.registrationDeadline, now)}, ${hm(t.registrationDeadline)}';

    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: manrope(15, 700))),
        ],
      ),
    );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TournamentCover(
          id: t.id,
          sportId: t.sportId,
          coverUrl: t.coverUrl,
          colorSeed: t.colorSeed,
          height: 240,
          radius: 0,
          darken: 0.45,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OverlayIconButton(icon: Icons.arrow_back_rounded, onTap: () => _back(context)),
                  const Spacer(),
                  if (sport != null)
                    Pill(
                      text: sport.name.resolve(lang),
                      color: AppColors.blue,
                      onColor: Colors.white,
                      large: true,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    t.title.resolve(lang),
                    style: manrope(23, 800, color: Colors.white, height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!t.registrationOpen) InfoBanner(icon: Icons.lock_clock_outlined, text: l.tournamentClosedBanner, error: true),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (t.venueName.resolve(lang).isNotEmpty) row(Icons.place_outlined, t.venueName.resolve(lang)),
                  row(Icons.event_outlined, tournamentDates(l, lang, t, now)),
                  row(Icons.schedule_rounded, l.tournamentDeadline(deadline)),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(description, style: AppText.body),
                  ],
                ],
              ),
            ),
          ),
        ),
        SectionCard(
          title: l.tournamentCategories,
          contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            children: [
              for (final (i, c) in t.categories.indexed) ...[
                if (i > 0) const Divider(height: 28),
                _CategoryTile(
                  tournament: t,
                  category: c,
                  onRegister: (waitlist) => _register(context, ref, t, c, waitlist: waitlist),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.tournament, required this.category, required this.onRegister});

  final Tournament tournament;
  final TournamentCategory category;

  /// Register (false) or join the waitlist (true).
  final void Function(bool waitlist) onRegister;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = category;
    final mine = tournament.myRegistrations.where((r) => r.categoryId == c.id).toList();
    final open = tournament.registrationOpen;
    // A full category is greyed unless the player is in it.
    final grey = c.full && mine.isEmpty;

    Widget? action;
    if (open && mine.isEmpty) {
      action = !c.full
          ? FilledButton(onPressed: () => onRegister(false), child: Text(l.registerLabel))
          : c.waitlistEnabled
          ? OutlinedButton(onPressed: () => onRegister(true), child: Text(l.joinWaitlist))
          : FilledButton(onPressed: null, child: Text(l.tournamentFull));
    }

    return Column(
      key: ValueKey('category-${c.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: grey ? 0.55 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name.resolve(context.lang), style: AppText.cardTitle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Pill(text: categoryKindLabel(l, c.kind)),
                  Pill(text: categoryGenderLabel(l, c.gender)),
                  Pill(
                    text: l.levelRange(c.minLevel, c.maxLevel),
                    icon: Icons.bar_chart_rounded,
                    color: AppColors.primarySoft,
                    onColor: AppColors.primaryDark,
                  ),
                  Pill(text: feeText(l, c.fee, tournament.currency), icon: Icons.payments_outlined),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: c.cap == 0 ? 0 : (c.filled / c.cap).clamp(0, 1).toDouble(),
                borderRadius: BorderRadius.circular(8),
                minHeight: 7,
                color: c.full ? AppColors.error : AppColors.primary,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: Text(l.filledOf(c.filled, c.cap), style: AppText.caption)),
                  if (c.waitlistCount > 0) Text(l.waitlistCount(c.waitlistCount), style: AppText.caption),
                ],
              ),
            ],
          ),
        ),
        for (final r in mine) ...[
          const SizedBox(height: 12),
          RegistrationBlock(registration: r, cityId: tournament.cityId, registrationOpen: open),
        ],
        if (action != null) ...[const SizedBox(height: 12), SizedBox(width: double.infinity, child: action)],
      ],
    );
  }
}
