import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/admin.dart';
import '../../domain/competitive.dart';
import '../../domain/teams.dart';
import '../../state/admin_providers.dart';
import '../../state/providers.dart';
import '../../state/ui_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../games/finished_section.dart';
import '../games/report_sheet.dart';
import '../games/score_sheet.dart';
import 'admin_common.dart';

/// What an admin has to decide (design §6.4): disputed and flagged scores,
/// open abuse reports, and teams to remove, in three tabs.
class AdminReviewScreen extends StatelessWidget {
  const AdminReviewScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      AdminScaffold(title: context.l.adminReview, fallback: '/admin', body: (_) => const _ReviewBody());
}

/// One tab of the screen: its label, with the count it holds, and its list.
typedef _ReviewTab = ({Key key, String label, Widget view});

class _ReviewBody extends ConsumerWidget {
  const _ReviewBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final value = ref.watch(adminReviewProvider);
    // The last list stays on screen while it reloads after an action, so the
    // tab the admin is on does not change.
    final review = value.valueOrNull;
    if (review == null) {
      return value.hasError
          ? EmptyState(icon: Icons.error_outline, text: l.errGeneric)
          : const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            );
    }

    final tabs = <_ReviewTab>[
      (
        key: const ValueKey('review-tab-scores'),
        label: l.reviewScoresTab(review.disputes.length),
        view: _ScoresTab(disputes: review.disputes),
      ),
      (
        key: const ValueKey('review-tab-reports'),
        label: l.reviewReportsTab(review.reports.length),
        view: _ReportsTab(reports: review.reports),
      ),
      (
        key: const ValueKey('review-tab-teams'),
        label: l.reviewTeamsTab(review.teams.length),
        view: _TeamsTab(teams: review.teams),
      ),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(tabs: [for (final t in tabs) Tab(key: t.key, text: t.label)]),
          Expanded(child: TabBarView(children: [for (final t in tabs) t.view])),
        ],
      ),
    );
  }
}

// ---- Scores ----

class _ScoresTab extends StatelessWidget {
  const _ScoresTab({required this.disputes});

  final List<AdminDispute> disputes;

  @override
  Widget build(BuildContext context) => disputes.isEmpty
      ? Center(child: EmptyState(icon: Icons.fact_check_outlined, text: context.l.reviewNoScores))
      : AdminListView(
          bottom: 24,
          children: [for (final d in disputes) _DisputeCard(key: ValueKey('review-score-${d.result.id}'), dispute: d)],
        );
}

/// The day and time of a game, in the venue's own clock.
String _gameTime(BuildContext context, AdminGameNote game) =>
    DateFormat('EEE, d MMM, HH:mm', context.lang).format(game.startsLocal);

/// The sport's name in the app language, or its id for one that is gone.
String _sportName(BuildContext context, WidgetRef ref, String sportId) {
  final sports = ref.watch(adminSportsProvider).valueOrNull ?? const <AdminSport>[];
  return sports.where((s) => s.sport.id == sportId).firstOrNull?.sport.name.resolve(context.lang) ?? sportId;
}

/// What an admin can do with a score; [wire] is the word the server takes.
enum _ScoreAction {
  confirm('confirm'),
  correct('correct'),
  voidScore('void'),
  keep('keep');

  const _ScoreAction(this.wire);

  final String wire;
}

class _DisputeCard extends ConsumerWidget {
  const _DisputeCard({super.key, required this.dispute});

  final AdminDispute dispute;

