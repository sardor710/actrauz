import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../onboarding/onboarding_screen.dart';

/// Name, bookings, and the language and city settings.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _pick(
    BuildContext context, {
    required String title,
    required Map<String, String> options,
    required String? current,
    required Future<void> Function(String) onPicked,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      // Above the bottom navigation, not behind it.
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            for (final option in options.entries)
              ListTile(
                title: Text(option.value),
                trailing: option.key == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(option.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) await onPicked(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final controller = ref.read(sessionProvider.notifier);
    final city = ref.watch(currentCityProvider);
    final name = session.userName ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(l.tabProfile)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  child: Text(
                    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.event_available_outlined),
            title: Text(l.myBookings),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/profile/bookings'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l.language),
            subtitle: Text(kLanguageNames[context.lang] ?? ''),
            onTap: () => _pick(
              context,
              title: l.language,
              options: kLanguageNames,
              current: context.lang,
              onPicked: controller.setLanguage,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(l.city),
            subtitle: Text(city.name.resolve(context.lang)),
            onTap: () => _pick(
              context,
              title: l.city,
              options: {for (final c in kCities) c.id: c.name.resolve(context.lang)},
              current: city.id,
              onPicked: controller.setCity,
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(l.signOut, style: TextStyle(color: theme.colorScheme.error)),
            onTap: controller.signOut,
          ),
        ],
      ),
    );
  }
}
