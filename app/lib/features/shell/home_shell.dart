import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/competitive.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';

/// Shared preference: the one-time "Pick your sports" offer has been shown on
/// this device.
const kSportsPromptedPref = 'sports_prompted';

/// Bottom navigation around the five main sections. The first time it opens
/// for a player with no sports it offers "My sports" once (design §5.1); the
/// offer never blocks the app.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerSports());
  }

  /// Shows the offer once, and only when the player's sports have loaded and
  /// are empty. It counts as seen as soon as it is shown.
  Future<void> _offerSports() async {
    final prefs = ref.read(sharedPrefsProvider);
    if (prefs.getBool(kSportsPromptedPref) ?? false) return;
    final List<MySport> mine;
    try {
      mine = await ref.read(mySportsProvider.future);
    } catch (_) {
      // Not loaded (offline, signed out meanwhile): offer it another time.
      return;
    }
    if (mine.isNotEmpty || !mounted || (prefs.getBool(kSportsPromptedPref) ?? false)) return;
    await prefs.setBool(kSportsPromptedPref, true);
    if (!mounted) return;
    final choose = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => const _SportsPrompt(),
    );
    if (choose == true && mounted) context.push('/sports');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final shell = widget.shell;
    final items = [
      (Icons.home_rounded, l.tabHome),
      (Icons.directions_run_rounded, l.tabGames),
      (Icons.stadium_rounded, l.tabVenues),
      (Icons.emoji_events_rounded, l.tabTournaments),
      (Icons.groups_rounded, l.tabSocial),
    ];

    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _BarItem(
                      icon: items[i].$1,
                      label: items[i].$2,
                      selected: i == shell.currentIndex,
                      // Tapping the current tab again returns to its first screen.
                      onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Pick your sports": choose now (true) or not now.
class _SportsPrompt extends StatelessWidget {
  const _SportsPrompt();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.sportsPromptTitle, style: AppText.title),
            const SizedBox(height: 8),
            Text(l.sportsPromptText, style: AppText.muted.copyWith(fontSize: 15)),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.chooseSports)),
            const SizedBox(height: 4),
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.notNow)),
          ],
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: onTap,
        radius: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 27, color: color),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: manrope(11, selected ? 800 : 600, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
