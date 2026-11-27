import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'game_card.dart';

/// The player's games that ended in the last 30 days, the latest first; each
/// opens the game page with its "Game finished" section (design §5.8).
class PastGamesScreen extends ConsumerWidget {
  const PastGamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.pastGames)),
      body: AsyncBody(
        value: ref.watch(pastGamesProvider),
        builder: (games) => games.isEmpty
            ? Center(child: EmptyState(icon: Icons.history_rounded, text: l.noPastGames))
            : RefreshIndicator(
                // Pull to see scores other players entered meanwhile.
                onRefresh: () => reloadQuietly(ref.refresh(pastGamesProvider.future)),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    for (final game in games)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GameCard(game: game),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
