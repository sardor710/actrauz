import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/social.dart';
import '../../domain/community.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../state/ui_providers.dart';
import '../common/app_header.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// Teams in the city and players to meet. Joining a team and inviting players
/// arrive in a later milestone.
class SocialScreen extends ConsumerWidget {
  const SocialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const AppHeader(),
            const SizedBox(height: 4),
            AsyncBody(
              value: ref.watch(teamsProvider),
              builder: (teams) => SectionCard(
                title: l.discoverTeams,
                contentPadding: const EdgeInsets.only(bottom: 16),
                child: teams.isEmpty
                    ? EmptyState(icon: Icons.groups_outlined, text: l.noTeams)
                    : SizedBox(
                        height: 186,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          itemCount: teams.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (context, i) => _TeamTile(team: teams[i]),
                        ),
                      ),
              ),
            ),
            AsyncBody(
              value: ref.watch(playersProvider(kAllPlayers)),
              builder: (players) => SectionCard(
                title: l.playersNearYou,
                contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  children: [
                    for (var i = 0; i < players.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _PlayerRow(player: players[i], sports: sports),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_add_alt_1_rounded),
                          const SizedBox(width: 10),
                          Expanded(child: Text(l.inviteTitle.toUpperCase(), style: AppText.sectionTitle)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(l.inviteText, style: AppText.muted.copyWith(fontSize: 14.5)),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => showMessage(context, l.comingSoon),
                          child: Text(l.inviteCta.toUpperCase()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({required this.team});

  final Team team;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final tint = tintFor(team.name);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showMessage(context, l.comingSoon),
      child: SizedBox(
        width: 112,
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint.background, shape: BoxShape.circle),
              child: SportBadge(sportId: team.sportId, size: 50),
            ),
            const SizedBox(height: 8),
            Text(
              team.name,
              style: manrope(13.5, 700, height: 1.2),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(l.members(team.memberCount), style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (team.upcomingGames > 0) ...[
              const SizedBox(height: 5),
              Pill(text: l.upcomingGames(team.upcomingGames), color: AppColors.blue, onColor: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.sports});

  final PlayerProfile player;
  final List<Sport> sports;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    String sportName(String id) => sports.where((s) => s.id == id).firstOrNull?.name.resolve(context.lang) ?? id;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          InitialAvatar(name: player.name, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player.name, style: manrope(15.5, 700)),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final entry in player.levels.entries)
                      Pill(text: '${sportName(entry.key)} · ${l.level(entry.value)}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
