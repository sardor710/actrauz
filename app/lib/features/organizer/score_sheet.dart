import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/brackets.dart';
import '../../domain/competitive.dart';
import '../../domain/tournaments.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../games/score_sheet.dart' show SetsEditor;
import '../tournaments/bracket_view.dart';
import '../tournaments/tournament_tools.dart';
import 'match_tools.dart';

/// The organiser enters or corrects a match's result (M8a design §7.3,
/// §7.4, §14a.4): played, walkover or retired. Rated sports enter M7 sets;
/// other sports one score per side, and a level knockout score asks who won
/// the decider. Returns `true` when saved; a refusal is shown in the sheet.
Future<bool?> showMatchScoreSheet(BuildContext context, ManagedMatch match, {required bool rated}) =>
    showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ClosesOnAccountChange(child: MatchScoreSheet(match: match, rated: rated)),
    );

/// The outcomes the organiser picks from; a decider is a played match with a
/// level score.
enum _Kind { played, walkover, retired }

class MatchScoreSheet extends ConsumerStatefulWidget {
  const MatchScoreSheet({super.key, required this.match, required this.rated});

  final ManagedMatch match;
  final bool rated;

  @override
  ConsumerState<MatchScoreSheet> createState() => _MatchScoreSheetState();
}

class _MatchScoreSheetState extends ConsumerState<MatchScoreSheet> {
  TournamentMatch get m => widget.match.match;
  bool get rated => widget.rated;
  bool get knockout => m.stage == MatchStage.knockout;

  late _Kind _kind;

  /// Rated sports: (side a, side b) per set.
  late List<(int, int)> _sets;

