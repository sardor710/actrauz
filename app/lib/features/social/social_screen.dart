import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/teams.dart';
import '../../domain/community.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../state/ui_providers.dart';
import '../common/app_header.dart';
import '../../domain/competitive.dart';
import '../common/formatters.dart';
import '../common/rating_pill.dart';
import '../common/reliability_badge.dart';
import '../common/widgets.dart';
import '../games/game_pickers.dart';
import 'team_screen.dart' show TeamAvatar;

/// The player's teams and the city's others, leaderboards, and players to
/// meet: search by name, sport and level.
class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({super.key});

  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen> {
  final _query = TextEditingController();
  String? _sportId;
  RangeValues _levels = const RangeValues(1, 5);

  /// Used instead of [_levels] when the sport is rated (padel, tennis).
  RangeValues _ratings = kAllRatings;

  /// Teams in the city of every sport, not only the player's own.
  bool _showAllTeams = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _pickSport(List<Sport> sports) async {
    final l = context.l;
    final picked = await showOptionSheet(
      context,
      title: l.filterSport,
      options: {'': l.allSports, for (final s in sports) s.id: s.name.resolve(context.lang)},
      current: _sportId ?? '',
    );
    if (picked != null) {
      setState(() {
        _sportId = picked.isEmpty ? null : picked;
        _levels = const RangeValues(1, 5);
        _ratings = kAllRatings;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final sport = sports.where((s) => s.id == _sportId).firstOrNull;
    final sportName = sport?.name.resolve(context.lang);
    final rated = sport?.competitiveRating ?? false;
    final text = _query.text.trim();
    final search = (
      sportId: _sportId,
      minLevel: _levels.start.round(),
      maxLevel: _levels.end.round(),
      minRating: rated ? _ratings.start : null,
      maxRating: rated ? _ratings.end : null,
      query: text.isEmpty ? null : text,
    );

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
              builder: (teams) => _TeamSections(
                teams: teams,
                showAll: _showAllTeams,
                onToggle: () => setState(() => _showAllTeams = !_showAllTeams),
              ),
            ),
            if (sports.where((s) => s.competitiveRating).toList() case final ratedSports when ratedSports.isNotEmpty)
              SectionCard(
                title: l.leaderboards,
                contentPadding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    for (final s in ratedSports)
                      ListTile(
                        key: ValueKey('leaderboard-link-${s.id}'),
                        leading: SportBadge(sportId: s.id, size: 34),
                        title: Text(s.name.resolve(context.lang), style: manrope(15.5, 700)),
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
                        onTap: () => context.push('/leaderboard/${s.id}'),
                      ),
                  ],
                ),
              ),
            SectionCard(
              title: l.findPlayers,
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const ValueKey('player-search'),
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l.searchPlayersHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        FilterChipButton(
                          key: const ValueKey('players-sport'),
                          label: sportName ?? l.filterSport,
                          selected: _sportId != null,
                          dropdown: true,
                          onTap: () => _pickSport(sports),
                        ),
                      ],
                    ),
                  ),
                  if (rated) ...[
                    Text(
                      l.ratingRangeValue(formatRatingRange(_ratings.start, _ratings.end)),
                      style: AppText.bodyStrong,
                    ),
                    RangeSlider(
                      key: const ValueKey('players-rating'),
                      values: _ratings,
                      min: RatingRules.min,
                      max: RatingRules.max,
                      divisions: ((RatingRules.max - RatingRules.min) * 2).round(),
                      labels: RangeLabels(formatRatingBound(_ratings.start), formatRatingBound(_ratings.end)),
                      onChanged: (v) => setState(() => _ratings = v),
                    ),
                  ] else if (_sportId != null) ...[
                    Text(l.levelRange(_levels.start.round(), _levels.end.round()), style: AppText.bodyStrong),
                    RangeSlider(
                      key: const ValueKey('players-level'),
                      values: _levels,
                      min: 1,
                      max: 5,
                      divisions: 4,
                      labels: RangeLabels('${_levels.start.round()}', '${_levels.end.round()}'),
                      onChanged: (v) => setState(() => _levels = v),
                    ),
                  ],
                  AsyncBody(
                    value: ref.watch(playersProvider(search)),
                    builder: (players) => players.isEmpty
                        ? EmptyState(icon: Icons.person_search_outlined, text: l.noPlayersFound)
                        : Column(
                            children: [
                              for (var i = 0; i < players.length; i++) ...[
                                if (i > 0) const Divider(height: 1),
                                _PlayerRow(player: players[i], sports: sports),
                              ],
                            ],
                          ),
                  ),
                ],
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

