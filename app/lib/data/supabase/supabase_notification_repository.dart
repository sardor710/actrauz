import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/community.dart';
import '../repositories.dart';
import 'mappers.dart';

/// The inbox and community settings through the database functions. The
/// database stores no sentence: the app renders each entry from its kind.
class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(this._client);

  final SupabaseClient _client;

  /// How many entries one page holds.
  static const pageSize = 50;

  @override
  Future<List<AppNotification>> inbox({DateTime? before}) async {
    final rows = await _client.rpc(
      'my_notifications',
      params: {'p_limit': pageSize, 'p_before': before?.toUtc().toIso8601String()},
    );
    return [for (final row in rows as List) notificationFromJson(Map<String, dynamic>.from(row as Map))];
  }

  @override
  Future<int> unreadCount() async => (await _client.rpc('unread_notification_count')) as int;

  @override
  Future<void> markRead([List<String>? ids]) async {
    await _client.rpc('mark_notifications_read', params: {'p_ids': ids});
  }

  @override
  Future<CommunitySettings> settings() async {
    final json = await _client.rpc('my_settings');
    return communitySettingsFromJson(Map<String, dynamic>.from(json as Map));
  }

  @override
  Future<void> saveSettings(CommunitySettings settings) async {
    await _client.rpc(
      'set_settings',
      params: {'p_muted': settings.mutedCategories.toList()..sort(), 'p_hidden': settings.hiddenFromSearch},
    );
  }
}
