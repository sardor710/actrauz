import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../data/sample/sample_media.dart';
import '../../state/providers.dart';
import 'formatters.dart';
import 'widgets.dart';

/// Lets the player switch city from anywhere.
Future<void> showCityPicker(BuildContext context, WidgetRef ref) async {
  final picked = await showOptionSheet(
    context,
    title: context.l.city,
    options: {for (final c in kCities) c.id: c.name.resolve(context.lang)},
    current: ref.read(currentCityProvider).id,
  );
  if (picked != null) await ref.read(sessionProvider.notifier).setCity(picked);
}

/// Top of every tab: avatar (opens the profile), greeting, city switcher,
/// notifications and the shortcut to My bookings.
class AppHeader extends ConsumerWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final name = ref.watch(sessionProvider.select((s) => s.userName)) ?? '';
    final city = ref.watch(currentCityProvider);
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: l.tabProfile,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.push('/profile'),
              child: InitialAvatar(name: name, size: 46),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        l.greeting(name),
                        style: AppText.greeting,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Image.asset(kWaveIcon, width: 22, height: 22, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  ],
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => showCityPicker(context, ref),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            city.name.resolve(context.lang),
                            style: AppText.muted,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down, size: 20, color: AppColors.muted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('inbox-bell'),
            tooltip: l.notificationsTitle,
            onPressed: () => context.push('/inbox'),
            icon: unread > 0
                ? Badge(label: Text('$unread'), child: const Icon(Icons.notifications_none_rounded, size: 26))
                : const Icon(Icons.notifications_none_rounded, size: 26),
          ),
          IconButton(
            tooltip: l.myBookings,
            onPressed: () => context.push('/bookings'),
            icon: const Icon(Icons.calendar_month_outlined, size: 25),
          ),
        ],
      ),
    );
  }
}
