import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/competitive.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/rating_pill.dart';

/// One question of the starting-rating questionnaire and its four answers,
/// weakest first (answer index 0–3, as `questionnaireRating` scores them).
typedef Question = ({String text, List<String> answers});

/// The five questions for a rated sport (design §5.2): years played, how
/// often, competition, and two about the sport itself. Tennis has its own
/// skill questions; padel's serve every other rated sport.
List<Question> questionsFor(AppLocalizations l, String sportId) {
  final tennis = sportId == 'tennis';
  return [
    (text: l.qYears, answers: [l.qYearsA0, l.qYearsA1, l.qYearsA2, l.qYearsA3]),
    (text: l.qOften, answers: [l.qOftenA0, l.qOftenA1, l.qOftenA2, l.qOftenA3]),
    (text: l.qCompeted, answers: [l.qCompetedA0, l.qCompetedA1, l.qCompetedA2, l.qCompetedA3]),
    tennis
        ? (text: l.qTennisServe, answers: [l.qTennisServeA0, l.qTennisServeA1, l.qTennisServeA2, l.qTennisServeA3])
        : (text: l.qPadelWall, answers: [l.qPadelWallA0, l.qPadelWallA1, l.qPadelWallA2, l.qPadelWallA3]),
    tennis
        ? (text: l.qTennisRally, answers: [l.qTennisRallyA0, l.qTennisRallyA1, l.qTennisRallyA2, l.qTennisRallyA3])
        : (text: l.qPadelNet, answers: [l.qPadelNetA0, l.qPadelNetA1, l.qPadelNetA2, l.qPadelNetA3]),
  ];
}

/// The questionnaire for a rated [sport], one question per page, then the
/// rating the server gave. Returns whether a rating was saved (closing the
/// sheet on the result page counts as saved).
Future<bool> showQuestionnaire(BuildContext context, Sport sport) async {
  var saved = false;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _QuestionnaireSheet(sport: sport, onSaved: () => saved = true),
  );
  return saved;
}

class _QuestionnaireSheet extends ConsumerStatefulWidget {
  const _QuestionnaireSheet({required this.sport, required this.onSaved});

  final Sport sport;
  final VoidCallback onSaved;

  @override
  ConsumerState<_QuestionnaireSheet> createState() => _QuestionnaireSheetState();
}

class _QuestionnaireSheetState extends ConsumerState<_QuestionnaireSheet> {
  final _answers = <int>[];
  SportRating? _result;
  bool _busy = false;
  String? _error;

  /// [step]: the question the tapped answer belongs to. A second tap on it
  /// before the next question shows does not answer that one too.
  Future<void> _answer(int step, int index, int questionCount) async {
    if (_busy || _answers.length != step) return;
    setState(() {
      _answers.add(index);
      _error = null;
    });
    if (_answers.length == questionCount) await _save();
  }

  void _back() => setState(() {
    _answers.removeLast();
    _error = null;
  });

  Future<void> _save() async {
    final l = context.l;
    // Taken now: the sheet may be gone when the save returns.
    final container = ProviderScope.containerOf(context, listen: false);
    final social = ref.read(socialRepositoryProvider);
    setState(() => _busy = true);
    try {
      final mine = await social.setSport(widget.sport.id, answers: [..._answers]);
      // The server's rating, which is the kept one if the player already has rated games.
      final rating = mine.where((s) => s.sportId == widget.sport.id).firstOrNull?.rating;
      if (rating == null) throw const JoinException(JoinError.unavailable);
      widget.onSaved();
      refreshSportsIn(container);
      if (mounted) {
        setState(() {
          _busy = false;
          _result = rating;
        });
      }
    } on JoinException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _answers.removeLast();
          _error = joinErrorText(l, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final questions = questionsFor(l, widget.sport.id);
    final result = _result;
    final step = _answers.length.clamp(0, questions.length - 1);

    // Not closed by a tap outside or Back while the answers are being saved.
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.questionnaireTitle(widget.sport.name.resolve(context.lang)).toUpperCase(),
                  style: AppText.sectionTitle,
                ),
                const SizedBox(height: 12),
                if (result != null) ...[
                  Text(l.questionnaireResult(formatRating(result.rating)), style: AppText.title),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: RatingPill(result)),
                  const SizedBox(height: 12),
                  Text(l.questionnaireResultHint(RatingRules.provisionalGames), style: AppText.muted),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.doneLabel)),
                ] else ...[
                  Text(l.questionnaireStep(step + 1, questions.length), style: AppText.caption),
                  const SizedBox(height: 6),
                  Text(questions[step].text, style: AppText.title),
                  const SizedBox(height: 16),
                  for (final (i, answer) in questions[step].answers.indexed)
                    _AnswerTile(
                      key: ValueKey('answer-$step-$i'),
                      text: answer,
                      onTap: _busy ? null : () => _answer(step, i, questions.length),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(_error!, style: manrope(13.5, 600, color: AppColors.error)),
                  ],
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (_answers.isNotEmpty && !_busy)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _back,
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: Text(l.backLabel),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One answer: wraps onto more lines rather than being cut.
class _AnswerTile extends StatelessWidget {
  const _AnswerTile({super.key, required this.text, required this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(child: Text(text, style: manrope(15.5, 700))),
              const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
            ],
          ),
        ),
      ),
    ),
  );
}
