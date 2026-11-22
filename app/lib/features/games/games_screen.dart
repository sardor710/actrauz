import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'game_card.dart';

class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.homeGames)),
      body: AsyncBody(
        value: ref.watch(gamesProvider),
        builder: (games) => games.isEmpty
            ? Center(child: EmptyState(icon: Icons.groups_outlined, text: l.noGames))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: games.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => GameCard(game: games[i]),
              ),
      ),
    );
  }
}
