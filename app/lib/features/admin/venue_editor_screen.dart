import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/admin.dart';
import '../../domain/models.dart';
import '../../state/admin_providers.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'admin_common.dart';
import 'court_editor_sheet.dart';
import 'localized_field.dart';
import 'owners_sheet.dart';

/// Creates or edits a venue, its courts and its owners (product spec
/// §12.2–12.3). Courts and owners appear once the venue has been saved.
class VenueEditorScreen extends ConsumerStatefulWidget {
  const VenueEditorScreen({super.key, this.venueId});

  /// `null` for a new venue.
  final String? venueId;

  @override
  ConsumerState<VenueEditorScreen> createState() => _VenueEditorScreenState();
}

class _VenueEditorScreenState extends ConsumerState<VenueEditorScreen> {
  final _form = GlobalKey<FormState>();
  late String? _venueId = widget.venueId;
  VenueDraft? _draft;
  bool _saving = false;

  Future<void> _saveVenue() async {
    final draft = _draft!;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    String? id;
    final ok = await adminWrite(context, ref, () async {
      id = await ref.read(adminRepositoryProvider).saveVenue(draft);
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok && id != null) {
        _venueId = id;
        draft.id = id;
      }
    });
  }

  Future<void> _deleteVenue(AdminVenue admin) async {
    final repo = ref.read(adminRepositoryProvider);
    if (!await confirmDelete(context, admin.venue.name.resolve(context.lang))) return;
    if (!mounted) return;
    var deleted = false;
    await adminWrite(
      context,
      ref,
      () async {
        await repo.deleteVenue(admin.venue.id);
        deleted = true;
      },
      onDeactivate: () async {
        await repo.saveVenue(_draft!..active = false);
        if (mounted) setState(() {});
      },
    );
    if (deleted && mounted) context.canPop() ? context.pop() : context.go('/admin/venues');
  }

  Future<void> _editCourt(Venue venue, CourtDraft draft) async {
    final saved = await showCourtEditor(context, draft: draft, cityId: venue.cityId);
    if (saved == true && mounted) {
      refreshAdmin(ref);
      showMessage(context, context.l.savedMsg);
    }
  }

  Future<void> _deleteCourt(Court court) async {
    final repo = ref.read(adminRepositoryProvider);
    if (!await confirmDelete(context, court.name.resolve(context.lang))) return;
    if (!mounted) return;
    await adminWrite(
      context,
      ref,
      () => repo.deleteCourt(court.id),
      onDeactivate: () => repo.saveCourt(CourtDraft.from(court, active: false)),
    );
  }

  Future<void> _assignOwner(AdminVenue admin) async {
    final user = await showOwnerSearch(context, exclude: {for (final o in admin.owners) o.userId});
    if (user == null || !mounted) return;
    await adminWrite(
      context,
      ref,
      () => ref.read(adminRepositoryProvider).setOwner(admin.venue.id, user.userId, assigned: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final venues = ref.watch(adminVenuesProvider);
    final sports = {for (final s in ref.watch(adminSportsProvider).valueOrNull ?? const <AdminSport>[]) s.sport.id: s};
    final admin = _venueId == null ? null : venues.valueOrNull?.where((v) => v.venue.id == _venueId).firstOrNull;

    if (_draft == null) {
      if (_venueId == null) {
        _draft = VenueDraft(cityId: ref.read(currentCityProvider).id);
      } else if (admin != null) {
        _draft = VenueDraft.from(admin);
      }
    }
    final draft = _draft;
    final title = admin?.venue.name.resolve(context.lang) ?? (_venueId == null ? l.newVenue : '');
    final canOpenOwnerScreens = admin != null && admin.active;

    return AdminScaffold(
      title: title,
      fallback: '/admin/venues',
      actions: [
        if (canOpenOwnerScreens) ...[
          IconButton(
            tooltip: l.ownerCalendar,
            onPressed: () => context.push('/owner/${admin.venue.id}'),
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: l.ownerSettings,
            onPressed: () => context.push('/owner/${admin.venue.id}/settings'),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ],
      body: (context) {
        if (draft == null) {
          // Editing a venue that has not loaded, or no longer exists.
          return venues.hasValue && !venues.isLoading
              ? Center(child: EmptyState(icon: Icons.search_off_rounded, text: l.errNotFound))
              : AsyncBody(value: venues, builder: (_) => const SizedBox.shrink());
        }
        final details = _details(context, draft, admin);
        final courts = _courts(context, admin, sports, loading: _venueId != null && admin == null);
        final owners = _owners(context, admin);

        return Form(
          key: _form,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Details on the left, courts and owners on the right on a wide screen.
              if (constraints.maxWidth >= 1100) {
                final side = adminGutter(constraints.maxWidth, maxWidth: 1320) - 16;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(side, 4, side, 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: details),
                      Expanded(flex: 2, child: Column(children: [courts, owners])),
                    ],
                  ),
                );
              }
              final side = adminGutter(constraints.maxWidth) - 16;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(side, 4, side, 24),
                child: Column(children: [details, courts, owners]),
              );
            },
          ),
        );
      },
    );
  }

  Widget _details(BuildContext context, VenueDraft draft, AdminVenue? admin) {
    final l = context.l;
    return SectionCard(
      title: l.venueDetails,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(l.city),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChipButton(
              key: const ValueKey('venue-city'),
              icon: Icons.place_outlined,
              label: cityById(draft.cityId).name.resolve(context.lang),
              dropdown: true,
              onTap: () async {
                final picked = await showOptionSheet(
                  context,
                  title: l.city,
                  options: {for (final c in kCities) c.id: c.name.resolve(context.lang)},
                  current: draft.cityId,
                );
                if (picked != null) setState(() => draft.cityId = picked);
              },
            ),
          ),
          const SizedBox(height: 16),
          LocalizedField(
            fieldKey: 'venue-name',
            label: l.nameLabel,
            initial: draft.name,
            required: true,
            onChanged: (v) => draft.name = v,
          ),
          const SizedBox(height: 16),
          LocalizedField(
            fieldKey: 'venue-description',
            label: l.descriptionLabel,
            initial: draft.description,
            multiline: true,
            onChanged: (v) => draft.description = v,
          ),
          const SizedBox(height: 16),
          LocalizedField(
            fieldKey: 'venue-address',
            label: l.address,
            initial: draft.address,
            onChanged: (v) => draft.address = v,
          ),
          const SizedBox(height: 16),
          LocalizedField(
            fieldKey: 'venue-district',
            label: l.districtLabel,
            initial: draft.district,
            onChanged: (v) => draft.district = v,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('venue-phone'),
            initialValue: draft.phone,
            keyboardType: TextInputType.phone,
            maxLength: kMaxTextLength,
            decoration: InputDecoration(labelText: l.phone, counterText: ''),
            onChanged: (v) => draft.phone = v,
          ),
          const SizedBox(height: 16),
          FieldLabel(l.amenities),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in kAmenityKeys)
                FilterChip(
                  key: ValueKey('amenity-$key'),
                  label: Text(amenityText(l, key)),
                  selected: draft.amenities.contains(key),
                  onSelected: (on) => setState(() {
                    // Kept in the canonical order.
                    final chosen = {...draft.amenities};
                    on ? chosen.add(key) : chosen.remove(key);
                    draft.amenities = [for (final k in kAmenityKeys) if (chosen.contains(k)) k];
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AdminSwitch(
            key: const ValueKey('venue-active'),
            label: l.activeLabel,
            hint: l.activeHint,
            value: draft.active,
            onChanged: (v) => setState(() => draft.active = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('save-venue'),
            onPressed: _saving ? null : _saveVenue,
            child: Text(l.saveLabel),
          ),
          if (admin != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('delete-venue'),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: () => _deleteVenue(admin),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(l.deleteVenue),
            ),
          ],
        ],
      ),
    );
  }

  Widget _courts(BuildContext context, AdminVenue? admin, Map<String, AdminSport> sports, {required bool loading}) {
    final l = context.l;
    if (admin == null) {
      return SectionCard(
        title: l.courts,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Text(l.saveVenueFirst, style: AppText.muted),
      );
    }
    final venue = admin.venue;
    final currency = cityById(venue.cityId).currency;
    final firstSport = sports.values.where((s) => s.active && s.sport.bookable).firstOrNull?.sport.id;

    return SectionCard(
      title: l.courts,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (venue.courts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l.noCourts, style: AppText.muted),
            ),
          for (final court in venue.courts)
            _CourtRow(
              court: court,
              sportName: sports[court.sportId]?.sport.name.resolve(context.lang) ?? court.sportId,
              priceText: money(l, court.basePrice, currency),
              active: !admin.inactiveCourtIds.contains(court.id),
              onEdit: () => _editCourt(venue, CourtDraft.from(court, active: !admin.inactiveCourtIds.contains(court.id))),
              onDuplicate: () => adminWrite(context, ref, () => ref.read(adminRepositoryProvider).duplicateCourt(court.id)),
              onDelete: () => _deleteCourt(court),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('add-court'),
            onPressed: firstSport == null
                ? null
                : () => _editCourt(venue, CourtDraft(venueId: venue.id, sportId: firstSport)),
            icon: const Icon(Icons.add_rounded),
            label: Text(l.addCourt),
          ),
        ],
      ),
    );
  }

  Widget _owners(BuildContext context, AdminVenue? admin) {
    final l = context.l;
    // Before the first save the courts card already says what to do.
    if (admin == null) return const SizedBox.shrink();
    return SectionCard(
      title: l.ownersTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (admin.owners.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l.noOwners, style: AppText.muted),
            ),
          for (final owner in admin.owners)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  InitialAvatar(name: owner.name, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(owner.name, style: AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (owner.phone != null && owner.phone!.isNotEmpty)
                          Text(owner.phone!, style: AppText.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey('remove-owner-${owner.userId}'),
                    tooltip: l.removeOwner,
                    onPressed: () => adminWrite(
                      context,
                      ref,
                      () => ref.read(adminRepositoryProvider).setOwner(admin.venue.id, owner.userId, assigned: false),
                    ),
                    icon: const Icon(Icons.person_remove_outlined, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            key: const ValueKey('assign-owner'),
            onPressed: () => _assignOwner(admin),
            icon: const Icon(Icons.person_add_alt_rounded),
            label: Text(l.assignOwner),
          ),
        ],
      ),
    );
  }
}

