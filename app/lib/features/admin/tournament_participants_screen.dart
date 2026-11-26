import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/tournaments.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/admin_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../tournaments/tournament_tools.dart';
import 'admin_common.dart';
import 'owners_sheet.dart';

/// Who is in a tournament, category by category: payment, removing, moving,
/// adding players, offering the waitlist's next spot, and the CSV of the list
/// (product spec §10.1, §14). Admins see phone numbers here and nowhere else.
class TournamentParticipantsScreen extends StatelessWidget {
  const TournamentParticipantsScreen({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context) => AdminScaffold(
    title: context.l.participantsLabel,
    fallback: '/admin/tournaments/$tournamentId',
    body: (_) => _Participants(tournamentId: tournamentId),
  );
}

class _Participants extends ConsumerWidget {
  const _Participants({required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = ref.watch(adminTournamentsProvider);
    final entries = ref.watch(adminRegistrationsProvider(tournamentId));
    // A reload after a change keeps the list on screen.
    final tournament = tournaments.valueOrNull?.where((a) => a.tournament.id == tournamentId).firstOrNull?.tournament;
    final list = entries.valueOrNull;
    if (tournament == null || list == null) {
      return AsyncBody(
        value: tournaments.hasError ? tournaments : entries,
        builder: (_) => Center(child: EmptyState(icon: Icons.search_off_rounded, text: context.l.errNotFound)),
      );
    }

    return AdminListView(
      bottom: 24,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(tournament.title.resolve(context.lang), style: AppText.title),
        ),
        for (final category in tournament.categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CategorySection(
              category: category,
              cityId: tournament.cityId,
              siblings: tournament.categories,
              entries: [for (final e in list) if (e.registration.categoryId == category.id) e],
            ),
          ),
      ],
    );
  }
}

class _CategorySection extends ConsumerWidget {
  const _CategorySection({required this.category, required this.cityId, required this.siblings, required this.entries});

  final TournamentCategory category;

  /// The tournament's city: the CSV shows its local time.
  final String cityId;
  final List<TournamentCategory> siblings;
  final List<AdminRegistration> entries;

  Future<bool> _write(BuildContext context, WidgetRef ref, Future<void> Function() action, {bool quiet = false}) async {
    final l = context.l;
    String? failure;
    try {
      await action();
    } on TournamentException catch (e) {
      failure = tournamentErrorText(l, e);
    }
    refreshAdmin(ref);
    if (!context.mounted) return failure == null;
    if (failure != null) {
      showMessage(context, failure);
    } else if (!quiet) {
      showMessage(context, l.savedMsg);
    }
    return failure == null;
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final repo = ref.read(adminRepositoryProvider);
    final taken = <String>{
      for (final e in entries)
        if (e.registration.status.live) ...[e.registration.registrant.id, ?e.registration.partner?.id],
    };
    final player = await showOwnerSearch(context, exclude: taken, title: l.addPlayer);
    if (player == null || !context.mounted) return;
    String? partnerId;
    if (category.kind == CategoryKind.pairs) {
      final partner = await showOwnerSearch(context, exclude: {...taken, player.userId}, title: l.partnerTitle);
      if (partner == null || !context.mounted) return;
      partnerId = partner.userId;
    }
    await _write(context, ref, () => repo.addRegistration(category.id, player.userId, partnerId: partnerId));
  }

  Future<void> _offerNext(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final repo = ref.read(adminRepositoryProvider);
    var offered = 0;
    final ok = await _write(context, ref, () async => offered = await repo.offerNext(category.id), quiet: true);
    if (ok && context.mounted) showMessage(context, l.offerNextResult(offered));
  }