/// "My teams" (captain, member or invited, from any city) with "Create a
/// team", then "Teams · {city}": the city's other teams in the player's
/// sports, or all of them with "Show all" (and always all when the player
/// has picked no sports yet).
class _TeamSections extends ConsumerWidget {
  const _TeamSections({required this.teams, required this.showAll, required this.onToggle});

  final List<Team> teams;
  final bool showAll;
  final VoidCallback onToggle;

  static bool _mine(Team t) => t.isMember || t.myStatus == MyTeamStatus.invited;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final city = ref.watch(currentCityProvider);
    final mySports = {for (final m in ref.watch(mySportsProvider).valueOrNull ?? const <MySport>[]) m.sportId};
    final mine = teams.where(_mine).toList();
    final others = teams.where((t) => !_mine(t) && t.cityId == city.id).toList();
    final filtering = !showAll && mySports.isNotEmpty;
    final shown = filtering ? others.where((t) => mySports.contains(t.sportId)).toList() : others;

    return Column(
      children: [
        SectionCard(
          key: const ValueKey('my-teams'),
          title: l.myTeams,
          contentPadding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (mine.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(l.noMyTeams, style: AppText.muted.copyWith(fontSize: 15)),
                )
              else
                _TeamStrip(teams: mine),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  key: const ValueKey('teams-create'),
                  onPressed: () => context.push('/teams/new'),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l.createTeam),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          key: const ValueKey('city-teams'),
          title: l.teamsInCity(city.name.resolve(context.lang)),
          contentPadding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (shown.isEmpty)
                EmptyState(icon: Icons.groups_outlined, text: filtering ? l.noTeamsForMySports : l.noTeams)
              else
                _TeamStrip(teams: shown),
              // Offered only when the filter hides something, or to undo it.
              if (mySports.isNotEmpty && (showAll || shown.length < others.length))
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TextButton(
                      key: const ValueKey('teams-show-all'),
                      onPressed: onToggle,
                      child: Text(showAll ? l.showMySportsTeams : l.showAllTeams),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A row of team tiles that scrolls sideways.
class _TeamStrip extends StatelessWidget {
  const _TeamStrip({required this.teams});

  final List<Team> teams;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    // As tall as its tallest tile: no empty band under a short list.
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, team) in teams.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          _TeamTile(team: team),
        ],
      ],
    ),
  );
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({required this.team});

  final Team team;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return InkWell(
      key: ValueKey('team-tile-${team.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/teams/${team.id}'),
      child: SizedBox(
        width: 112,
        child: Column(
          children: [
            SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                children: [
                  TeamAvatar(name: team.name, colorSeed: team.colorSeed, size: 84),
                  Positioned(right: 0, bottom: 0, child: SportBadge(sportId: team.sportId, size: 32)),
                  // A pending invite to answer.
                  if (team.myStatus == MyTeamStatus.invited)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Badge(key: ValueKey('team-invite-dot-${team.id}'), smallSize: 12),
                    ),
                ],
              ),
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
    String levelText(String id, int level) => switch (sports.where((s) => s.id == id).firstOrNull) {
      final sport? => levelOrRating(context, sport, level: level, rating: player.ratings[id]),
      null => l.level(level),
    };

    return InkWell(
      onTap: () => context.push('/players/${player.id}'),
      child: Padding(
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
                      ReliabilityPill(reliability: player.reliability),
                      for (final entry in player.levels.entries)
                        Pill(text: '${sportName(entry.key)} · ${levelText(entry.key, entry.value)}'),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}
