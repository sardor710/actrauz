import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../data/sample/sample_data.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/teams.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/ui_providers.dart';
import '../admin/admin_common.dart' show confirmDelete;
import '../common/formatters.dart';
import '../common/rating_pill.dart';
import '../common/reliability_badge.dart';
import '../common/widgets.dart';
import '../games/game_card.dart';

/// Runs a team action on a screen and shows the translated reason when the
/// backend refuses. Every view of teams reloads either way: a refusal
/// usually means the team changed meanwhile. Returns whether it went
/// through; false at once while another team action runs (a double tap).
Future<bool> runTeamAction(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
  if (_teamActionRunning) return false;
  _teamActionRunning = true;
  final l = context.l;
  final String? error;
  try {
    error = await teamActionError(l, action);
  } finally {
    _teamActionRunning = false;
  }
  if (!context.mounted) return error == null;
  refreshTeams(ref);
  if (error != null) showMessage(context, error);
  return error == null;
}

/// Whether a [runTeamAction] is under way.
bool _teamActionRunning = false;

/// For a sheet or form, where a snackbar would be hidden: runs [action] and
/// returns the refusal's text, or null when it went through.
Future<String?> teamActionError(AppLocalizations l, Future<void> Function() action) async {
  try {
    await action();
    return null;
  } on JoinException catch (e) {
    return joinErrorText(l, e);
  }
}

/// The sport's name in the app language, or its id while the list loads.
String teamSportName(BuildContext context, List<Sport> sports, String sportId) =>
    sports.where((s) => s.id == sportId).firstOrNull?.name.resolve(context.lang) ?? sportId;

/// The city's name in the app language.
String teamCityName(BuildContext context, String cityId) =>
    kCities.where((c) => c.id == cityId).firstOrNull?.name.resolve(context.lang) ?? cityId;

/// A team's initials on the colour its seed picks.
class TeamAvatar extends StatelessWidget {
  const TeamAvatar({super.key, required this.name, required this.colorSeed, this.size = 44});

  final String name;
  final int colorSeed;
  final double size;

  /// The first letters of the first two words: "Night Owls" → "NO".
  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
    final letters = words.map((w) => w.characters.first.toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }

  @override
  Widget build(BuildContext context) {
    final tint = tintFor('$colorSeed');
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint.background, shape: BoxShape.circle),
      child: Text(initials(name), style: manrope(size * 0.36, 800, color: tint.foreground)),
    );
  }
}

/// "Level 3" in a simple sport; the rating, provisional or not, in a rated one.
String _levelText(AppLocalizations l, {required int level, double? rating, bool provisional = false}) {
  if (rating == null) return l.level(level);
  final value = formatRating(rating);
  return provisional ? l.ratingWithProvisional(value) : value;
}

