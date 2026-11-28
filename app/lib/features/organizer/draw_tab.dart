import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/brackets.dart';
import '../../domain/tournaments.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../tournaments/bracket_view.dart';
import '../tournaments/tournament_tools.dart';

/// The format the organiser picked for a category's next draw.
typedef _Choice = ({DrawFormat format, int groupSize, int advance});

/// The manager's Draw tab (M8a design §6, §11), one category at a time: its
/// entries (names, phones, paid), the format, "Make draw", the draft with
/// tap-two-entries-to-swap, Publish and Redo. Every refusal shows its reason.
class DrawTab extends ConsumerStatefulWidget {
  const DrawTab({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  ConsumerState<DrawTab> createState() => _DrawTabState();
}

/// Kept alive: a tab flip keeps the category, the format choices and the
/// open entries list.
class _DrawTabState extends ConsumerState<DrawTab> with AutomaticKeepAliveClientMixin {
  String get tournamentId => widget.tournamentId;

  @override
  bool get wantKeepAlive => true;

  String? _categoryId;
  final _choices = <String, _Choice>{};
  bool _entriesOpen = false;
  bool _busy = false;

  /// The first entry tapped for a swap, in the draw it was tapped in: a
  /// reloaded draw drops it.
  String? _selected;
  CategoryDraw? _selectedIn;

  _Choice _choice(String categoryId, CategoryDraw? draw) =>
      _choices[categoryId] ??
      (format: draw?.format ?? DrawFormat.knockout, groupSize: draw?.groupSize ?? 4, advance: draw?.advance ?? 2);

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _selected = null;
    });
    await runTournamentAction(context, ref, action, organizer: true);
    if (mounted) setState(() => _busy = false);
  }

  void _tapEntry(CategoryDraw draw, String registrationId) {
    final first = identical(_selectedIn, draw) ? _selected : null;
    if (first == null) {
      setState(() {
        _selected = registrationId;
        _selectedIn = draw;
      });
    } else if (first == registrationId) {
      setState(() => _selected = null);
    } else {
      _run(() => ref.read(organizerRepositoryProvider).swapEntries(draw.categoryId, first, registrationId));
    }
  }

  Future<bool> _confirm(String title, String text, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => ClosesOnAccountChange(
        child: AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.l.cancel)),
            FilledButton(
              key: const ValueKey('confirm-dialog-ok'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _publish(String categoryId) async {
    final l = context.l;
    if (!await _confirm(l.publishConfirmTitle, l.publishConfirmText, l.publishDraw) || !mounted) return;
    await _run(() => ref.read(organizerRepositoryProvider).publish(categoryId));
  }

  Future<void> _redo(String categoryId) async {
    final l = context.l;
    if (!await _confirm(l.redoConfirmTitle, l.redoConfirmText, l.redoDraw) || !mounted) return;
    await _run(() => ref.read(organizerRepositoryProvider).redo(categoryId));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = context.l;
    final bracketValue = ref.watch(bracketProvider(tournamentId));
    final entriesValue = ref.watch(organizerEntriesProvider(tournamentId));

    return AsyncBody(
      value: ref.watch(tournamentProvider(tournamentId)),
      onRetry: () => ref.invalidate(tournamentProvider(tournamentId)),
      errorText: (error) => organizerErrorText(l, error),
      canRetry: (error) => !(error is TournamentException && error.error == TournamentError.notFound),
      builder: (tournament) {
        // Kept through a failed refresh; never another account's.
        final bracket = currentData(bracketValue);
        if (bracket == null) {
          if (bracketValue.isLoading || !bracketValue.hasError) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _error(bracketValue.error, () => ref.invalidate(bracketProvider(tournamentId)));
        }
        if (!bracket.organizer) return EmptyState(icon: Icons.lock_outline_rounded, text: l.notOrganizer);
        return _body(context, tournament, bracket, currentData(entriesValue), entriesValue);
      },
    );
  }

  Widget _error(Object? error, VoidCallback retry) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      EmptyState(
        icon: Icons.error_outline,
        text: error == null ? context.l.errGeneric : organizerErrorText(context.l, error),
      ),
      OutlinedButton(key: const ValueKey('async-retry'), onPressed: retry, child: Text(context.l.tryAgain)),
    ],
  );

  Widget _body(
    BuildContext context,
    Tournament tournament,
    TournamentBracket bracket,
    List<AdminRegistration>? entries,
    AsyncValue<List<AdminRegistration>> entriesValue,
  ) {
    final categories = tournament.categories;
    if (categories.isEmpty) return EmptyState(icon: Icons.category_outlined, text: context.l.errNotFound);
    final category = categories.where((c) => c.id == _categoryId).firstOrNull ?? categories.first;
    final lang = context.lang;

    return RefreshIndicator(
      onRefresh: () => pullToReload(
        context,
        Future.wait([
          ref.refresh(bracketProvider(tournamentId).future),
          ref.refresh(organizerEntriesProvider(tournamentId).future),
        ]),
      ),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in categories)
                ChoiceChip(
                  key: ValueKey('manage-category-${c.id}'),
                  label: Text(c.name.resolve(lang)),
                  selected: c.id == category.id,
                  onSelected: (_) => setState(() {
                    _categoryId = c.id;
                    _selected = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _category(context, tournament, category, bracket.draw(category.id), entries, entriesValue),
        ],
      ),
    );
  }

  Widget _category(
    BuildContext context,
    Tournament tournament,
    TournamentCategory category,
    CategoryDraw? draw,
    List<AdminRegistration>? entries,
    AsyncValue<List<AdminRegistration>> entriesValue,
  ) {
    final l = context.l;
    final mine = entries?.where((e) => e.registration.categoryId == category.id).toList();
    final registered = mine?.where((e) => e.registration.status == RegistrationStatus.registered).length;

    final (statusKey, statusText, statusColor, statusOn) = switch (draw) {
      null => ('draw-status-none', l.drawStatusNone, AppColors.field, AppColors.muted),
      CategoryDraw(published: false) => ('draw-status-draft', l.drawStatusDraft, AppColors.amberSoft, AppColors.ink),
      _ => ('draw-status-published', l.drawStatusPublished, AppColors.primarySoft, AppColors.primaryDark),
    };

    Widget entriesBlock() {
      if (mine == null) {
        if (entriesValue.isLoading || !entriesValue.hasError) return const LinearProgressIndicator();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(organizerErrorText(l, entriesValue.error!), key: const ValueKey('entries-error'), style: AppText.muted),
            TextButton(
              key: const ValueKey('entries-retry'),
              onPressed: () => ref.invalidate(organizerEntriesProvider(tournamentId)),
              child: Text(l.tryAgain),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('entries-toggle'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _entriesOpen = !_entriesOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.groups_outlined, color: AppColors.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l.entriesTitle, style: AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Icon(_entriesOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                ],
              ),
            ),
          ),
          if (_entriesOpen)
            for (final e in mine) _EntryRow(entry: e),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category.name.resolve(context.lang),
                    style: AppText.cardTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Pill(key: ValueKey(statusKey), text: statusText, color: statusColor, onColor: statusOn),
              ],
            ),
            if (registered != null) ...[
              const SizedBox(height: 4),
              Text(l.entriesCount(registered), key: const ValueKey('entries-count'), style: AppText.muted),
            ],
            const SizedBox(height: 8),
            entriesBlock(),
            const Divider(height: 24),
            if (draw == null || !draw.published) ..._draftPart(context, category, draw) else ..._published(draw),
          ],
        ),
      ),
    );
  }

  List<Widget> _draftPart(BuildContext context, TournamentCategory category, CategoryDraw? draw) {
    final l = context.l;
    final choice = _choice(category.id, draw);
    void choose(_Choice c) => setState(() => _choices[category.id] = c);

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 10),
      child: Text(text.toUpperCase(), style: AppText.sectionTitle),
    );

    return [
      label(l.drawFormatLabel),
      SegmentedButton<DrawFormat>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: DrawFormat.knockout,
            label: Text(l.formatKnockout, key: const ValueKey('format-knockout')),
          ),
          ButtonSegment(
            value: DrawFormat.groups,
            label: Text(l.formatGroups, key: const ValueKey('format-groups')),
          ),
        ],
        selected: {choice.format},
        onSelectionChanged: (v) => choose((format: v.first, groupSize: choice.groupSize, advance: choice.advance)),
      ),
      if (choice.format == DrawFormat.groups) ...[
        label(l.groupSizeLabel),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (final n in const [3, 4]) ButtonSegment(value: n, label: Text('$n', key: ValueKey('group-size-$n'))),
          ],
          selected: {choice.groupSize},
          onSelectionChanged: (v) => choose((format: choice.format, groupSize: v.first, advance: choice.advance)),
        ),
        label(l.advancingLabel),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (final n in const [1, 2]) ButtonSegment(value: n, label: Text('$n', key: ValueKey('advance-$n'))),
          ],
          selected: {choice.advance},
          onSelectionChanged: (v) => choose((format: choice.format, groupSize: choice.groupSize, advance: v.first)),
        ),
      ],
      const SizedBox(height: 14),
      FilledButton.icon(
        key: const ValueKey('make-draw'),
        onPressed: _busy
            ? null
            : () => _run(
                () => ref
                    .read(organizerRepositoryProvider)
                    .makeDraw(
                      category.id,
                      choice.format,
                      groupSize: choice.format == DrawFormat.groups ? choice.groupSize : null,
                      advance: choice.format == DrawFormat.groups ? choice.advance : null,
                    ),
              ),
        icon: const Icon(Icons.shuffle_rounded),
        label: Text(draw == null ? l.makeDraw : l.makeDrawAgain),
      ),
      if (draw != null) ...[
        const Divider(height: 28),
        if (draw.outdated)
          Container(
            key: const ValueKey('draw-outdated'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.sync_problem_rounded, color: AppColors.error),
                const SizedBox(width: 10),
                Expanded(child: Text(l.drawOutdatedBanner, style: manrope(14, 700, color: AppColors.error))),
              ],
            ),
          ),
        Text(l.swapHint, style: AppText.muted),
        const SizedBox(height: 10),
        _DraftPreview(
          draw: draw,
          selected: identical(_selectedIn, draw) ? _selected : null,
          onTap: _busy ? null : (id) => _tapEntry(draw, id),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const ValueKey('publish-draw'),
          onPressed: _busy || draw.outdated ? null : () => _publish(category.id),
          icon: const Icon(Icons.campaign_outlined),
          label: Text(l.publishDraw),
        ),
      ],
    ];
  }

  List<Widget> _published(CategoryDraw draw) {
    final l = context.l;
    // Scores make the draw final; the backend has the last word (walkovers
    // from withdrawals do not count).
    final scored = draw.matches.any(
      (m) => const {MatchOutcome.played, MatchOutcome.retired, MatchOutcome.decider}.contains(m.outcome),
    );
    final city = ref.watch(tournamentProvider(tournamentId)).valueOrNull?.cityId;
    final now = city == null ? DateTime.now() : tournamentNow(ref, city);
    return [
      Row(
        children: [
          const Icon(Icons.lock_outline_rounded, color: AppColors.primaryDark, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(l.drawPublishedNote, style: AppText.bodyStrong)),
        ],
      ),
      const SizedBox(height: 12),
      CategoryDrawSection(draw: draw, now: now),
      if (!scored) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('redo-draw'),
          onPressed: _busy ? null : () => _redo(draw.categoryId),
          icon: const Icon(Icons.restart_alt_rounded),
          label: Text(l.redoDraw),
        ),
      ],
    ];
  }
}

