import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/tournaments.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/admin_providers.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../tournaments/tournament_tools.dart';
import 'admin_common.dart';

/// Every tournament, active or not (product spec §12): filter by date, sport
/// and city, sort by date or A–Z. Opens the editor.
class AdminTournamentsScreen extends StatelessWidget {
  const AdminTournamentsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      AdminScaffold(title: context.l.adminTournaments, fallback: '/admin', body: (_) => const _TournamentList());
}

/// Runs an admin tournament write and refreshes everything that shows
/// tournaments, also after a refusal (it usually means the screen was out of
/// date). Returns the translated refusal, or `null` when it went through.
Future<String?> runAdminTournamentWrite(WidgetRef ref, AppLocalizations l, Future<void> Function() action) async {
  String? failure;
  try {
    await action();
  } on TournamentException catch (e) {
    failure = tournamentErrorText(l, e);
  }
  refreshAdmin(ref);
  return failure;
}

class _TournamentList extends ConsumerStatefulWidget {
  const _TournamentList();

  @override
  ConsumerState<_TournamentList> createState() => _TournamentListState();
}

class _TournamentListState extends ConsumerState<_TournamentList> {
  String? _sportId;
  String? _cityId;

  /// Hides tournaments that ended before this day.
  DateTime? _from;
  bool _az = false;

  Future<void> _pickSport() async {
    final l = context.l;
    final sports = ref.read(adminSportsProvider).valueOrNull ?? const [];
    final picked = await showOptionSheet(
      context,
      title: l.filterSport,
      options: {'': l.allSports, for (final s in sports) s.sport.id: s.sport.name.resolve(context.lang)},
      current: _sportId ?? '',
    );
    if (picked != null) setState(() => _sportId = picked.isEmpty ? null : picked);
  }

  Future<void> _pickCity() async {
    final l = context.l;
    final picked = await showOptionSheet(
      context,
      title: l.city,
      options: {'': l.allCities, for (final c in kCities) c.id: c.name.resolve(context.lang)},
      current: _cityId ?? '',
    );
    if (picked != null) setState(() => _cityId = picked.isEmpty ? null : picked);
  }

  Future<void> _pickDate() async {
    final today = dateOnly(ref.read(cityNowProvider)());
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? today,
      firstDate: today.subtract(const Duration(days: 730)),
      lastDate: today.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _from = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final lang = context.lang;
    final now = ref.watch(cityNowProvider)();
    final sports = ref.watch(adminSportsProvider).valueOrNull ?? const [];
    final sportName = sports.where((s) => s.sport.id == _sportId).firstOrNull?.sport.name.resolve(lang);
    final all = ref.watch(adminTournamentsProvider);

    return AdminListView(
      bottom: 24,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey('add-tournament'),
            style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => context.push('/admin/tournaments/new'),
            icon: const Icon(Icons.add_rounded),
            label: Text(l.addTournament),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              FilterChipButton(
                key: const ValueKey('admin-tournaments-sport'),
                label: sportName ?? l.filterSport,
                selected: _sportId != null,
                dropdown: true,
                onTap: _pickSport,
              ),
              FilterChipButton(
                key: const ValueKey('admin-tournaments-city'),
                icon: Icons.place_outlined,
                label: _cityId == null ? l.city : cityById(_cityId!).name.resolve(lang),
                selected: _cityId != null,
                dropdown: true,
                onTap: _pickCity,
              ),
              FilterChipButton(
                key: const ValueKey('admin-tournaments-date'),
                icon: Icons.event_outlined,
                label: _from == null ? l.tournamentFilterDate : l.tournamentFilterFrom(dayLabel(l, lang, _from!, now)),
                selected: _from != null,
                onTap: _pickDate,
              ),
              if (_from != null)
                FilterChipButton(
                  key: const ValueKey('admin-tournaments-date-clear'),
                  icon: Icons.close_rounded,
                  onTap: () => setState(() => _from = null),
                ),
              FilterChipButton(
                key: const ValueKey('admin-tournaments-sort-az'),
                icon: Icons.sort_by_alpha_rounded,
                label: l.tournamentSortAz,
                selected: _az,
                onTap: () => setState(() => _az = !_az),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (all.valueOrNull == null)
          AsyncBody(value: all, builder: (_) => const SizedBox.shrink())
        else
          ..._rows(context, all.requireValue),
      ],
    );
  }

  List<Widget> _rows(BuildContext context, List<AdminTournament> all) {
    final lang = context.lang;
    final rows = all.where((a) {
      final t = a.tournament;
      return (_sportId == null || t.sportId == _sportId) &&
          (_cityId == null || t.cityId == _cityId) &&
          (_from == null || !t.end.isBefore(_from!));
    }).toList();
    if (_az) {
      rows.sort((a, b) => a.tournament.title.resolve(lang).toLowerCase().compareTo(b.tournament.title.resolve(lang).toLowerCase()));
    }
    if (rows.isEmpty) return [EmptyState(icon: Icons.emoji_events_outlined, text: context.l.noAdminTournaments)];
    return [for (final row in rows) ...[_TournamentCard(admin: row), const SizedBox(height: 12)]];
  }
}

class _TournamentCard extends ConsumerWidget {
  const _TournamentCard({required this.admin});

  final AdminTournament admin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final t = admin.tournament;
    final now = tournamentNow(ref, t.cityId);
    final sport = ref.watch(adminSportsProvider).valueOrNull?.where((s) => s.sport.id == t.sportId).firstOrNull;
    final place = [?sport?.sport.name.resolve(context.lang), cityById(t.cityId).name.resolve(context.lang)].join(' · ');

    return Card(
      child: InkWell(
        key: ValueKey('admin-tournament-${t.id}'),
        onTap: () => context.push('/admin/tournaments/${t.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              TournamentCover(id: t.id, sportId: t.sportId, coverUrl: t.coverUrl, colorSeed: t.colorSeed, width: 72, height: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title.resolve(context.lang), style: AppText.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(place, style: AppText.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(tournamentDates(l, context.lang, t, now), style: AppText.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      l.tournamentCounts(admin.categoryCount, admin.registrationCount),
                      style: AppText.muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!t.active) ...[const SizedBox(height: 8), const InactivePill()],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
            ],
          ),
        ),
      ),
    );
  }
}
