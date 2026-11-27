import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/brackets.dart';
import '../common/formatters.dart';
import 'bracket_view.dart';

/// One group's table in place order: played, won, lost, points; the places
/// that go through to the knockout are marked.
class GroupTable extends StatelessWidget {
  const GroupTable({super.key, required this.group, required this.draw});

  final DrawGroup group;
  final CategoryDraw draw;

  static const _numberWidth = 30.0;
  static const _pointsWidth = 44.0;

  @override
  Widget build(BuildContext context) {
    final l = context.l;

    Widget number(String text, {double width = _numberWidth, TextStyle? style}) => SizedBox(
      width: width,
      child: Text(text, textAlign: TextAlign.center, maxLines: 1, style: style ?? AppText.body),
    );

    return Container(
      key: ValueKey('group-${group.id}'),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.field,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.groupLabel(group.label),
                    style: AppText.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                number(l.tablePlayed, style: AppText.caption),
                number(l.tableWon, style: AppText.caption),
                number(l.tableLost, style: AppText.caption),
                number(l.tablePoints, width: _pointsWidth, style: AppText.caption),
              ],
            ),
          ),
          for (final s in group.standings)
            Container(
              key: ValueKey('group-row-${s.registrationId}'),
              color: s.advancing ? AppColors.primarySoft : null,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  SizedBox(width: 20, child: Text('${s.place}', style: AppText.caption)),
                  Expanded(
                    child: Text(
                      entryName(l, draw, s.registrationId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: s.withdrawn
                          ? AppText.muted.copyWith(decoration: TextDecoration.lineThrough)
                          : AppText.bodyStrong,
                    ),
                  ),
                  if (s.advancing)
                    Tooltip(
                      message: l.groupAdvancing,
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        key: ValueKey('advancing-${s.registrationId}'),
                        size: 16,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  number('${s.played}'),
                  number('${s.won}'),
                  number('${s.lost}'),
                  number('${s.points}', width: _pointsWidth, style: AppText.bodyStrong),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
