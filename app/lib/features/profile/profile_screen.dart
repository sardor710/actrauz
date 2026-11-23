import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/sample/sample_data.dart';
import '../../domain/booking_engine.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../state/admin_providers.dart';
import '../../state/owner_providers.dart';
import '../../state/providers.dart';
import '../common/app_header.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../onboarding/onboarding_screen.dart';

/// The player's card, their sports, and the settings menu.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final session = ref.watch(sessionProvider);
    final controller = ref.read(sessionProvider.notifier);
    final city = ref.watch(currentCityProvider);
    final name = session.userName ?? '';
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final me = ref.watch(playerProvider(kMeId)).valueOrNull;

    final bookings = ref.watch(myBookingsProvider).valueOrNull ?? const <Booking>[];
    final games = ref.watch(gamesProvider).valueOrNull ?? const <Game>[];
    final booked = bookings.where((b) => b.status != BookingStatus.cancelledByPlayer).length;
    final joined = games.where((g) => g.participantIds.contains(kMeId)).length;
    final late = bookings.where((b) => b.lateCancellation).length;
    // Shown only to people who manage at least one venue.
    final managesVenues = (ref.watch(myVenuesProvider).valueOrNull ?? const <Venue>[]).isNotEmpty;
    // Shown only to Actra admins.
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text(l.tabProfile),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InitialAvatar(name: name, size: 76),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Stat(value: '$booked', label: l.statBookings),
                      ),
                      Expanded(
                        child: _Stat(value: '$joined', label: l.statGames),
                      ),
                      Expanded(
                        child: _Stat(value: '$late', label: l.statLate),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(name, style: AppText.title),
                  const SizedBox(height: 2),
                  Text(city.name.resolve(context.lang), style: AppText.muted.copyWith(fontSize: 15)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (me != null && sports.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.mySports.toUpperCase(), style: AppText.sectionTitle),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        children: [
                          for (final sport in sports)
                            Container(
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
                              // White with a border: pale icons such as the volleyball stay visible.
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                border: Border.all(color: AppColors.line),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SportBadge(sportId: sport.id, size: 26),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${sport.name.resolve(context.lang)} · ${l.level(me.levelFor(sport.id))}',
                                    style: manrope(13.5, 700),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Column(
              children: [
                if (managesVenues) ...[
                  _MenuRow(icon: Icons.stadium_outlined, title: l.myVenues, onTap: () => context.push('/owner')),
                  const Divider(indent: 60),
                ],
                if (isAdmin) ...[
                  _MenuRow(
                    icon: Icons.admin_panel_settings_outlined,
                    title: l.adminTitle,
                    onTap: () => context.push('/admin'),
                  ),
                  const Divider(indent: 60),
                ],
                _MenuRow(
                  icon: Icons.event_available_outlined,
                  title: l.myBookings,
                  onTap: () => context.push('/bookings'),
                ),
                const Divider(indent: 60),
                _MenuRow(
                  icon: Icons.language_rounded,
                  title: l.language,
                  value: kLanguageNames[context.lang],
                  onTap: () async {
                    final picked = await showOptionSheet(
                      context,
                      title: l.language,
                      options: kLanguageNames,
                      current: context.lang,
                    );
                    if (picked != null) await controller.setLanguage(picked);
                  },
                ),
                const Divider(indent: 60),
                _MenuRow(
                  icon: Icons.place_outlined,
                  title: l.city,
                  value: city.name.resolve(context.lang),
                  onTap: () => showCityPicker(context, ref),
                ),
                const Divider(indent: 60),
                _MenuRow(icon: Icons.logout_rounded, title: l.signOut, danger: true, onTap: controller.signOut),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: manrope(20, 800)),
      const SizedBox(height: 2),
      // Two lines reserved, so the numbers line up when one label wraps.
      SizedBox(
        height: 34,
        child: Text(
          label,
          style: AppText.caption,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.title, required this.onTap, this.value, this.danger = false});

  final IconData icon;
  final String title;
  final String? value;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.ink;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Text(title, style: manrope(15.5, 700, color: color)),
            ),
            if (value != null) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(value!, style: AppText.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
            ],
            if (!danger) const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}