/// One entry for the organiser: the players, their phones, paid or not; the
/// state when it is not a registered entry.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final AdminRegistration entry;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final r = entry.registration;
    final people = [
      (r.registrant, entry.registrantPhone),
      if (r.partner case final partner?) (partner, entry.partnerPhone),
    ];
    final registered = r.status == RegistrationStatus.registered;
    return Container(
      key: ValueKey('entry-row-${r.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (p, phone) in people) ...[
                  Text(
                    playerName(l, p.name, deleted: p.deleted),
                    style: AppText.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (phone != null && phone.isNotEmpty) Text(phone, style: AppText.caption),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (registered)
            Pill(
              text: r.paid ? l.paidLabel : l.notPaidLabel,
              color: r.paid ? AppColors.primarySoft : AppColors.field,
              onColor: r.paid ? AppColors.primaryDark : AppColors.muted,
            )
          else
            RegistrationStatusPill(registration: r),
        ],
      ),
    );
  }
}

/// A draft as the organiser rearranges it: the groups with their entries, or
/// the knockout's first round. Tapping two entries swaps them.
class _DraftPreview extends StatelessWidget {
  const _DraftPreview({required this.draw, required this.selected, required this.onTap});

  final CategoryDraw draw;
  final String? selected;

  /// Null while an action runs.
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    if (draw.format == DrawFormat.groups) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in draw.groups)
            _box(
              key: ValueKey('draft-group-${g.id}'),
              header: l.groupLabel(g.label),
              children: [
                for (final e in draw.entries.where((e) => e.groupId == g.id).toList()
                  ..sort((a, b) => a.seed.compareTo(b.seed)))
                  _entry(l, e.registrationId),
              ],
            ),
        ],
      );
    }
    final firstRound =
        draw.matches.where((m) => m.stage == MatchStage.knockout && m.round == 1).toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    Widget side(String? id, bool empty) => id != null
        ? _entry(l, id)
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Text(empty ? l.byeLabel : l.matchTbd, style: AppText.muted),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in firstRound)
          _box(key: ValueKey('draft-match-${m.id}'), children: [side(m.sideA, m.aEmpty), side(m.sideB, m.bEmpty)]),
      ],
    );
  }

  Widget _box({required Key key, String? header, required List<Widget> children}) => Container(
    key: key,
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Container(
            color: AppColors.field,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(header, style: AppText.bodyStrong),
          ),
        ...children,
      ],
    ),
  );

  Widget _entry(AppLocalizations l, String registrationId) {
    final isSelected = selected == registrationId;
    final entry = draw.entries.where((e) => e.registrationId == registrationId).firstOrNull;
    return Material(
      color: isSelected ? AppColors.primarySoft : Colors.transparent,
      child: InkWell(
        key: ValueKey('draft-entry-$registrationId'),
        onTap: onTap == null ? null : () => onTap!(registrationId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(entry == null ? '' : '${entry.seed}', style: AppText.caption),
              ),
              Expanded(
                child: Text(
                  entryName(l, draw, registrationId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStrong,
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.swap_vert_rounded,
                  key: ValueKey('draft-selected-$registrationId'),
                  color: AppColors.primaryDark,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
