import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localized_text.dart';
import '../../core/theme.dart';
import '../../data/supabase/supabase_notification_repository.dart';
import '../../domain/community.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/rating_pill.dart' show formatRating;
import '../common/widgets.dart';

/// One sentence for [n], in the app language. The database stores none: it is
/// built from the kind and the payload (plan: Notifications).
String notificationText(AppLocalizations l, String lang, AppNotification n) {
  final p = n.payload;
  String name(String key, String fallback) {
    final value = p[key];
    if (value is! Map) return fallback;
    String? text(String code) => value[code] is String ? value[code] as String : null;
    final resolved = LocalizedText(uz: text('uz'), ru: text('ru'), kk: text('kk'), en: text('en')).resolve(lang);
    return resolved.isEmpty ? fallback : resolved;
  }

  final actorValue = p['actor_name'];
  final actor = actorValue is String && actorValue.isNotEmpty ? actorValue : l.notifSomeone;
  final venue = name('venue_name', l.notifVenueFallback);
  final court = name('court_name', l.notifCourtFallback);
  final tournament = name('title', l.notifTournamentFallback);
  final categoryName = name('category_name', '');
  final category = categoryName.isEmpty ? null : categoryName;
  // The team's name as it was when the notice was sent; without one a team
  // notice reads as the generic line.
  final teamValue = p['team_name'];
  final team = teamValue is String && teamValue.isNotEmpty ? teamValue : null;
  double? number(String key) {
    final value = p[key];
    return value is num ? value.toDouble() : null;
  }
  final oldRating = number('old');
  final newRating = number('new');
  return switch (n.kind) {
    'booking_confirmed' => l.notifBookingConfirmed(venue),
    'booking_cancelled_by_venue' => l.notifBookingCancelledByVenue(venue),
    'booking_reminder' => l.notifBookingReminder(venue),
    'venue_new_booking' => l.notifVenueNewBooking(actor, court),
    'venue_booking_cancelled' => l.notifVenueBookingCancelled(actor, court),
    'game_joined' => l.notifGameJoined(actor),
    'game_left' => l.notifGameLeft(actor),
    'join_request' => l.notifJoinRequest(actor),
    'join_approved' => l.notifJoinApproved,
    'join_declined' => l.notifJoinDeclined,
    'game_full' => l.notifGameFull,
    'game_changed' => l.notifGameChanged,
    'game_cancelled' => l.notifGameCancelled,
    'game_removed' => l.notifGameRemoved,
    'game_reminder' => l.notifGameReminder,
    'game_invite' => l.notifGameInvite(actor),
    'request_interest' => l.notifRequestInterest(actor),
    'request_converted' => p['added'] == false ? l.notifRequestConvertedFull : l.notifRequestConvertedIn,
    'request_expired' => l.notifRequestExpired,
    'game_finished' => p['can_score'] == true ? l.notifGameFinishedScore : l.notifGameFinishedRate,
    'score_entered' => l.notifScoreEntered,
    'score_disputed' => l.notifScoreDisputed,
    'score_resolved' => p['action'] == 'void' ? l.notifScoreVoided : l.notifScoreResolved,
    'no_show_recorded' => l.notifNoShowRecorded,
    'rating_updated' when oldRating != null && newRating != null => l.notifRatingUpdated(
      formatRating(oldRating),
      formatRating(newRating),
    ),
    'tournament_registered' => l.notifTournamentRegistered(tournament),
    'tournament_partner_invite' => l.notifTournamentPartnerInvite(actor, tournament),
    'tournament_partner_accepted' => l.notifTournamentPartnerAccepted(actor, tournament),
    'tournament_partner_declined' => l.notifTournamentPartnerDeclined(actor, tournament),
    'tournament_partner_cancelled' => l.notifTournamentPartnerCancelled(actor, tournament),
    'tournament_partner_expired' => l.notifTournamentPartnerExpired(tournament),
    'tournament_spot_offered' => l.notifTournamentSpotOffered(tournament),
    'tournament_deadline_reminder' => l.notifTournamentDeadlineReminder(tournament),
    'tournament_removed' => l.notifTournamentRemoved(tournament),
    'tournament_moved' => category == null
        ? l.notifTournamentMoved(tournament)
        : l.notifTournamentMovedTo(category, tournament),
    'team_invite' when team != null => l.notifTeamInvite(actor, team),
    'team_join_request' when team != null => l.notifTeamJoinRequest(actor, team),
    'team_join_approved' when team != null => l.notifTeamJoinApproved(team),
    'team_join_declined' when team != null => l.notifTeamJoinDeclined(team),
    'team_removed' when team != null => l.notifTeamRemoved(team),
    'team_captain' when team != null => l.notifTeamCaptain(team),
    'team_deleted' when team != null => l.notifTeamDeleted(team),
    _ => l.notifUnknown,
  };
}

