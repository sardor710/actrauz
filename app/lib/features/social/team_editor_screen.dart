import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/teams.dart';
import '../../state/providers.dart';
import '../../state/ui_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'team_screen.dart' show teamCityName, teamSportName;

/// Creates a team, or lets its captain edit it ([teamId]). The sport and
/// city are chosen once: editing changes the name, description and join
/// policy only, as the backend does.
class TeamEditorScreen extends ConsumerStatefulWidget {
  const TeamEditorScreen({super.key, this.teamId});

  final String? teamId;

  @override
  ConsumerState<TeamEditorScreen> createState() => _TeamEditorScreenState();
}

class _TeamEditorScreenState extends ConsumerState<TeamEditorScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String? _sportId;
  late String _cityId = ref.read(currentCityProvider).id;
  TeamJoinPolicy _policy = TeamJoinPolicy.open;

  /// Editing: false until the team has loaded, true when it failed to.
  bool _loading = false;
  bool _failed = false;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.teamId != null;

  @override
  void initState() {
    super.initState();
    final id = widget.teamId;
    if (id == null) return;
    _loading = true;
    ref
        .read(teamProvider(id).future)
        .then(
          (team) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _name.text = team.name;
              _description.text = team.description ?? '';
              _sportId = team.sportId;
              _cityId = team.cityId;
              _policy = team.joinPolicy;
            });
          },
          onError: (Object _) {
            if (mounted) setState(() => _failed = true);
          },
        );
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _valid {
    final length = _name.text.trim().length;
    return _sportId != null && length >= Team.minName && length <= Team.maxName;
  }

  Future<void> _pickSport(List<Sport> sports) async {
    final picked = await showOptionSheet(
      context,
      title: context.l.teamChooseSport,
      options: {for (final s in sports) s.id: s.name.resolve(context.lang)},
      current: _sportId,
    );
    if (picked != null) setState(() => _sportId = picked);
  }

  Future<void> _pickCity() async {
    final picked = await showOptionSheet(
      context,
      title: context.l.city,
      options: {for (final c in kCities) c.id: c.name.resolve(context.lang)},
      current: _cityId,
    );
    if (picked != null) setState(() => _cityId = picked);
  }

  Future<void> _save() async {
    final l = context.l;
    final social = ref.read(socialRepositoryProvider);
    final description = _description.text.trim();
    final draft = TeamDraft(
      name: _name.text.trim(),
      sportId: _sportId!,
      cityId: _cityId,
      description: description.isEmpty ? null : description,
      joinPolicy: _policy,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = widget.teamId;
      final team = id == null ? await social.createTeam(draft) : await social.updateTeam(id, draft);
      if (!mounted) return;
      refreshTeams(ref);
      if (id == null) {
        context.pushReplacement('/teams/${team.id}');
      } else {
        context.canPop() ? context.pop() : context.go('/teams/$id');
      }
    } on JoinException catch (e) {
      if (mounted) setState(() => _error = joinErrorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final sportName = _sportId == null ? null : teamSportName(context, sports, _sportId!);

    Widget body() {
      if (_failed) return EmptyState(icon: Icons.error_outline, text: l.errGeneric);
      if (_loading) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            key: const ValueKey('team-name'),
            controller: _name,
            maxLength: Team.maxName,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: l.nameLabel, helperText: l.teamNameHelp(Team.minName, Team.maxName)),
          ),
          const SizedBox(height: 12),
          if (_editing)
            InputDecorator(
              decoration: InputDecoration(labelText: l.filterSport),
              child: Text('$sportName · ${teamCityName(context, _cityId)}', style: AppText.bodyStrong),
            )
          else ...[
            _PickerField(
              key: const ValueKey('team-sport'),
              label: l.filterSport,
              value: sportName ?? l.teamChooseSport,
              onTap: () => _pickSport(sports),
            ),
            const SizedBox(height: 12),
            _PickerField(
              key: const ValueKey('team-city'),
              label: l.city,
              value: teamCityName(context, _cityId),
              onTap: _pickCity,
            ),
          ],
          const SizedBox(height: 6),
          Text(l.teamFixedHint, style: AppText.caption),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('team-description'),
            controller: _description,
            minLines: 3,
            maxLines: 6,
            maxLength: Team.maxDescription,
            decoration: InputDecoration(labelText: l.descriptionLabel, alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          Text(l.teamPolicyTitle, style: AppText.bodyStrong),
          for (final (policy, title, hint) in [
            (TeamJoinPolicy.open, l.teamOpen, l.teamPolicyOpenHint),
            (TeamJoinPolicy.approval, l.teamByApproval, l.teamPolicyApprovalHint),
          ])
            RadioListTile<TeamJoinPolicy>(
              key: ValueKey('team-policy-${policy.name}'),
              contentPadding: EdgeInsets.zero,
              value: policy,
              groupValue: _policy,
              onChanged: (v) => setState(() => _policy = v!),
              title: Text(title, style: AppText.bodyStrong),
              subtitle: Text(hint, style: AppText.muted),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: manrope(13.5, 600, color: AppColors.error)),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/social')),
        title: Text(_editing ? l.teamEditTitle : l.teamNew),
      ),
      body: Column(
        children: [
          Expanded(child: body()),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('team-save'),
                    onPressed: _valid && !_busy && !_loading ? _save : null,
                    child: Text(_editing ? l.saveLabel : l.createTeam),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled field that opens a list to pick from.
class _PickerField extends StatelessWidget {
  const _PickerField({super.key, required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: InputDecorator(
      decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.keyboard_arrow_down)),
      child: Text(value, style: AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}
