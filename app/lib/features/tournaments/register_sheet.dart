import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/tournaments.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'tournament_tools.dart';

/// What the player chose in the sheet. [partnerId] is null for singles.
class RegisterChoice {
  const RegisterChoice({this.partnerId});

  final String? partnerId;
}

/// Asks for what a registration needs: a confirmation for singles, a partner
/// for pairs (from Find players, or by an exact phone number). Returns the
/// choice, or null when dismissed; the caller then runs the registration, so
/// its errors show on the screen and not behind the sheet.
Future<RegisterChoice?> showRegisterSheet(
  BuildContext context, {
  required Tournament tournament,
  required TournamentCategory category,
  required bool waitlist,
}) => showModalBottomSheet<RegisterChoice>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => RegisterSheet(tournament: tournament, category: category, waitlist: waitlist),
);

class RegisterSheet extends ConsumerStatefulWidget {
  const RegisterSheet({super.key, required this.tournament, required this.category, required this.waitlist});

  final Tournament tournament;
  final TournamentCategory category;
  final bool waitlist;

  @override
  ConsumerState<RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends ConsumerState<RegisterSheet> {
  final _search = TextEditingController();
  final _phone = TextEditingController();
  int _tab = 0;
  PlayerRef? _partner;

  /// Said under the phone field: no such player, too many lookups.
  String? _phoneMessage;

  /// Said above the button: no partner chosen yet.
  String? _error;
  bool _finding = false;

  bool get _pairs => widget.category.kind == CategoryKind.pairs;

  @override
  void dispose() {
    _search.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) return;
    setState(() {
      _finding = true;
      _phoneMessage = null;
      _partner = null;
    });
    final l = context.l;
    try {
      final found = await ref.read(tournamentRepositoryProvider).findPlayerByPhone(phone);
      if (!mounted) return;
      setState(() {
        _partner = found;
        _phoneMessage = found == null ? l.partnerNotFound : null;
        _error = null;
      });
    } on TournamentException catch (e) {
      if (mounted) setState(() => _phoneMessage = tournamentErrorText(l, e));
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  void _submit() {
    if (_pairs && _partner == null) {
      setState(() => _error = context.l.partnerPickFirst);
      return;
    }
    Navigator.of(context).pop(RegisterChoice(partnerId: _pairs ? _partner!.id : null));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = widget.tournament;
    final c = widget.category;
    final name = c.name.resolve(context.lang);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.waitlist ? l.waitlistSheetTitle(name) : l.registerSheetTitle(name), style: AppText.title),
              const SizedBox(height: 6),
              Text(t.title.resolve(context.lang), style: AppText.muted),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pill(text: categoryKindLabel(l, c.kind)),
                  Pill(text: l.levelRange(c.minLevel, c.maxLevel), icon: Icons.bar_chart_rounded),
                  Pill(text: feeText(l, c.fee, t.currency), color: AppColors.primarySoft, onColor: AppColors.primaryDark),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.waitlist) ...[Text(l.waitlistSheetNote, style: AppText.muted), const SizedBox(height: 6)],
              if (c.fee > 0) Text(l.registrationFeeNote(money(l, c.fee, t.currency)), style: AppText.muted),
              if (_pairs) ...[
                const SizedBox(height: 18),
                Text(l.partnerTitle.toUpperCase(), style: AppText.sectionTitle),
                const SizedBox(height: 10),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 0, label: Text(l.partnerTabPlayers)),
                    ButtonSegment(value: 1, label: Text(l.partnerTabPhone)),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (v) => setState(() {
                    _tab = v.first;
                    _partner = null;
                    _phoneMessage = null;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 12),
                if (_tab == 0) _players(context) else _phoneLookup(context),
                const SizedBox(height: 8),
                Text(l.inviteNote, style: AppText.caption),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: manrope(13.5, 700, color: AppColors.error)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(
                    widget.waitlist ? l.joinWaitlist : (_pairs ? l.sendInvite : l.confirmRegistration),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _players(BuildContext context) {
    final l = context.l;
    final c = widget.category;
    final text = _search.text.trim();
    final search = (
      sportId: widget.tournament.sportId,
      minLevel: c.minLevel,
      maxLevel: c.maxLevel,
      query: text.isEmpty ? null : text,
    );
    return Column(
      children: [
        TextField(
          key: const ValueKey('partner-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: l.searchPlayersHint, prefixIcon: const Icon(Icons.search_rounded)),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: AsyncBody(
            value: ref.watch(playersProvider(search)),
            builder: (players) => players.isEmpty
                ? EmptyState(icon: Icons.person_search_outlined, text: l.noPlayersFound)
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in players)
                        _PartnerRow(
                          key: ValueKey('partner-player-${p.id}'),
                          name: p.name,
                          selected: _partner?.id == p.id,
                          onTap: () => setState(() {
                            _partner = PlayerRef(id: p.id, name: p.name);
                            _error = null;
                          }),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _phoneLookup(BuildContext context) {
    final l = context.l;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('partner-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                onSubmitted: (_) => _find(),
                decoration: InputDecoration(hintText: l.partnerPhoneHint, prefixIcon: const Icon(Icons.phone_outlined)),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: _finding ? null : _find, child: Text(l.partnerFind)),
          ],
        ),
        if (_phoneMessage != null) ...[
          const SizedBox(height: 8),
          Text(_phoneMessage!, style: manrope(13.5, 700, color: AppColors.error)),
        ],
        if (_partner != null) _PartnerRow(name: _partner!.name, selected: true, onTap: () {}),
      ],
    );
  }
}

class _PartnerRow extends StatelessWidget {
  const _PartnerRow({super.key, required this.name, required this.selected, required this.onTap});

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          InitialAvatar(name: name, size: 40),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: manrope(15.5, 700))),
          if (selected) const Icon(Icons.check_circle, color: AppColors.primary),
        ],
      ),
    ),
  );
}