IconData _categoryIcon(String category) => switch (category) {
  'bookings' => Icons.event_available_outlined,
  'venue' => Icons.stadium_outlined,
  'games' => Icons.sports_tennis_outlined,
  'requests' => Icons.campaign_outlined,
  'invites' => Icons.mail_outline_rounded,
  'tournaments' => Icons.emoji_events_outlined,
  'ratings' => Icons.bar_chart_rounded,
  'teams' => Icons.groups_outlined,
  _ => Icons.notifications_none_rounded,
};

/// Refreshes the bell and the list after entries are read or arrive.
void refreshInbox(WidgetRef ref) {
  ref.invalidate(inboxProvider);
  ref.invalidate(unreadCountProvider);
}

/// The player's notifications, newest first. Tapping one marks it read and
/// opens what it is about.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  static const _pageSize = SupabaseNotificationRepository.pageSize;

  /// Older pages loaded with "Load more", below the newest page.
  final List<AppNotification> _older = [];
  bool _exhausted = false;
  bool _loadingMore = false;
  /// Entries marked read on this screen, until the list reloads with it. By
  /// id, so "Mark all read" never covers a notification that arrives later.
  final Set<String> _readHere = {};

  AppNotification _shown(AppNotification n) => _readHere.contains(n.id) ? n.copyWith(read: true) : n;

  Future<void> _open(AppNotification n) async {
    final route = n.route;
    if (!n.read) {
      try {
        await ref.read(notificationRepositoryProvider).markRead([n.id]);
        _readHere.add(n.id);
        refreshInbox(ref);
      } catch (_) {
        // Opening what it is about matters more than the dot.
      }
    }
    if (route == null || !mounted) return;
    // Games and tournaments live inside the tabs, like everywhere else in the
    // app: go, not push (pushing a tab route from outside the tabs duplicates
    // its page).
    route.startsWith('/games') || route.startsWith('/tournaments') ? context.go(route) : context.push(route);
  }

  Future<void> _markAll(List<AppNotification> shown) async {
    try {
      await ref.read(notificationRepositoryProvider).markRead();
      if (mounted) setState(() => _readHere.addAll(shown.map((n) => n.id)));
      refreshInbox(ref);
    } catch (_) {
      if (mounted) showMessage(context, context.l.errGeneric);
    }
  }

  Future<void> _loadMore(List<AppNotification> all) async {
    setState(() => _loadingMore = true);
    try {
      final last = all.last;
      final page = await ref.read(notificationRepositoryProvider).inbox(before: last.createdAt, beforeId: last.id);
      if (!mounted) return;
      setState(() {
        _older.addAll(page);
        _exhausted = page.length < _pageSize;
      });
    } catch (_) {
      if (mounted) showMessage(context, context.l.errGeneric);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final inbox = ref.watch(inboxProvider);
    final newest = inbox.valueOrNull ?? const <AppNotification>[];
    final all = [
      for (final n in [...newest, ..._older]) _shown(n),
    ];
    final anyUnread = all.any((n) => !n.read);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text(l.notificationsTitle),
        actions: [
          TextButton(onPressed: anyUnread ? () => _markAll(all) : null, child: Text(l.markAllRead)),
          IconButton(
            tooltip: l.notificationSettings,
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: AsyncBody(
        value: inbox,
        builder: (_) {
          if (all.isEmpty) return EmptyState(icon: Icons.notifications_none_rounded, text: l.noNotifications);
          final canLoadMore = !_exhausted && (_older.isNotEmpty || newest.length >= _pageSize);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, n) in all.indexed) ...[
                      if (i > 0) const Divider(indent: 72, height: 1),
                      _NotificationRow(notification: n, onTap: () => _open(n)),
                    ],
                  ],
                ),
              ),
              if (canLoadMore)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: _loadingMore ? null : () => _loadMore(all),
                      child: Text(l.loadMore),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationRow extends ConsumerWidget {
  const _NotificationRow({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final n = notification;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const [];
    final sportId = n.payload['sport_id'];
    final sportName = sports.where((s) => s.id == sportId).firstOrNull?.name.resolve(context.lang);
    final start = DateTime.tryParse('${n.payload['starts_local'] ?? ''}');
    final now = ref.watch(cityNowProvider)();
    final details = [
      ?sportName,
      if (start != null) '${dayLabel(l, context.lang, start, now)}, ${hm(start)}',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: n.read ? AppColors.field : AppColors.primarySoft, shape: BoxShape.circle),
              child: Icon(
                _categoryIcon(n.category),
                size: 22,
                color: n.read ? AppColors.muted : AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notificationText(l, context.lang, n), style: n.read ? AppText.body : AppText.bodyStrong),
                  if (details.isNotEmpty) ...[const SizedBox(height: 2), Text(details, style: AppText.muted)],
                ],
              ),
            ),
            if (!n.read) ...[
              const SizedBox(width: 10),
              Container(
                key: const ValueKey('unread-dot'),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
