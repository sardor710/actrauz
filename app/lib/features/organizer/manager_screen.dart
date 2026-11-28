import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'draw_tab.dart';
import 'schedule_tab.dart';
import 'scores_tab.dart';

/// The tournament manager (M8a design §11), for its organisers and admins:
/// Draw, Schedule and Scores tabs. Phone width first: it is used courtside.
///
/// The screen checks nothing itself; the backend refuses everyone else and
/// the Draw tab says so. Reloads on opening; a failed reload keeps what was
/// shown, and another account never sees the previous one's data (each tab
/// reads its data with currentData, which knows which account loaded it).
class ManagerScreen extends ConsumerStatefulWidget {
  const ManagerScreen({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  ConsumerState<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends ConsumerState<ManagerScreen> {
  String get tournamentId => widget.tournamentId;

  @override
  void initState() {
    super.initState();
    // Opened again: entries, draws and scores may have changed meanwhile.
    final cached = [
      tournamentProvider(tournamentId),
      bracketProvider(tournamentId),
      organizerEntriesProvider(tournamentId),
    ].where(ref.exists).toList();
    if (cached.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final provider in cached) {
        ref.invalidate(provider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    // The previous account's tournament is not shown.
    final title = currentData(ref.watch(tournamentProvider(tournamentId)))?.title.resolve(context.lang);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        key: const ValueKey('tournament-manage-screen'),
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/tournaments/$tournamentId'),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.manageTournament, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (title != null && title.isNotEmpty)
                Text(title, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
          bottom: TabBar(
            tabs: [
              Tab(key: const ValueKey('manage-tab-draw'), text: l.drawTitle),
              Tab(key: const ValueKey('manage-tab-schedule'), text: l.manageSchedule),
              Tab(key: const ValueKey('manage-tab-scores'), text: l.manageScores),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            DrawTab(tournamentId: tournamentId),
            ScheduleTab(tournamentId: tournamentId),
            ScoresTab(tournamentId: tournamentId),
          ],
        ),
      ),
    );
  }
}