  Future<void> _resolve(BuildContext context, WidgetRef ref, _ScoreAction action) async {
    final l = context.l;
    final id = dispute.result.id;
    if (action == _ScoreAction.correct) {
      final sets = await showAdminSheet<List<(int, int)>>(context, (_) => _CorrectSheet(dispute: dispute));
      if (sets == null || !context.mounted) return;
      await _run(context, ref, () => ref.read(adminRepositoryProvider).resolveScore(id, 'correct', sets: sets));
      return;
    }
    final (title, message, label) = switch (action) {
      _ScoreAction.confirm => (l.reviewConfirmTitle, l.reviewConfirmMsg, l.reviewConfirm),
      _ScoreAction.keep => (l.reviewKeepTitle, l.reviewKeepMsg, l.reviewKeep),
      _ => (l.reviewVoidTitle, l.reviewVoidMsg, l.reviewVoid),
    };
    if (!await _confirmAction(context, title, message, label, destructive: action == _ScoreAction.voidScore)) return;
    if (!context.mounted) return;
    await _run(context, ref, () => ref.read(adminRepositoryProvider).resolveScore(id, action.wire));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final result = dispute.result;
    final id = result.id;
    final reason = result.disputeReason;
    final disputer = (dispute.disputedByName ?? '').isEmpty ? l.deletedPlayer : dispute.disputedByName!;

    Widget button(_ScoreAction action, String label, {bool filled = false, bool danger = false}) {
      final key = ValueKey('review-${action.wire}-$id');
      void onPressed() => _resolve(context, ref, action);
      if (filled) return FilledButton(key: key, onPressed: onPressed, child: Text(label));
      return OutlinedButton(
        key: key,
        onPressed: onPressed,
        style: danger ? OutlinedButton.styleFrom(foregroundColor: AppColors.error) : null,
        child: Text(label),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_sportName(context, ref, dispute.game.sportId)} · ${_gameTime(context, dispute.game)}',
              style: AppText.cardTitle,
            ),
            const SizedBox(height: 10),
            ScoreBoard.named(names: dispute.names, result: result),
            const SizedBox(height: 10),
            if (dispute.flagged)
              _StatusPill(l.reviewFlaggedNoShow)
            else if (reason == 'no_show')
              _StatusPill(l.reviewNoShowFrozen)
            else
              Text(
                reason == null ? l.reviewDisputedByNoReason(disputer) : l.reviewDisputedBy(disputer, reason),
                style: AppText.muted,
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (dispute.flagged) ...[
                  button(_ScoreAction.keep, l.reviewKeep, filled: true),
                  button(_ScoreAction.voidScore, l.reviewVoid, danger: true),
                ] else ...[
                  button(_ScoreAction.confirm, l.reviewConfirm, filled: true),
                  button(_ScoreAction.correct, l.reviewCorrect),
                  button(_ScoreAction.voidScore, l.reviewVoid, danger: true),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Pill(text: text, icon: Icons.flag_outlined, color: AppColors.amberSoft, onColor: const Color(0xFF7A4B00)),
  );
}

/// The sets of the entered score, to be corrected.
class _CorrectSheet extends StatefulWidget {
  const _CorrectSheet({required this.dispute});

  final AdminDispute dispute;

  @override
  State<_CorrectSheet> createState() => _CorrectSheetState();
}

class _CorrectSheetState extends State<_CorrectSheet> {
  late List<(int, int)> _sets = [...widget.dispute.result.sets];

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final d = widget.dispute;
    String side(List<String> ids) => ids.map(d.nameOf).join(', ');
    return AdminSheetFrame(
      title: l.reviewCorrectTitle,
      saveKey: const ValueKey('review-correct-save'),
      busy: !validSets(_sets),
      onSave: () => Navigator.of(context).pop(_sets),
      children: [
        Text(l.reviewCorrectHint, style: AppText.muted),
        const SizedBox(height: 14),
        SetsEditor(
          sets: _sets,
          firstSide: side(d.result.sideA),
          secondSide: side(d.result.sideB),
          onChanged: (sets) => setState(() => _sets = sets),
        ),
      ],
    );
  }
}

// ---- Reports ----

class _ReportsTab extends StatelessWidget {
  const _ReportsTab({required this.reports});

  final List<AdminReport> reports;

  @override
  Widget build(BuildContext context) => reports.isEmpty
      ? Center(child: EmptyState(icon: Icons.flag_outlined, text: context.l.reviewNoReports))
      : AdminListView(
          bottom: 24,
          children: [for (final r in reports) _ReportCard(key: ValueKey('review-report-${r.id}'), report: r)],
        );
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({super.key, required this.report});

  final AdminReport report;

  Future<void> _close(BuildContext context, WidgetRef ref) async {
    final note = await showAdminSheet<String>(context, (_) => const _CloseSheet());
    if (note == null || !context.mounted) return;
    await _run(context, ref, () => ref.read(adminRepositoryProvider).closeReport(report.id, note: note));
  }

