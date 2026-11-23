import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/sample/sample_media.dart';
import '../../domain/admin.dart';
import '../../state/admin_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'admin_common.dart';
import 'localized_field.dart';

/// Every sport, active or not (product spec §12.4); added and edited in a
/// sheet.
class AdminSportsScreen extends StatelessWidget {
  const AdminSportsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      AdminScaffold(title: context.l.adminSports, fallback: '/admin', body: (_) => const _SportList());
}

/// Icons the app can draw for a sport.
const _iconKeys = ['padel', 'tennis', 'football', 'basketball', 'volleyball', 'sports'];

class _SportList extends ConsumerWidget {
  const _SportList();

  Future<void> _open(BuildContext context, WidgetRef ref, SportDraft draft, {required bool create}) async {
    final saved = await showAdminSheet(context, (_) => _SportSheet(draft: draft, create: create));
    if (saved == true && context.mounted) {
      refreshAdmin(ref);
      showMessage(context, context.l.savedMsg);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return AsyncBody(
      value: ref.watch(adminSportsProvider),
      builder: (sports) => AdminListView(
        bottom: 24,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('add-sport'),
              style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: () {
                final last = sports.isEmpty ? -1 : sports.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b);
                _open(context, ref, SportDraft(iconKey: 'sports', sortOrder: last + 1), create: true);
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(l.addSport),
            ),
          ),
          const SizedBox(height: 12),
          for (final s in sports) ...[
            Card(
              child: InkWell(
                key: ValueKey('admin-sport-${s.sport.id}'),
                onTap: () => _open(context, ref, SportDraft.from(s), create: false),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _SportIcon(sportId: s.sport.id, iconKey: s.sport.iconKey),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.sport.name.resolve(context.lang),
                              style: AppText.cardTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                s.sport.bookable ? l.bookable : l.placeOnly,
                                s.sport.competitiveRating ? l.ratingCompetitive : l.ratingSimple,
                                l.playersN(s.sport.defaultPlayers),
                              ].join(' · '),
                              style: AppText.muted,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!s.active) ...[const SizedBox(height: 8), const InactivePill()],
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// The sport's 3D icon, or the line icon for its icon key.
class _SportIcon extends StatelessWidget {
  const _SportIcon({required this.sportId, required this.iconKey});

  final String sportId;
  final String iconKey;

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
    child: Image.asset(
      sportIconAsset(sportId),
      width: 36,
      height: 36,
      errorBuilder: (context, error, stack) => Icon(sportIcon(iconKey), color: AppColors.primaryDark, size: 26),
    ),
  );
}

class _SportSheet extends ConsumerStatefulWidget {
  const _SportSheet({required this.draft, required this.create});

  final SportDraft draft;
  final bool create;

  @override
  ConsumerState<_SportSheet> createState() => _SportSheetState();
}

class _SportSheetState extends ConsumerState<_SportSheet> {
  final _form = GlobalKey<FormState>();
  late final SportDraft _draft = widget.draft;
  late final _players = TextEditingController(text: '${widget.draft.defaultPlayers}');
  late final _order = TextEditingController(text: '${widget.draft.sortOrder}');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _players.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    _draft
      ..defaultPlayers = int.parse(_players.text.trim())
      ..sortOrder = int.parse(_order.text.trim());
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).saveSport(_draft, create: widget.create);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = bookingErrorText(l, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final icons = {..._iconKeys, if (_draft.iconKey.isNotEmpty) _draft.iconKey};

    return Form(
      key: _form,
      child: AdminSheetFrame(
        title: widget.create ? l.newSport : l.editSport,
        saveKey: const ValueKey('save-sport'),
        busy: _busy,
        error: _error,
        onSave: _save,
        children: [
          if (widget.create) ...[
            TextFormField(
              key: const ValueKey('sport-id'),
              initialValue: _draft.id,
              autocorrect: false,
              decoration: InputDecoration(labelText: l.sportIdLabel, helperText: l.sportIdHint, helperMaxLines: 3, errorMaxLines: 3),
              validator: (v) => kSportIdPattern.hasMatch(v?.trim() ?? '') ? null : l.errSportId,
              onChanged: (v) => setState(() {
                _draft.id = v.trim();
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
          ],
          LocalizedField(
            fieldKey: 'sport-name',
            label: l.nameLabel,
            initial: _draft.name,
            required: true,
            onChanged: (v) => _draft.name = v,
          ),
          const SizedBox(height: 12),
          FieldLabel(l.iconLabel),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in icons)
                ChoiceChip(
                  key: ValueKey('sport-icon-$key'),
                  avatar: Icon(sportIcon(key), size: 18),
                  label: Text(key),
                  selected: _draft.iconKey == key,
                  onSelected: (_) => setState(() => _draft.iconKey = key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FieldLabel(l.sportTypeLabel),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, label: Text(l.bookable)),
              ButtonSegment(value: false, label: Text(l.placeOnly)),
            ],
            selected: {_draft.bookable},
            onSelectionChanged: (v) => setState(() => _draft.bookable = v.first),
          ),
          const SizedBox(height: 16),
          FieldLabel(l.ratingLabel),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(l.ratingSimple)),
              ButtonSegment(value: true, label: Text(l.ratingCompetitive)),
            ],
            selected: {_draft.competitiveRating},
            onSelectionChanged: (v) => setState(() => _draft.competitiveRating = v.first),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('sport-players'),
                  controller: _players,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: l.defaultPlayers, errorMaxLines: 2),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    return n == null || n < 1 || n > 100 ? l.errInvalidArgument : null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('sport-order'),
                  controller: _order,
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                  decoration: InputDecoration(labelText: l.sortOrderLabel, errorMaxLines: 2),
                  validator: (v) => int.tryParse(v?.trim() ?? '') == null ? l.errInvalidArgument : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AdminSwitch(
            key: const ValueKey('sport-active'),
            label: l.activeLabel,
            hint: l.activeHint,
            value: _draft.active,
            onChanged: (v) => setState(() => _draft.active = v),
          ),
        ],
      ),
    );
  }
}
