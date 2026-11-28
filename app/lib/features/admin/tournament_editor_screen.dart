import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/tournaments.dart';
import '../../state/admin_providers.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../tournaments/register_sheet.dart';
import '../tournaments/tournament_tools.dart';
import 'admin_common.dart';
import 'admin_tournaments_screen.dart';
import 'category_sheet.dart';
import 'localized_field.dart';

/// The days a date picker offers: from [first] (default a year before
/// [today]) to two years after [today], widened to take in [initial] so that
/// editing an old tournament never opens the picker outside its own range.
({DateTime first, DateTime last}) pickerRange(DateTime initial, DateTime today, {DateTime? first}) {
  final from = first ?? today.subtract(const Duration(days: 365));
  final to = today.add(const Duration(days: 365 * 2));
  return (first: initial.isBefore(from) ? initial : from, last: initial.isAfter(to) ? initial : to);
}

/// Creates or edits a tournament and its categories (product spec §10.1).
/// A new tournament collects its categories in the form and saves them
/// together; an existing one saves each category on its own.
class TournamentEditorScreen extends ConsumerStatefulWidget {
  const TournamentEditorScreen({super.key, this.tournamentId});

  /// `null` for a new tournament.
  final String? tournamentId;

  @override
  ConsumerState<TournamentEditorScreen> createState() => _TournamentEditorScreenState();
}

class _TournamentEditorScreenState extends ConsumerState<TournamentEditorScreen> {
  final _form = GlobalKey<FormState>();
  late String? _tournamentId = widget.tournamentId;
  TournamentDraft? _draft;
  bool _saving = false;

  /// A new tournament's deadline follows its first day until it is picked.
  bool _deadlineChosen = false;
  final _cover = TextEditingController();

  @override
  void dispose() {
    _cover.dispose();
    super.dispose();
  }

  DateTime _today(String cityId) => dateOnly(venueNow(cityById(cityId), utcNow: ref.read(clockProvider)()));

  TournamentDraft _newDraft() {
    final city = ref.read(currentCityProvider);
    final start = _today(city.id).add(const Duration(days: 14));
    final sports = ref.read(adminSportsProvider).valueOrNull ?? const [];
    final sport = sports.where((s) => s.active).firstOrNull ?? sports.firstOrNull;
    return TournamentDraft(
      cityId: city.id,
      sportId: sport?.sport.id ?? 'padel',
      start: start,
      end: start,
      registrationDeadline: start,
    );
  }

  Future<DateTime?> _pickDay(DateTime initial, {DateTime? first}) {
    final range = pickerRange(initial, _today(_draft!.cityId), first: first);
    return showDatePicker(context: context, initialDate: initial, firstDate: range.first, lastDate: range.last);
  }

  Future<void> _pickStart() async {
    final draft = _draft!;
    final picked = await _pickDay(draft.start);
    if (picked == null) return;
    setState(() {
      draft.start = dateOnly(picked);
      if (draft.end.isBefore(draft.start)) draft.end = draft.start;
      if (widget.tournamentId == null && _tournamentId == null && !_deadlineChosen) {
        draft.registrationDeadline = draft.start;
      }
    });
  }

  Future<void> _pickEnd() async {
    final draft = _draft!;
    final picked = await _pickDay(draft.end, first: draft.start);
    if (picked != null) setState(() => draft.end = dateOnly(picked));
  }

