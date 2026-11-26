import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../domain/admin.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/admin_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'admin_common.dart';

/// Every admin and owner change, newest first (product spec §12.7): who,
/// what, which entity, when; tap an entry for its before and after values.
class AdminAuditScreen extends StatelessWidget {
  const AdminAuditScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      AdminScaffold(title: context.l.adminAudit, fallback: '/admin', body: (_) => const _AuditList());
}

/// Entries per page, as [adminAuditProvider] loads them.
const _pageSize = 50;

/// A readable label for an audit action, or the action itself if unknown.
String auditActionText(AppLocalizations l, AuditEntry entry) {
  var action = entry.action;
  for (final prefix in ['admin_', 'owner_']) {
    if (action.startsWith(prefix)) action = action.substring(prefix.length);
  }
  // "save_venue" covers both creating and updating.
  if (action.startsWith('save_')) action = '${entry.before == null ? 'create' : 'update'}_${action.substring(5)}';
  if (action == 'set_owner') action = entry.after?['assigned'] == false ? 'remove_owner' : 'assign_owner';
  return switch (action) {
    'create_venue' => l.auditCreateVenue,
    'update_venue' => l.auditUpdateVenue,
    'delete_venue' => l.auditDeleteVenue,
    'create_court' => l.auditCreateCourt,
    'update_court' => l.auditUpdateCourt,
    'duplicate_court' => l.auditDuplicateCourt,
    'delete_court' => l.auditDeleteCourt,
    'assign_owner' => l.auditAssignOwner,
    'remove_owner' => l.auditRemoveOwner,
    'create_sport' => l.auditCreateSport,
    'update_sport' => l.auditUpdateSport,
    'create_banner' => l.auditCreateBanner,
    'update_banner' => l.auditUpdateBanner,
    'delete_banner' => l.auditDeleteBanner,
    'set_venue_hours' => l.auditVenueHours,
    'set_court_hours' => l.auditCourtHours,
    'set_court_pricing' => l.auditCourtPricing,
    'create_walk_in' => l.auditWalkIn,
    'block_slots' => l.auditBlock,
    'cancel_booking' => l.bookingCancelled,
    'mark_booking' => l.auditMarkBooking,
    _ => entry.action,
  };
}

String _entityText(AppLocalizations l, String entity) => switch (entity) {
  'venue' => l.entityVenue,
  'court' => l.courtLabel,
  'sport' => l.filterSport,
  'banner' => l.entityBanner,
  'booking' => l.entityBooking,
  'venue_owner' || 'owner' => l.entityOwner,
  _ => entity,
};

/// The entity's name in the app language from its recorded values, or its id.
String? _entityName(AuditEntry entry, String lang) {
  final values = entry.after ?? entry.before;
  if (values != null) {
    for (final field in ['name', 'title']) {
      for (final code in [lang, 'ru', 'en', 'uz', 'kk']) {
        final value = values['${field}_$code'];
        if (value is String && value.trim().isNotEmpty) return value;
      }
    }
  }
  return entry.entityId;
}

class _AuditList extends ConsumerStatefulWidget {
  const _AuditList();

  @override
  ConsumerState<_AuditList> createState() => _AuditListState();
}

class _AuditListState extends ConsumerState<_AuditList> {
  /// Pages loaded with "Load more", after the first one.
  final _more = <AuditEntry>[];
  bool _exhausted = false;
  bool _loading = false;
  final _expanded = <String>{};

  Future<void> _loadMore(List<AuditEntry> shown) async {
    setState(() => _loading = true);
    try {
      final page = await ref.read(adminRepositoryProvider).auditLog(limit: _pageSize, before: shown.last.at);
      if (!mounted) return;
      setState(() {
        final seen = {for (final e in shown) e.id};
        _more.addAll(page.where((e) => !seen.contains(e.id)));
        _exhausted = page.length < _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showMessage(context, bookingErrorText(context.l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    // A refresh starts again from the newest entries.
    ref.listen(adminAuditProvider, (_, _) {
      _more.clear();
      _exhausted = false;
    });

    return AsyncBody(
      value: ref.watch(adminAuditProvider),
      builder: (first) {
        if (first.isEmpty) return Center(child: EmptyState(icon: Icons.history_rounded, text: l.auditEmpty));
        final entries = [...first, ..._more];
        // A short page means there is nothing older.
        final canLoadMore = !_exhausted && (_more.isNotEmpty || first.length >= _pageSize);
        return AdminListView(
          bottom: 24,
          children: [
            for (final entry in entries) ...[
              _EntryCard(
                entry: entry,
                expanded: _expanded.contains(entry.id),
                onTap: () => setState(() => _expanded.contains(entry.id) ? _expanded.remove(entry.id) : _expanded.add(entry.id)),
              ),
              const SizedBox(height: 10),
            ],
            if (canLoadMore)
              Center(
                child: OutlinedButton(
                  key: const ValueKey('audit-more'),
                  onPressed: _loading ? null : () => _loadMore(entries),
                  child: Text(l.loadMore),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.expanded, required this.onTap});

  final AuditEntry entry;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final actor = (entry.actorName == null || entry.actorName!.trim().isEmpty) ? l.auditSystem : entry.actorName!;
    final name = _entityName(entry, context.lang);
    final what = [_entityText(l, entry.entity), if (name != null && name.isNotEmpty) name].join(' · ');
    final when = DateFormat('d MMM y, HH:mm', context.lang).format(entry.at.toLocal());

    return Card(
      child: InkWell(
        key: ValueKey('audit-${entry.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InitialAvatar(name: actor, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(auditActionText(l, entry), style: AppText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(what, style: AppText.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('$actor · $when', style: AppText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: AppColors.faint,
                  ),
                ],
              ),
              if (expanded) ...[
                if (entry.before != null) _Values(label: l.auditBefore, values: entry.before!),
                if (entry.after != null) _Values(label: l.auditAfter, values: entry.after!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One side of a change as indented JSON.
class _Values extends StatelessWidget {
  const _Values({required this.label, required this.values});

  final String label;
  final Map<String, dynamic> values;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label.toUpperCase(), style: AppText.sectionTitle),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.page, borderRadius: BorderRadius.circular(12)),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(values),
            style: manrope(12.5, 500, height: 1.45),
          ),
        ),
      ],
    ),
  );
}