  Future<void> _voidScore(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    if (!await _confirmAction(context, l.reviewVoidTitle, l.reviewVoidMsg, l.reviewVoid, destructive: true)) return;
    if (!context.mounted) return;
    await _run(context, ref, () => ref.read(adminRepositoryProvider).resolveScore(report.result!.id, 'void'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final game = report.game;
    final result = report.result;
    final details = report.details;
    final when = DateFormat('d MMM y, HH:mm', context.lang).format(report.createdAt.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: ValueKey('review-target-${report.id}'),
              onTap: () => context.push('/players/${report.targetId}'),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.reviewReportLine(
                        report.reporterName.isEmpty ? l.deletedPlayer : report.reporterName,
                        report.targetName.isEmpty ? l.deletedPlayer : report.targetName,
                      ),
                      style: AppText.cardTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Pill(text: reportReasonText(l, report.reason)),
                Text(when, style: AppText.caption),
              ],
            ),
            if (details != null && details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(details, style: AppText.body),
            ],
            if (game != null) ...[
              const SizedBox(height: 8),
              Text(
                '${_sportName(context, ref, game.sportId)} · ${_gameTime(context, game)}',
                style: AppText.muted,
              ),
            ],
            if (report.hasLiveScore) ...[
              const SizedBox(height: 4),
              Text(
                l.reviewScoreLine([for (final (a, b) in result!.sets) '$a–$b'].join(', ')),
                key: ValueKey('review-report-score-${report.id}'),
                style: AppText.bodyStrong,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: ValueKey('review-close-${report.id}'),
                  onPressed: () => _close(context, ref),
                  child: Text(l.reviewClose),
                ),
                if (report.hasLiveScore)
                  OutlinedButton(
                    key: ValueKey('review-void-score-${report.id}'),
                    onPressed: () => _voidScore(context, ref),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                    child: Text(l.reviewVoidScore),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The optional note of a closed report; pops with the text ('' for none).
class _CloseSheet extends StatefulWidget {
  const _CloseSheet();

  @override
  State<_CloseSheet> createState() => _CloseSheetState();
}

class _CloseSheetState extends State<_CloseSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return AdminSheetFrame(
      title: l.reviewCloseTitle,
      saveKey: const ValueKey('review-close-save'),
      saveLabel: l.reviewCloseReport,
      onSave: () => Navigator.of(context).pop(_note.text),
      children: [
        TextField(
          key: const ValueKey('review-note'),
          controller: _note,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(labelText: l.reviewNote),
        ),
      ],
    );
  }
}

// ---- Teams ----

/// Every team, newest first, for names or descriptions that should not stay
/// up (design §6.4).
class _TeamsTab extends StatelessWidget {
  const _TeamsTab({required this.teams});

  final List<Team> teams;

  @override
  Widget build(BuildContext context) => teams.isEmpty
      ? Center(child: EmptyState(icon: Icons.groups_outlined, text: context.l.reviewNoTeams))
      : AdminListView(
          bottom: 24,
          children: [for (final t in teams) _TeamCard(key: ValueKey('review-team-${t.id}'), team: t)],
        );
}

class _TeamCard extends ConsumerWidget {
  const _TeamCard({super.key, required this.team});

  final Team team;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    if (!await confirmDelete(context, team.name) || !context.mounted) return;
    final ok = await adminWrite(
      context,
      ref,
      () => ref.read(adminRepositoryProvider).deleteTeam(team.id),
      adminOnly: true,
    );
    if (ok) {
      refreshTeams(ref);
    } else {
      ref.invalidate(adminReviewProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final city = kCities.where((c) => c.id == team.cityId).firstOrNull?.name.resolve(context.lang) ?? team.cityId;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(team.name, style: AppText.cardTitle),
            const SizedBox(height: 4),
            Text('${_sportName(context, ref, team.sportId)} · $city', style: AppText.muted),
            const SizedBox(height: 4),
            Text(l.members(team.memberCount), style: AppText.caption),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: ValueKey('review-delete-team-${team.id}'),
                onPressed: () => _delete(context, ref),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                child: Text(l.deleteLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Shared ----

/// Runs an admin write on a score or report. The list is reloaded either way:
/// a refused call usually means someone else got there first. A decided score
/// changes ratings and the game, so those screens reload too.
Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
  final ok = await adminWrite(context, ref, action, adminOnly: true);
  if (ok) {
    refreshGames(ref);
    refreshSports(ref);
  } else {
    ref.invalidate(adminReviewProvider);
  }
}

/// "Void this score? …": Cancel, and the action's own button.
Future<bool> _confirmAction(
  BuildContext context,
  String title,
  String message,
  String label, {
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.l.cancel)),
        FilledButton(
          key: const ValueKey('review-dialog-ok'),
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.error) : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(label),
        ),
      ],
    ),
  );
  return confirmed == true;
}