  Future<void> _pickDeadline() async {
    final draft = _draft!;
    final current = draft.registrationDeadline ?? draft.start;
    final day = await _pickDay(current);
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay(hour: current.hour, minute: current.minute));
    if (!mounted) return;
    setState(() {
      _deadlineChosen = true;
      draft.registrationDeadline = DateTime.utc(day.year, day.month, day.day, time?.hour ?? current.hour, time?.minute ?? current.minute);
    });
  }

  Future<void> _save() async {
    final l = context.l;
    final draft = _draft!;
    if (!_form.currentState!.validate()) return;
    final cover = _cover.text.trim();
    if (cover.isNotEmpty && !cover.startsWith('https://')) return showMessage(context, l.errInvalidArgument);
    draft.coverUrl = cover.isEmpty ? null : cover;
    final creating = _tournamentId == null;
    if (creating && draft.categories.isEmpty) return showMessage(context, l.addCategoryFirst);

    setState(() => _saving = true);
    String? id;
    final error = await runAdminTournamentWrite(ref, l, () async => id = await ref.read(adminRepositoryProvider).saveTournament(draft));
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error == null && creating) {
        // From here on it is an existing tournament: reload it, so the next
        // save carries its stored deadline and cover.
        _tournamentId = id;
        _draft = null;
      }
    });
    showMessage(context, error ?? l.savedMsg);
  }

  Future<void> _editCategory({CategoryDraft? draft, int? localIndex, TournamentCategory? stored, required bool last}) async {
    final l = context.l;
    final repo = ref.read(adminRepositoryProvider);
    final tournament = _draft!;
    final persisted = _tournamentId != null;
    final initial = draft ?? CategoryDraft(tournamentId: _tournamentId);
    final saved = await showCategorySheet(
      context,
      initial: initial,
      filled: stored?.filled ?? 0,
      onSave: (result) async {
        if (!persisted) {
          setState(() {
            if (localIndex == null) {
              tournament.categories.add(result);
            } else {
              tournament.categories[localIndex] = result;
            }
          });
          return null;
        }
        return runAdminTournamentWrite(ref, l, () => repo.saveCategory(result));
      },
      onDelete: (initial.id == null && localIndex == null) || (persisted && last)
          ? null
          : () async {
              if (!persisted) {
                setState(() => tournament.categories.removeAt(localIndex!));
                return null;
              }
              return runAdminTournamentWrite(ref, l, () => repo.deleteCategory(initial.id!));
            },
    );
    if (saved == true && mounted && persisted) showMessage(context, l.savedMsg);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final tournaments = ref.watch(adminTournamentsProvider);
    final admin = _tournamentId == null
        ? null
        : tournaments.valueOrNull?.where((a) => a.tournament.id == _tournamentId).firstOrNull;

    if (_draft == null) {
      if (_tournamentId == null) {
        // The sports list decides the first sport; wait for it.
        if (ref.watch(adminSportsProvider).hasValue) _draft = _newDraft();
      } else if (admin != null) {
        _draft = TournamentDraft.from(admin.tournament);
        _cover.text = admin.tournament.coverUrl ?? '';
      }
    }
    final draft = _draft;
    final title = draft == null
        ? ''
        : _tournamentId == null
        ? l.newTournament
        : draft.title.resolve(context.lang);

    return AdminScaffold(
      title: title,
      fallback: '/admin/tournaments',
      actions: [
        if (_tournamentId != null)
          IconButton(
            key: const ValueKey('open-participants'),
            tooltip: l.participantsLabel,
            onPressed: () => context.push('/admin/tournaments/$_tournamentId/participants'),
            icon: const Icon(Icons.groups_outlined),
          ),
      ],
      body: (context) {
        if (draft == null) {
          // Editing a tournament that has not loaded, or no longer exists.
          return tournaments.hasValue && !tournaments.isLoading && _tournamentId != null
              ? Center(child: EmptyState(icon: Icons.search_off_rounded, text: l.errNotFound))
              : const Center(child: CircularProgressIndicator());
        }
        return Form(
          key: _form,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = adminGutter(constraints.maxWidth) - 16;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(side, 4, side, 24),
                child: Column(
                  children: [
                    _details(context, draft),
                    _categories(context, draft, admin),
                    if (_tournamentId case final id?) OrganizersCard(tournamentId: id, sportId: draft.sportId),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _dateField(BuildContext context, Key key, String label, String value, VoidCallback onTap) => InkWell(
    key: key,
    borderRadius: BorderRadius.circular(14),
    onTap: onTap,
    child: InputDecorator(
      decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.event_outlined)),
      child: Text(value, style: AppText.body),
    ),
  );

  Widget _details(BuildContext context, TournamentDraft draft) {
    final l = context.l;
    final lang = context.lang;
    final now = _today(draft.cityId);
    final sports = ref.watch(adminSportsProvider).valueOrNull ?? const [];
    final venues = (ref.watch(adminVenuesProvider).valueOrNull ?? const []).where((v) => v.venue.cityId == draft.cityId).toList();
    final venue = venues.where((v) => v.venue.id == draft.venueId).firstOrNull;
    final sportName = sports.where((s) => s.sport.id == draft.sportId).firstOrNull?.sport.name.resolve(lang) ?? draft.sportId;
    final deadline = draft.registrationDeadline ?? draft.start;

    return SectionCard(
      title: l.tournamentDetails,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(l.city),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChipButton(
              key: const ValueKey('tournament-city'),
              icon: Icons.place_outlined,
              label: cityById(draft.cityId).name.resolve(lang),
              dropdown: true,
              onTap: () async {
                final picked = await showOptionSheet(
                  context,
                  title: l.city,
                  options: {for (final c in kCities) c.id: c.name.resolve(lang)},
                  current: draft.cityId,
                );
                if (picked == null) return;
                setState(() {
                  draft.cityId = picked;
                  // A venue belongs to one city.
                  final stillThere = (ref.read(adminVenuesProvider).valueOrNull ?? const []).any(
                    (v) => v.venue.id == draft.venueId && v.venue.cityId == picked,
                  );
                  if (!stillThere) draft.venueId = null;
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel(l.filterSport),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChipButton(
              key: const ValueKey('tournament-sport'),
              label: sportName,
              dropdown: true,
              onTap: () async {
                final picked = await showOptionSheet(
                  context,
                  title: l.filterSport,
                  options: {
                    for (final s in sports)
                      if (s.active || s.sport.id == draft.sportId) s.sport.id: s.sport.name.resolve(lang),
                  },
                  current: draft.sportId,
                );
                if (picked != null) setState(() => draft.sportId = picked);
              },
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel(l.venueOptional),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChipButton(
              key: const ValueKey('tournament-venue'),
              icon: Icons.stadium_outlined,
              label: venue?.venue.name.resolve(lang) ?? l.noVenue,
              dropdown: true,
              onTap: () async {
                final picked = await showOptionSheet(
                  context,
                  title: l.venueOptional,
                  options: {'': l.noVenue, for (final v in venues) v.venue.id: v.venue.name.resolve(lang)},
                  current: draft.venueId ?? '',
                );
                if (picked != null) setState(() => draft.venueId = picked.isEmpty ? null : picked);
              },
            ),
          ),
          const SizedBox(height: 16),
          LocalizedField(
            fieldKey: 'tournament-title',
            label: l.nameLabel,
            initial: draft.title,
            required: true,
            onChanged: (v) => draft.title = v,
          ),
          const SizedBox(height: 16),
          LocalizedField(
            fieldKey: 'tournament-description',
            label: l.descriptionLabel,
            initial: draft.description,
            multiline: true,
            onChanged: (v) => draft.description = v,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _dateField(context, const ValueKey('tournament-start'), l.firstDayLabel, dayLabel(l, lang, draft.start, now), _pickStart),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dateField(context, const ValueKey('tournament-end'), l.lastDayLabel, dayLabel(l, lang, draft.end, now), _pickEnd),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _dateField(
            context,
            const ValueKey('tournament-deadline'),
            l.deadlineLabel,
            '${dayLabel(l, lang, dateOnly(deadline), now)} ${hm(deadline)}',
            _pickDeadline,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('tournament-cover'),
            controller: _cover,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: l.coverUrlLabel),
          ),
          const SizedBox(height: 8),
          AdminSwitch(
            key: const ValueKey('tournament-active'),
            label: l.activeLabel,
            hint: l.activeHint,
            value: draft.active,
            onChanged: (v) => setState(() => draft.active = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('save-tournament'),
            onPressed: _saving ? null : _save,
            child: Text(l.saveLabel),
          ),
        ],
      ),
    );
  }

  Widget _categories(BuildContext context, TournamentDraft draft, AdminTournament? admin) {
    final l = context.l;
    final lang = context.lang;
    final stored = admin?.tournament.categories ?? const <TournamentCategory>[];
    final currency = cityById(draft.cityId).currency;

    Widget row({required Key key, required String name, required CategoryKind kind, required CategoryGender gender, required int min, required int max, required int fee, required int cap, int? filled, int waitlist = 0, required VoidCallback onTap}) {
      final parts = [
        categoryKindLabel(l, kind),
        categoryGenderLabel(l, gender),
        l.levelRange(min, max),
        feeText(l, fee, currency),
      ];
      return InkWell(
        key: key,
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(parts.join(' · '), style: AppText.muted),
                    Text(
                      [
                        filled == null ? '$cap' : l.filledOf(filled, cap),
                        if (waitlist > 0) l.waitlistCount(waitlist),
                      ].join(' · '),
                      style: AppText.muted,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
            ],
          ),
        ),
      );
    }

    final persisted = _tournamentId != null;
    return SectionCard(
      title: l.tournamentCategories,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(l.categoriesHint, style: AppText.muted),
          ),
          if (persisted && admin == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (persisted)
            for (final c in stored)
              row(
                key: ValueKey('category-row-${c.id}'),
                name: c.name.resolve(lang),
                kind: c.kind,
                gender: c.gender,
                min: c.minLevel,
                max: c.maxLevel,
                fee: c.fee,
                cap: c.cap,
                filled: c.filled,
                waitlist: c.waitlistCount,
                onTap: () => _editCategory(draft: CategoryDraft.from(c), stored: c, last: stored.length <= 1),
              )
          else
            for (final (i, c) in draft.categories.indexed)
              row(
                key: ValueKey('category-row-new-$i'),
                name: c.name.resolve(lang),
                kind: c.kind,
                gender: c.gender,
                min: c.minLevel,
                max: c.maxLevel,
                fee: c.fee,
                cap: c.cap,
                onTap: () => _editCategory(draft: c, localIndex: i, last: false),
              ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('add-category'),
            onPressed: persisted && admin == null ? null : () => _editCategory(last: false),
            icon: const Icon(Icons.add_rounded),
            label: Text(l.addCategory),
          ),
        ],
      ),
    );
  }
}

/// The tournament's organisers (M8a design §5): who they are, Add organiser
/// (an account found by name or phone, as the pair invite finds a partner)
/// and Remove. Each person is told by the backend.
class OrganizersCard extends ConsumerWidget {
  const OrganizersCard({super.key, required this.tournamentId, required this.sportId});

  final String tournamentId;

  /// Find players starts with the tournament's sport.
  final String sportId;

  Future<void> _set(BuildContext context, WidgetRef ref, String userId, {required bool add}) async {
    final l = context.l;
    final error = await runAdminTournamentWrite(
      ref,
      l,
      () => ref.read(adminRepositoryProvider).setOrganizer(tournamentId, userId, add: add),
    );
    if (context.mounted) showMessage(context, error ?? l.savedMsg);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final player = await showPickPlayerSheet(context, title: l.addOrganizer, action: l.addOrganizer, sportId: sportId);
    if (player == null || !context.mounted) return;
    await _set(context, ref, player.id, add: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return SectionCard(
      key: const ValueKey('organizers-card'),
      title: l.organizersTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.organizersHint, style: AppText.muted),
          const SizedBox(height: 4),
          AsyncBody(
            value: ref.watch(adminOrganizersProvider(tournamentId)),
            onRetry: () => ref.invalidate(adminOrganizersProvider(tournamentId)),
            errorText: (error) => tournamentErrorText(l, error),
            builder: (organizers) => organizers.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(l.noOrganizers, style: AppText.muted),
                  )
                : Column(
                    children: [
                      for (final p in organizers)
                        Padding(
                          key: ValueKey('organizer-${p.id}'),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              InitialAvatar(name: p.name, size: 36, deleted: p.deleted),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  playerName(l, p.name, deleted: p.deleted),
                                  style: AppText.bodyStrong,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                key: ValueKey('remove-organizer-${p.id}'),
                                tooltip: l.removeOrganizer,
                                onPressed: () => _set(context, ref, p.id, add: false),
                                icon: const Icon(Icons.person_remove_outlined, color: AppColors.error),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('add-organizer'),
            onPressed: () => _add(context, ref),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: Text(l.addOrganizer),
          ),
        ],
      ),
    );
  }
}
