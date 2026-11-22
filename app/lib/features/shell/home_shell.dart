import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../common/formatters.dart';

/// Bottom navigation around the five main sections.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
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