  /// Other sports: the score of side a and side b.
  late (int, int) _points;
  Side? _winner;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A correction starts from what was entered.
    _kind = switch (m.outcome) {
      MatchOutcome.walkover => _Kind.walkover,
      MatchOutcome.retired => _Kind.retired,
      _ => _Kind.played,
    };
    final sets = m.sets;
    _sets = sets == null || sets.isEmpty ? [(0, 0)] : [for (final s in sets) (s[0], s[1])];
    _points = sets == null || sets.isEmpty ? (0, 0) : (sets.first[0], sets.first[1]);
    _winner = m.winner == Side.a || m.winner == Side.b ? m.winner : null;
  }

  bool get _level => _points.$1 == _points.$2;

  /// A withdrawn entry wins nothing it had not already won (the backend
  /// refuses it): its chip is off unless it is the winner stored now.
  bool _canWin(Side side) {
    final registrationId = side == Side.a ? m.sideA : m.sideB;
    final withdrawn = widget.match.draw.entries.any((e) => e.registrationId == registrationId && e.withdrawn);
    return !withdrawn || (m.status == MatchStatus.done && m.winner == side);
  }

  /// A knockout match of a sport without sets ending level: the organiser
  /// names who won the decider.
  bool get _decider => _kind == _Kind.played && !rated && knockout && _level;

  bool get _needsWinner => _kind != _Kind.played || _decider;

  bool get _scoreValid => rated ? validSets(_sets) : true;

  bool get _valid => (_kind == _Kind.walkover || _scoreValid) && (!_needsWinner || _winner != null);

  List<List<int>> get _score => rated
      ? [
          for (final (a, b) in _sets) [a, b],
        ]
      : [
          [_points.$1, _points.$2],
        ];

  Future<void> _save() async {
    final l = context.l;
    // Taken now: the sheet may be gone when the save returns.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final organizer = ref.read(organizerRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final (outcome, winner, sets) = switch (_kind) {
      _Kind.walkover => (MatchOutcome.walkover, _winner, null),
      _Kind.retired => (MatchOutcome.retired, _winner, _score),
      _Kind.played when _decider => (MatchOutcome.decider, _winner, _score),
      _Kind.played => (MatchOutcome.played, null, _score),
    };
    try {
      await organizer.enterScore(m.id, outcome, winner: winner, sets: sets);
      refreshTournamentsIn(container);
      if (mounted) Navigator.of(context).pop(true);
    } on TournamentException catch (e) {
      // The bracket may have moved on meanwhile.
      refreshTournamentsIn(container);
      if (!mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(organizerErrorText(l, e)), behavior: SnackBarBehavior.floating));
        return;
      }
      setState(() {
        _busy = false;
        _error = organizerErrorText(l, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final draw = widget.match.draw;
    final nameA = entryName(l, draw, m.sideA);
    final nameB = entryName(l, draw, m.sideB);

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text.toUpperCase(), style: AppText.sectionTitle),
    );

    Widget scoreInput() => rated
        ? SetsEditor(
            sets: _sets,
            firstSide: nameA,
            secondSide: nameB,
            onChanged: (sets) => setState(() => _sets = sets),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (side, name) in [(Side.a, nameA), (Side.b, nameB)])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(name, style: AppText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      _PointsStepper(
                        keyPrefix: side == Side.a ? 'points-a' : 'points-b',
                        value: side == Side.a ? _points.$1 : _points.$2,
                        onChanged: (v) => setState(() => _points = side == Side.a ? (v, _points.$2) : (_points.$1, v)),
                      ),
                    ],
                  ),
                ),
            ],
          );

    Widget winnerPick() => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (side, name) in [(Side.a, nameA), (Side.b, nameB)])
          ChoiceChip(
            key: ValueKey(side == Side.a ? 'winner-a' : 'winner-b'),
            label: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            selected: _winner == side,
            onSelected: _canWin(side) ? (_) => setState(() => _winner = side) : null,
          ),
      ],
    );

    return PopScope(
      // Not closed by a tap outside or Back while the score is being saved.
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(m.status == MatchStatus.done ? l.scoreCorrect : l.scoreEnter, style: AppText.title),
                const SizedBox(height: 4),
                Text(matchStageText(l, context.lang, widget.match), style: AppText.muted),
                const SizedBox(height: 14),
                // Chips that wrap: "Техническая победа" does not fit a third
                // of a phone.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (kind, text, key) in [
                      (_Kind.played, l.outcomePlayed, 'outcome-played'),
                      (_Kind.walkover, l.outcomeWalkover, 'outcome-walkover'),
                      (_Kind.retired, l.outcomeRetired, 'outcome-retired'),
                    ])
                      ChoiceChip(
                        key: ValueKey(key),
                        label: Text(text),
                        selected: _kind == kind,
                        onSelected: (_) => setState(() => _kind = kind),
                      ),
                  ],
                ),
                if (_kind != _Kind.walkover) ...[
                  label(rated ? l.scoreSets : l.scoreEnter),
                  if (_kind == _Kind.retired) ...[
                    Text(l.retiredHint, style: AppText.caption),
                    const SizedBox(height: 6),
                  ],
                  scoreInput(),
                ],
                if (_needsWinner) ...[
                  if (_decider)
                    Padding(
                      key: const ValueKey('decider-prompt'),
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Text(l.deciderPrompt, style: AppText.bodyStrong),
                    )
                  else
                    label(l.matchWinner),
                  winnerPick(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: manrope(13.5, 600, color: AppColors.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('match-score-save'),
                  onPressed: _valid && !_busy ? _save : null,
                  child: Text(l.saveLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A score of 0 to 99 (goals, points).
class _PointsStepper extends StatelessWidget {
  const _PointsStepper({required this.keyPrefix, required this.value, required this.onChanged});

  static const max = 99;

  final String keyPrefix;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    const size = BoxConstraints.tightFor(width: 40, height: 40);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          key: ValueKey('$keyPrefix-minus'),
          tooltip: l.scoreFewerGames,
          constraints: size,
          padding: EdgeInsets.zero,
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 40,
          child: Text('$value', key: ValueKey(keyPrefix), textAlign: TextAlign.center, style: manrope(20, 800)),
        ),
        IconButton.filledTonal(
          key: ValueKey('$keyPrefix-plus'),
          tooltip: l.scoreMoreGames,
          constraints: size,
          padding: EdgeInsets.zero,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
