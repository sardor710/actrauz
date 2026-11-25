import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/community.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

String _categoryLabel(AppLocalizations l, String category) => switch (category) {
  'bookings' => l.notifCategoryBookings,
  'venue' => l.notifCategoryVenue,
  'games' => l.notifCategoryGames,
  'requests' => l.notifCategoryRequests,
  'invites' => l.notifCategoryInvites,
  'tournaments' => l.notifCategoryTournaments,
  _ => category,
};

/// Which notifications the player hears about, and whether other players can
/// find them.
class CommunitySettingsScreen extends ConsumerStatefulWidget {
  const CommunitySettingsScreen({super.key});

  @override
  ConsumerState<CommunitySettingsScreen> createState() => _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState extends ConsumerState<CommunitySettingsScreen> {
  /// What is on screen; null until the saved settings have loaded.
  CommunitySettings? _draft;
  CommunitySettings? _saved;
  bool _saving = false;

  bool get _changed {
    final draft = _draft;
    final saved = _saved;
    if (draft == null || saved == null) return false;
    return draft.hiddenFromSearch != saved.hiddenFromSearch ||
        draft.mutedCategories.length != saved.mutedCategories.length ||
        !draft.mutedCategories.containsAll(saved.mutedCategories);
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(notificationRepositoryProvider).saveSettings(draft);
      ref.invalidate(communitySettingsProvider);
      if (!mounted) return;
      setState(() => _saved = draft);
      showMessage(context, context.l.savedMsg);
    } catch (_) {
      if (mounted) showMessage(context, context.l.errGeneric);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final loaded = ref.watch(communitySettingsProvider);
    if (_draft == null && loaded.hasValue) {
      _draft = _saved = loaded.requireValue;
    }
    final draft = _draft;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/profile')),
        title: Text(l.notificationsAndPrivacy),
      ),
      body: draft == null
          ? AsyncBody<CommunitySettings>(value: loaded, builder: (_) => const SizedBox.shrink())
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              children: [
                SectionCard(
                  title: l.notificationsTitle,
                  contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.notificationsMuteHint, style: AppText.muted),
                      const SizedBox(height: 4),
                      for (final category in kNotificationCategories)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_categoryLabel(l, category), style: AppText.bodyStrong),
                          value: !draft.mutedCategories.contains(category),
                          onChanged: (on) => setState(() {
                            final muted = {...draft.mutedCategories};
                            on ? muted.remove(category) : muted.add(category);
                            _draft = draft.copyWith(mutedCategories: muted);
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: l.privacyTitle,
                  contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.hideFromSearch, style: AppText.bodyStrong),
                    subtitle: Text(l.hideFromSearchHint, style: AppText.muted),
                    value: draft.hiddenFromSearch,
                    onChanged: (on) => setState(() => _draft = draft.copyWith(hiddenFromSearch: on)),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton(onPressed: _changed && !_saving ? _save : null, child: Text(l.saveLabel)),
                ),
              ],
            ),
    );
  }
}
