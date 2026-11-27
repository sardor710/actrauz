import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/sample/sample_data.dart';
import '../../domain/games.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import 'finished_section.dart';

/// Enters the score of [game], or corrects the player's own pending one
/// (design §5.4): who played, then the games per set. Returns `true` when saved.
Future<bool?> showScoreSheet(BuildContext context, Game game) => showModalBottomSheet<bool>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => ScoreSheet(game: game),
);

class ScoreSheet extends ConsumerStatefulWidget {
  const ScoreSheet({super.key, required this.game});

  final Game game;

  @override
  ConsumerState<ScoreSheet> createState() => _ScoreSheetState();
}

class _ScoreSheetState extends ConsumerState<ScoreSheet> {
  /// The other participants the player can pick, in the game's order.
  late final List<String> _others = [
    for (final id in widget.game.participantIds)
      if (id != kMeId && !(widget.game.participants.where((m) => m.id == id).firstOrNull?.deleted ?? false)) id,
  ];

  /// 2 against 2, else 1 against 1.
  late bool _doubles;
  String? _partner;
  List<String> _opponents = [];

  /// (the player's side, the other side) per set.
  List<(int, int)> _sets = [(0, 0)];

  /// A 1-against-1 result in a game of four, entered elsewhere, stays editable.
  bool _singlesInFour = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final result = widget.game.result;
    if (result != null && result.enteredBy == kMeId) {
      // Correcting my own score: my side first, the sets turned to match.
      final mineIsA = result.sideA.contains(kMeId);
      final mine = mineIsA ? result.sideA : result.sideB;
      _doubles = mine.length == 2;
      _partner = mine.where((id) => id != kMeId).firstOrNull;
      _opponents = [...(mineIsA ? result.sideB : result.sideA)];
      _sets = [for (final (a, b) in result.sets) mineIsA ? (a, b) : (b, a)];
      _singlesInFour = !_doubles && _others.length == 3;
      return;
    }
    switch (_others.length) {
      case 1:
        _doubles = false;
        _opponents = [_others.first];
      case 3:
        // The player and the first other one against the remaining two.
        _doubles = true;
        _partner = _others.first;
        _opponents = _others.sublist(1);
      case 2:
        _doubles = false;
      default:
        _doubles = true;
    }
  }

  /// Exactly four players: everyone played, so only partners are picked.
  bool get _fourPlayers => _others.length == 3;

  bool get _canDoubles => _others.length >= 3;
  bool get _canSingles => !_fourPlayers || _singlesInFour;

  List<String> get _mySide => [kMeId, if (_doubles && _partner != null) _partner!];

  bool get _valid {
    final sidesOk = _doubles
        ? _partner != null && _opponents.length == 2 && !_opponents.contains(_partner)
        : _opponents.length == 1;
    return sidesOk && SetsEditor.valid(_sets);
  }

  void _pickFormat(bool doubles) => setState(() {
    _doubles = doubles;
    _partner = null;
    _opponents = [];
  });

  void _pickPartner(String id) => setState(() {
    _partner = id;
    // In a game of four the other two are the opponents; else the partner
    // cannot also be one.
    _opponents = [
      for (final o in _fourPlayers ? _others : _opponents)
        if (o != id) o,
    ];
  });

  void _toggleOpponent(String id) => setState(() {
    if (_opponents.contains(id)) {
      _opponents = [..._opponents]..remove(id);
    } else if (!_doubles) {
      _opponents = [id];
    } else if (_opponents.length < 2) {
      _opponents = [..._opponents, id];
    }
  });

  /// Shown in the sheet: a snackbar would be hidden behind it.
  Future<void> _save() async {
    final l = context.l;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(gameRepositoryProvider).enterScore(widget.game.id, sideA: _mySide, sideB: _opponents, sets: _sets);
      refreshGames(ref);
      if (mounted) Navigator.of(context).pop(true);
    } on JoinException catch (e) {
      // The game may have moved on (a score entered or disputed meanwhile).
      refreshGames(ref);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = joinErrorText(l, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    String name(String id) => memberName(l, widget.game, id);

    Widget chips(Iterable<String> ids, {required bool Function(String) selected, required void Function(String) onTap, required String keyPrefix}) =>
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in ids)
              ChoiceChip(
                key: ValueKey('$keyPrefix-$id'),
                label: Text(name(id)),
                selected: selected(id),
                onSelected: (_) => onTap(id),
              ),
          ],
        );

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(text, style: AppText.bodyStrong),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.scoreEnter, style: AppText.title),
              const SizedBox(height: 8),
              Text(l.scoreWhoPlayed.toUpperCase(), style: AppText.sectionTitle),
              if (_canDoubles && _canSingles) ...[
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, label: Text(l.scoreSingles, key: const ValueKey('score-singles'))),
                    ButtonSegment(value: true, label: Text(l.scoreDoubles, key: const ValueKey('score-doubles'))),
                  ],
                  selected: {_doubles},
                  onSelectionChanged: (v) => _pickFormat(v.first),
                ),
              ],
              if (_others.length > 1) ...[
                if (_doubles) ...[
                  label(l.scorePartner),
                  chips(_others, selected: (id) => id == _partner, onTap: _pickPartner, keyPrefix: 'score-partner'),
                ],
                if (!_doubles || !_fourPlayers) ...[
                  label(_doubles ? l.scoreOpponents : l.scoreOpponent),
                  chips(
                    [for (final id in _others) if (id != _partner || !_doubles) id],
                    selected: _opponents.contains,
                    onTap: _toggleOpponent,
                    keyPrefix: 'score-opponent',
                  ),
                ],
              ],
              const SizedBox(height: 14),
              _SideLine(title: l.scoreYourSide, names: [for (final id in _mySide) name(id)]),
              const SizedBox(height: 4),
              _SideLine(title: l.scoreOtherSide, names: [for (final id in _opponents) name(id)]),
              const SizedBox(height: 18),
              Text(l.scoreSets.toUpperCase(), style: AppText.sectionTitle),
              const SizedBox(height: 8),
              SetsEditor(
                sets: _sets,
                firstSide: l.scoreYourSide,
                secondSide: l.scoreOtherSide,
                onChanged: (sets) => setState(() => _sets = sets),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: manrope(13.5, 600, color: AppColors.error)),
              ],
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('score-save'),
                onPressed: _valid && !_busy ? _save : null,
                child: Text(l.saveLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The games won per set, 1 to 5 sets: a header naming the two sides, a stepper
/// pair per set, and Add set. Shared by the score sheet and the admin's
/// correction of a score.
class SetsEditor extends StatelessWidget {
  const SetsEditor({
    super.key,
    required this.sets,
    required this.onChanged,
    required this.firstSide,
    required this.secondSide,
  });

  static const maxSets = 5;
  static const maxGames = 30;

  /// 1 to [maxSets] sets of 0 to [maxGames] games, none 0–0.
  static bool valid(List<(int, int)> sets) =>
      sets.isNotEmpty &&
      sets.length <= maxSets &&
      sets.every((s) => s.$1 >= 0 && s.$1 <= maxGames && s.$2 >= 0 && s.$2 <= maxGames && (s.$1 != 0 || s.$2 != 0));

  final List<(int, int)> sets;
  final ValueChanged<List<(int, int)>> onChanged;

  /// What the two columns are called.
  final String firstSide;
  final String secondSide;

  void _setGames(int index, {int? first, int? second}) {
    final (a, b) = sets[index];
    onChanged([...sets]..[index] = (first ?? a, second ?? b));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 24),
            Expanded(child: Text(firstSide, textAlign: TextAlign.center, style: AppText.caption, maxLines: 2)),
            const SizedBox(width: 12),
            Expanded(child: Text(secondSide, textAlign: TextAlign.center, style: AppText.caption, maxLines: 2)),
            const SizedBox(width: 36),
          ],
        ),
        for (final (i, (first, second)) in sets.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(width: 24, child: Text('${i + 1}', style: AppText.caption)),
                Expanded(
                  child: _GamesStepper(
                    keyPrefix: 'set-$i-mine',
                    value: first,
                    onChanged: (v) => _setGames(i, first: v),
                  ),
                ),
                SizedBox(width: 12, child: Text('–', textAlign: TextAlign.center, style: AppText.bodyStrong)),
                Expanded(
                  child: _GamesStepper(
                    keyPrefix: 'set-$i-theirs',
                    value: second,
                    onChanged: (v) => _setGames(i, second: v),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: sets.length > 1
                      ? IconButton(
                          key: ValueKey('set-$i-remove'),
                          tooltip: l.scoreRemoveSet,
                          padding: EdgeInsets.zero,
                          onPressed: () => onChanged([...sets]..removeAt(i)),
                          icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                        )
                      : null,
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('score-add-set'),
            onPressed: sets.length < maxSets ? () => onChanged([...sets, (0, 0)]) : null,
            icon: const Icon(Icons.add_rounded),
            label: Text(l.scoreAddSet),
          ),
        ),
      ],
    );
  }
}

/// "Your side: You, Aziz".
class _SideLine extends StatelessWidget {
  const _SideLine({required this.title, required this.names});

  final String title;
  final List<String> names;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '$title: ', style: AppText.muted),
        TextSpan(text: names.isEmpty ? '—' : names.join(', '), style: AppText.bodyStrong),
      ],
    ),
  );
}

/// Games won in a set, 0 to 30.
class _GamesStepper extends StatelessWidget {
  const _GamesStepper({required this.keyPrefix, required this.value, required this.onChanged});

  static const _max = 30;

  final String keyPrefix;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    const size = BoxConstraints.tightFor(width: 34, height: 34);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          key: ValueKey('$keyPrefix-minus'),
          tooltip: l.scoreFewerGames,
          constraints: size,
          padding: EdgeInsets.zero,
          iconSize: 18,
          style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 30,
          child: Text('$value', key: ValueKey(keyPrefix), textAlign: TextAlign.center, style: manrope(20, 800)),
        ),
        IconButton.filledTonal(
          key: ValueKey('$keyPrefix-plus'),
          tooltip: l.scoreMoreGames,
          constraints: size,
          padding: EdgeInsets.zero,
          iconSize: 18,
          style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          onPressed: value < _max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