enum _CourtAction { edit, duplicate, delete }

class _CourtRow extends StatelessWidget {
  const _CourtRow({
    required this.court,
    required this.sportName,
    required this.priceText,
    required this.active,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Court court;
  final String sportName;
  final String priceText;
  final bool active;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final details = [sportName, l.slotLength(court.slotMinutes), priceText, court.indoor ? l.indoor : l.outdoor].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.page,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
            child: Row(
              children: [
                SportBadge(sportId: court.sportId, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        court.name.resolve(context.lang),
                        style: manrope(15.5, 800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(details, style: AppText.muted, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (!active) ...[const SizedBox(height: 6), const InactivePill()],
                    ],
                  ),
                ),
                PopupMenuButton<_CourtAction>(
                  key: ValueKey('court-menu-${court.id}'),
                  tooltip: l.courtActions,
                  onSelected: (action) => switch (action) {
                    _CourtAction.edit => onEdit(),
                    _CourtAction.duplicate => onDuplicate(),
                    _CourtAction.delete => onDelete(),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: _CourtAction.edit, child: Text(l.editLabel)),
                    PopupMenuItem(value: _CourtAction.duplicate, child: Text(l.duplicateLabel)),
                    PopupMenuItem(
                      value: _CourtAction.delete,
                      child: Text(l.deleteLabel, style: manrope(14.5, 700, color: AppColors.error)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