/// A team (design §7): its upcoming games, who is in it, and the join, leave
/// and captain tools.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key, required this.teamId});

  final String teamId;

  void _back(BuildContext context) => context.canPop() ? context.pop() : context.go('/social');

  Future<void> _delete(BuildContext context, WidgetRef ref, Team team) async {
    if (!await confirmDelete(context, team.name) || !context.mounted) return;
    final error = await teamActionError(context.l, () => ref.read(socialRepositoryProvider).deleteTeam(team.id));
    if (!context.mounted) return;
    if (error != null) {
      refreshTeams(ref);
      showMessage(context, error);
      return;
    }
    // Leave first: the page would reload a team that is gone.
    _back(context);
    refreshTeams(ref);
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, Team team) async {
    final l = context.l;
    if (team.isCaptain) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _HandoverSheet(team: team),
      );
      if (!context.mounted) return;
      if (choice == _HandoverSheet.delete) {
        await _delete(context, ref, team);
      } else if (choice == _HandoverSheet.handedOver) {
        // The role moved but leaving did not: the page now shows a member's Leave.
        showMessage(context, l.teamHandoverLeaveFailed);
      }
      return;
    }
    final ok = await _confirm(context, l.teamLeaveConfirm(team.name), null, l.teamLeave);
    if (!ok || !context.mounted) return;
    await runTeamAction(context, ref, () => ref.read(socialRepositoryProvider).leaveTeam(team.id));
  }

  Future<void> _memberMenu(BuildContext context, WidgetRef ref, Team team, TeamMember member) async {
    final l = context.l;
    final picked = await showOptionSheet(
      context,
      title: member.name,
      options: {'captain': l.teamMakeCaptain, 'remove': l.teamRemoveMember},
    );
    if (picked == null || !context.mounted) return;
    final social = ref.read(socialRepositoryProvider);
    if (picked == 'captain') {
      if (!await _confirm(context, l.teamMakeCaptainConfirm(member.name), l.teamMakeCaptainMsg, l.teamMakeCaptain)) {
        return;
      }
      if (context.mounted) await runTeamAction(context, ref, () => social.transferCaptain(team.id, member.id));
    } else {
      if (!await _confirm(context, l.teamRemoveConfirm(member.name), null, l.teamRemove, destructive: true)) return;
      if (context.mounted) await runTeamAction(context, ref, () => social.removeTeamMember(team.id, member.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final value = ref.watch(teamProvider(teamId));
    final captain = value.valueOrNull?.isCaptain ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => _back(context)),
        actions: [
          if (captain)
            IconButton(
              key: const ValueKey('team-edit'),
              tooltip: l.editLabel,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/teams/$teamId/edit'),
            ),
        ],
      ),
      body: AsyncBody(
        value: value,
        builder: (team) => Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                // Pull to see what the captain and the others changed meanwhile.
                onRefresh: () => reloadQuietly(ref.refresh(teamProvider(teamId).future)),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  children: [
                    _Header(team: team),
                    if (team.isCaptain && team.requests.isNotEmpty) _Requests(team: team),
                    if (team.isMember || team.games.isNotEmpty) _Games(team: team),
                    SectionCard(
                      title: l.teamMembersTitle,
                      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                      child: Column(
                        children: [
                          for (var i = 0; i < team.members.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _MemberRow(
                              team: team,
                              member: team.members[i],
                              onMenu: () => _memberMenu(context, ref, team, team.members[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (team.isCaptain)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: OutlinedButton.icon(
                          key: const ValueKey('team-delete'),
                          onPressed: () => _delete(context, ref, team),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: Text(l.teamDelete),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _ActionBar(team: team, onLeave: () => _leave(context, ref, team)),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.team});

  final Team team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final description = team.description;
    final open = team.joinPolicy == TeamJoinPolicy.open;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              TeamAvatar(name: team.name, colorSeed: team.colorSeed, size: 72),
              const SizedBox(height: 12),
              Text(team.name, style: manrope(22, 800), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SportBadge(sportId: team.sportId, size: 24),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${teamSportName(context, sports, team.sportId)} · ${teamCityName(context, team.cityId)}',
                      style: AppText.muted,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  Pill(
                    text: open ? l.teamOpen : l.teamByApproval,
                    icon: open ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                  ),
                  Pill(text: l.members(team.memberCount), icon: Icons.groups_outlined),
                  if (team.upcomingGames > 0)
                    Pill(text: l.upcomingGames(team.upcomingGames), color: AppColors.blue, onColor: Colors.white),
                ],
              ),
              if (description != null && description.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(description, style: AppText.body),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The team's upcoming games the player may see, and the captain's way to
/// post one: the usual create form, with the team chosen.
class _Games extends StatelessWidget {
  const _Games({required this.team});

  final Team team;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return SectionCard(
      title: l.teamUpcomingGamesTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (team.games.isEmpty)
            Text(l.teamNoGames, style: AppText.muted)
          else
            for (final game in team.games)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GameCard(game: game),
              ),
          if (team.isCaptain) ...[
            if (team.games.isEmpty) const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('team-post-game'),
              onPressed: () => context.go('/games/new?team=${team.id}'),
              icon: const Icon(Icons.add_rounded),
              label: Text(l.teamPostGame),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pending requests, for the captain to approve or decline.
class _Requests extends ConsumerWidget {
  const _Requests({required this.team});

  final Team team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final social = ref.read(socialRepositoryProvider);
    return SectionCard(
      title: l.teamRequestsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < team.requests.length; i++) ...[
            if (i > 0) const Divider(height: 20),
            Row(
              children: [
                InitialAvatar(name: team.requests[i].name, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(team.requests[i].name, style: manrope(15.5, 700)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Pill(
                            text: _levelText(l, level: team.requests[i].level, rating: team.requests[i].rating),
                          ),
                          ReliabilityPill(reliability: team.requests[i].reliability),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: ValueKey('team-approve-${team.requests[i].id}'),
                  onPressed: () =>
                      runTeamAction(context, ref, () => social.decideTeamRequest(team.requests[i].id, approve: true)),
                  child: Text(l.approveLabel),
                ),
                OutlinedButton(
                  key: ValueKey('team-decline-request-${team.requests[i].id}'),
                  onPressed: () =>
                      runTeamAction(context, ref, () => social.decideTeamRequest(team.requests[i].id, approve: false)),
                  child: Text(l.declineLabel),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.team, required this.member, required this.onMenu});

  final Team team;
  final TeamMember member;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final name = playerName(l, member.name, deleted: member.deleted);
    final opens = member.id != kMeId && !member.deleted;
    return InkWell(
      onTap: opens ? () => context.push('/players/${member.id}') : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            InitialAvatar(name: name, size: 40, deleted: member.deleted),
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
                      if (member.captain)
                        Pill(
                          text: l.teamCaptain,
                          icon: Icons.star_rounded,
                          color: AppColors.primarySoft,
                          onColor: AppColors.primaryDark,
                        ),
                      if (!member.deleted) ...[
                        Pill(
                          text: _levelText(
                            l,
                            level: member.level,
                            rating: member.rating,
                            provisional: member.provisional,
                          ),
                        ),
                        ReliabilityPill(reliability: member.reliability),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (team.isCaptain && !member.captain && !member.deleted)
              IconButton(
                key: ValueKey('team-member-menu-${member.id}'),
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: onMenu,
              )
            else if (opens)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right_rounded, color: AppColors.faint),
              ),
          ],
        ),
      ),
    );
  }
}

/// The main button by the player's place in the team.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.team, required this.onLeave});

  final Team team;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final social = ref.read(socialRepositoryProvider);
    Future<void> run(Future<void> Function() action) => runTeamAction(context, ref, action);

    final Widget content = switch (team.myStatus) {
      MyTeamStatus.captain || MyTeamStatus.member => OutlinedButton.icon(
        key: const ValueKey('team-leave'),
        onPressed: onLeave,
        icon: const Icon(Icons.logout_rounded),
        label: Text(l.teamLeave),
      ),
      MyTeamStatus.requested => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.teamRequestSent, style: AppText.muted, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('team-cancel-request'),
            onPressed: team.myRequestId == null ? null : () => run(() => social.withdrawTeamRequest(team.myRequestId!)),
            child: Text(l.teamCancelRequest),
          ),
        ],
      ),
      MyTeamStatus.invited => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.teamInvited, style: AppText.muted, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const ValueKey('team-accept'),
                  onPressed: () => run(() => social.respondTeamInvite(team.id, accept: true)),
                  child: Text(l.teamAcceptInvite, textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('team-decline'),
                  onPressed: () => run(() => social.respondTeamInvite(team.id, accept: false)),
                  child: Text(l.declineLabel, textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ],
      ),
      null => FilledButton.icon(
        key: const ValueKey('team-join'),
        onPressed: () => run(() => social.joinTeam(team.id)),
        icon: const Icon(Icons.group_add_outlined),
        label: Text(team.joinPolicy == TeamJoinPolicy.open ? l.teamJoin : l.teamRequestJoin),
      ),
    };

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(width: double.infinity, child: content),
        ),
      ),
    );
  }
}

/// The captain's way out: hand the role to a member and leave, or, when
/// nobody else is in the team, delete it. Pops [delete] for the latter, and
/// [handedOver] when the role moved but leaving then failed.
class _HandoverSheet extends ConsumerStatefulWidget {
  const _HandoverSheet({required this.team});

  static const delete = 'delete';
  static const handedOver = 'handed_over';

  final Team team;

  @override
  ConsumerState<_HandoverSheet> createState() => _HandoverSheetState();
}

class _HandoverSheetState extends ConsumerState<_HandoverSheet> {
  String? _error;
  bool _busy = false;

  Future<void> _handOver(TeamMember member) async {
    final l = context.l;
    // Cannot be undone: an approval team would not let the old captain back.
    if (!await _confirm(context, l.teamHandoverConfirm(member.name), null, l.teamLeave)) return;
    if (!mounted) return;
    final social = ref.read(socialRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await teamActionError(l, () => social.transferCaptain(widget.team.id, member.id));
    if (!mounted) return;
    if (error == null) {
      // No longer captain: whatever leaving answers, this sheet is done.
      final left = await teamActionError(l, () => social.leaveTeam(widget.team.id));
      if (!mounted) return;
      refreshTeams(ref);
      Navigator.of(context).pop(left == null ? null : _HandoverSheet.handedOver);
      return;
    }
    refreshTeams(ref);
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final others = [
      for (final m in widget.team.members)
        if (!m.captain && !m.deleted) m,
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.teamHandoverTitle, style: AppText.title),
              const SizedBox(height: 8),
              Text(others.isEmpty ? l.teamHandoverEmpty : l.teamHandoverText, style: AppText.muted),
              const SizedBox(height: 8),
              for (final m in others)
                ListTile(
                  key: ValueKey('handover-${m.id}'),
                  contentPadding: EdgeInsets.zero,
                  enabled: !_busy,
                  leading: InitialAvatar(name: m.name, size: 36),
                  title: Text(m.name),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
                  onTap: () => _handOver(m),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: manrope(13.5, 600, color: AppColors.error)),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('handover-delete'),
                onPressed: _busy ? null : () => Navigator.of(context).pop(_HandoverSheet.delete),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(l.teamDelete),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A yes/no question with the action's own button.
Future<bool> _confirm(
  BuildContext context,
  String title,
  String? message,
  String label, {
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.l.cancel)),
        FilledButton(
          key: const ValueKey('team-dialog-ok'),
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.error) : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(label),
        ),
      ],
    ),
  );
  return confirmed == true;
}