  Future<void> _copyCsv(BuildContext context) async {
    final csv = registrationsCsv(
      [for (final e in entries) if (e.registration.status.live) e],
      context.lang,
      utcOffsetMinutes: cityById(cityId).utcOffsetMinutes,
    );
    await Clipboard.setData(ClipboardData(text: csv));
    if (context.mounted) showMessage(context, context.l.csvCopied);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final live = [for (final e in entries) if (e.registration.status.live) e];
    final past = [for (final e in entries) if (!e.registration.status.live) e];

    return Card(
      key: ValueKey('participants-${category.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(category.name.resolve(context.lang), style: AppText.cardTitle),
            const SizedBox(height: 2),
            Text(
              [
                categoryKindLabel(l, category.kind),
                categoryGenderLabel(l, category.gender),
                l.levelRange(category.minLevel, category.maxLevel),
                l.filledOf(category.filled, category.cap),
                if (category.waitlistCount > 0) l.waitlistCount(category.waitlistCount),
              ].join(' · '),
              style: AppText.muted,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('add-player-${category.id}'),
                  onPressed: () => _add(context, ref),
                  icon: const Icon(Icons.person_add_alt_rounded),
                  label: Text(l.addPlayer),
                ),
                if (category.waitlistEnabled)
                  OutlinedButton.icon(
                    key: ValueKey('offer-next-${category.id}'),
                    onPressed: () => _offerNext(context, ref),
                    icon: const Icon(Icons.campaign_outlined),
                    label: Text(l.offerNext),
                  ),
                OutlinedButton.icon(
                  key: ValueKey('copy-csv-${category.id}'),
                  onPressed: () => _copyCsv(context),
                  icon: const Icon(Icons.copy_all_rounded),
                  label: Text(l.copyCsv),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(l.addPlayerNote, style: AppText.caption),
            const Divider(height: 24),
            if (live.isEmpty) Text(l.noEntriesYet, style: AppText.muted),
            for (final e in live)
              _EntryRow(
                entry: e,
                moveTargets: [
                  for (final c in siblings)
                    if (c.id != category.id && c.kind == category.kind) c,
                ],
                write: (action, {bool quiet = false}) => _write(context, ref, action, quiet: quiet),
              ),
            if (past.isNotEmpty)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: ValueKey('past-${category.id}'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(l.pastEntries(past.length), style: AppText.muted),
                  children: [for (final e in past) _PastRow(entry: e)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A player on an entry: "Deleted player" once their account is gone.
String _player(AppLocalizations l, PlayerRef p) => playerName(l, p.name, deleted: p.deleted);

String _names(AppLocalizations l, AdminRegistration e) {
  final r = e.registration;
  return r.partner == null ? _player(l, r.registrant) : '${_player(l, r.registrant)} + ${_player(l, r.partner!)}';
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.entry, required this.moveTargets, required this.write});

  final AdminRegistration entry;
  final List<TournamentCategory> moveTargets;
  final Future<bool> Function(Future<void> Function() action, {bool quiet}) write;

  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final repo = ref.read(adminRepositoryProvider);
    final id = entry.registration.id;
    final picked = await showOptionSheet(
      context,
      title: l.moveRegistration,
      options: {for (final c in moveTargets) c.id: '${c.name.resolve(context.lang)} · ${l.filledOf(c.filled, c.cap)}'},
    );
    if (picked == null || !context.mounted) return;
    await write(() => repo.moveRegistration(id, picked));
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final repo = ref.read(adminRepositoryProvider);
    final r = entry.registration;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.removePlayerTitle(_names(l, entry))),
        content: Text(l.removePlayerMsg),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.removeLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await write(() => repo.removeRegistration(r.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final r = entry.registration;
    final registered = r.status == RegistrationStatus.registered;
    final phones = [entry.registrantPhone, entry.partnerPhone].whereType<String>().join(' · ');
    final place = r.status == RegistrationStatus.waitlisted ? r.waitlistPlace : null;

    return Padding(
      key: ValueKey('registration-${r.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_player(l, r.registrant), style: AppText.bodyStrong),
                if (r.partner != null) Text(l.pairedWith(_player(l, r.partner!)), style: AppText.body),
                if (phones.isNotEmpty) Text(phones, style: AppText.muted),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RegistrationStatusPill(registration: r),
                    Text(feeText(l, r.fee, r.currency), style: AppText.muted),
                    if (place != null) Text(l.waitlistPlaceLabel(place), style: AppText.muted),
                  ],
                ),
              ],
            ),
          ),
          if (registered)
            Column(
              children: [
                Text(l.paidLabel, style: AppText.caption),
                Switch(
                  key: ValueKey('paid-${r.id}'),
                  value: r.paid,
                  onChanged: (value) => write(() => ref.read(adminRepositoryProvider).setPaid(r.id, value), quiet: true),
                ),
              ],
            ),
          PopupMenuButton<String>(
            key: ValueKey('reg-menu-${r.id}'),
            onSelected: (action) => action == 'move' ? _move(context, ref) : _remove(context, ref),
            itemBuilder: (context) => [
              // Only a registered entry can move to another category.
              if (registered && moveTargets.isNotEmpty)
                PopupMenuItem(key: ValueKey('move-${r.id}'), value: 'move', child: Text(l.moveRegistration)),
              PopupMenuItem(key: ValueKey('remove-${r.id}'), value: 'remove', child: Text(l.removeEntry)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PastRow extends StatelessWidget {
  const _PastRow({required this.entry});

  final AdminRegistration entry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(_names(context.l, entry), style: AppText.body)),
        RegistrationStatusPill(registration: entry.registration),
      ],
    ),
  );
}

const kCsvHeader = 'category,status,registrant_name,registrant_phone,partner_name,partner_phone,fee,currency,paid,created';

String _statusCode(RegistrationStatus s) => switch (s) {
  RegistrationStatus.pendingPartner => 'pending_partner',
  _ => s.name,
};

/// One cell. Quoted when it holds a comma, a quote or a line break; a text
/// that a spreadsheet would run as a formula gets a leading apostrophe.
String _cell(String value, {bool text = true}) {
  var v = value;
  if (text && v.isNotEmpty && '=+-@\t\r'.contains(v[0])) v = "'$v";
  if (v.contains(RegExp('[",\n\r]'))) v = '"${v.replaceAll('"', '""')}"';
  return v;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// The category's entries as CSV: [kCsvHeader] and one line per entry.
/// Phones are in it: only admins ever see this list. `created` is the
/// tournament city's wall-clock time ([utcOffsetMinutes] from UTC).
String registrationsCsv(List<AdminRegistration> entries, String lang, {required int utcOffsetMinutes}) {
  final l = lookupAppLocalizations(Locale(lang));
  final lines = [kCsvHeader];
  for (final e in entries) {
    final r = e.registration;
    final c = r.createdAt.toUtc().add(Duration(minutes: utcOffsetMinutes));
    lines.add(
      [
        _cell(r.categoryName.resolve(lang)),
        _statusCode(r.status),
        _cell(_player(l, r.registrant)),
        _cell(e.registrantPhone ?? '', text: false),
        _cell(r.partner == null ? '' : _player(l, r.partner!)),
        _cell(e.partnerPhone ?? '', text: false),
        '${r.fee}',
        r.currency.name.toUpperCase(),
        r.paid ? 'yes' : 'no',
        '${c.year}-${_two(c.month)}-${_two(c.day)} ${_two(c.hour)}:${_two(c.minute)}',
      ].join(','),
    );
  }
  return '${lines.join('\n')}\n';
}
