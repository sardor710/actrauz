import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../domain/tournaments.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../tournaments/tournament_tools.dart';
import 'admin_common.dart';
import 'localized_field.dart';

/// The form of one category (singles or pairs, eligibility, fee, places,
/// waitlist). It edits a copy of [initial]; [onSave] gets the result and
/// returns the reason to show when it is refused, or `null` when done.
///
/// [filled] is how many entries already hold a spot: the places cannot go
/// below it. [onDelete] is `null` when the category cannot be deleted (a new
/// one, or the tournament's last).
Future<bool?> showCategorySheet(
  BuildContext context, {
  required CategoryDraft initial,
  required int filled,
  required Future<String?> Function(CategoryDraft draft) onSave,
  Future<String?> Function()? onDelete,
}) => showAdminSheet(
  context,
  (context) => _CategorySheet(initial: initial, filled: filled, onSave: onSave, onDelete: onDelete),
);

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.initial, required this.filled, required this.onSave, this.onDelete});

  final CategoryDraft initial;
  final int filled;
  final Future<String?> Function(CategoryDraft draft) onSave;
  final Future<String?> Function()? onDelete;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final CategoryDraft _draft = CategoryDraft(
    id: widget.initial.id,
    tournamentId: widget.initial.tournamentId,
    name: widget.initial.name,
    kind: widget.initial.kind,
    gender: widget.initial.gender,
    minLevel: widget.initial.minLevel,
    maxLevel: widget.initial.maxLevel,
    fee: widget.initial.fee,
    cap: widget.initial.cap,
    waitlistEnabled: widget.initial.waitlistEnabled,
    sortOrder: widget.initial.sortOrder,
  );
  late final _fee = TextEditingController(text: '${_draft.fee}');
  late final _cap = TextEditingController(text: '${_draft.cap}');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _fee.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<void> _pickLevel({required bool min}) async {
    final l = context.l;
    final picked = await showOptionSheet(
      context,
      title: min ? l.minLevelLabel : l.maxLevelLabel,
      options: {for (var n = 1; n <= 5; n++) '$n': l.level(n)},
      current: '${min ? _draft.minLevel : _draft.maxLevel}',
    );
    if (picked == null) return;
    setState(() {
      final level = int.parse(picked);
      if (min) {
        _draft.minLevel = level;
        if (_draft.maxLevel < level) _draft.maxLevel = level;
      } else {
        _draft.maxLevel = level;
        if (_draft.minLevel > level) _draft.minLevel = level;
      }
    });
  }

  Future<void> _save() async {
    final l = context.l;
    final fee = int.tryParse(_fee.text.trim());
    final cap = int.tryParse(_cap.text.trim());
    final named = [_draft.name.uz, _draft.name.ru, _draft.name.en].any((s) => s != null && s.trim().isNotEmpty);
    if (!named) return setState(() => _error = l.nameRequiredAny);
    if (fee == null || cap == null) return setState(() => _error = l.errInvalidArgument);
    // The database refuses it too; say why before asking.
    if (widget.initial.id != null && cap < widget.filled) {
      return setState(() => _error = l.capBelowFilled(widget.filled));
    }
    _draft
      ..fee = fee
      ..cap = cap;
    await _run(() => widget.onSave(_draft));
  }

  Future<void> _delete() async {
    final name = widget.initial.name.resolve(context.lang);
    if (!await confirmDelete(context, name)) return;
    await _run(widget.onDelete!);
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await action();
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final isNew = widget.initial.id == null;
    return AdminSheetFrame(
      title: isNew ? l.newCategory : l.editCategory,
      saveKey: const ValueKey('save-category'),
      onSave: _save,
      busy: _busy,
      error: _error,
      extraAction: widget.onDelete == null
          ? null
          : TextButton.icon(
              key: const ValueKey('delete-category'),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(l.deleteCategory),
            ),
      children: [
        LocalizedField(
          fieldKey: 'category-name',
          label: l.nameLabel,
          initial: _draft.name,
          required: true,
          onChanged: (v) => _draft.name = v,
        ),
        const SizedBox(height: 16),
        FieldLabel(l.typeLabel),
        Wrap(
          spacing: 8,
          children: [
            for (final kind in CategoryKind.values)
              ChoiceChip(
                key: ValueKey('category-kind-${kind.name}'),
                label: Text(categoryKindLabel(l, kind)),
                selected: _draft.kind == kind,
                onSelected: (_) => setState(() => _draft.kind = kind),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FieldLabel(l.genderLabel),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final gender in CategoryGender.values)
              ChoiceChip(
                key: ValueKey('category-gender-${gender.name}'),
                label: Text(categoryGenderLabel(l, gender)),
                selected: _draft.gender == gender,
                onSelected: (_) => setState(() => _draft.gender = gender),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FieldLabel(l.levelRangeLabel),
        Row(
          children: [
            FilterChipButton(
              key: const ValueKey('category-min-level'),
              label: l.level(_draft.minLevel),
              dropdown: true,
              onTap: () => _pickLevel(min: true),
            ),
            FilterChipButton(
              key: const ValueKey('category-max-level'),
              label: l.level(_draft.maxLevel),
              dropdown: true,
              onTap: () => _pickLevel(min: false),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('category-fee'),
                controller: _fee,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: l.entryFee),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('category-cap'),
                controller: _cap,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: l.capLabel),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AdminSwitch(
          key: const ValueKey('category-waitlist'),
          label: l.waitlistLabel,
          hint: l.waitlistHint,
          value: _draft.waitlistEnabled,
          onChanged: (v) => setState(() => _draft.waitlistEnabled = v),
        ),
      ],
    );
  }
}
