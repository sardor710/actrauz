import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/admin.dart';
import '../../state/admin_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'admin_common.dart';
import 'localized_field.dart';

/// Home-screen banners, active or not (product spec §12.6); added, edited
/// and deleted in a sheet. Banners keep their placeholder artwork for now.
class AdminBannersScreen extends StatelessWidget {
  const AdminBannersScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      AdminScaffold(title: context.l.adminBanners, fallback: '/admin', body: (_) => const _BannerList());
}

String _cityText(BuildContext context, String? cityId) {
  if (cityId == null) return context.l.allCities;
  return kCities.where((c) => c.id == cityId).firstOrNull?.name.resolve(context.lang) ?? cityId;
}

class _BannerList extends ConsumerWidget {
  const _BannerList();

  Future<void> _open(BuildContext context, WidgetRef ref, BannerDraft draft) async {
    final saved = await showAdminSheet(context, (_) => _BannerSheet(draft: draft));
    if (saved == true && context.mounted) {
      refreshAdmin(ref);
      showMessage(context, context.l.savedMsg);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return AsyncBody(
      value: ref.watch(adminBannersProvider),
      builder: (banners) => AdminListView(
        bottom: 24,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('add-banner'),
              style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: () {
                // A new banner goes first, where players see it.
                final first = banners.isEmpty ? 1 : banners.map((b) => b.sortOrder).reduce((a, b) => a < b ? a : b);
                _open(context, ref, BannerDraft(sortOrder: first - 1));
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(l.addBanner),
            ),
          ),
          const SizedBox(height: 12),
          if (banners.isEmpty) EmptyState(icon: Icons.view_carousel_outlined, text: l.noBanners),
          for (final b in banners) ...[
            Card(
              child: InkWell(
                key: ValueKey('admin-banner-${b.id}'),
                onTap: () => _open(context, ref, BannerDraft.from(b)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.title.resolve(context.lang),
                              style: AppText.cardTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _cityText(context, b.cityId),
                              style: AppText.muted,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              b.url,
                              style: manrope(13, 600, color: AppColors.primaryDark),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!b.active) ...[const SizedBox(height: 8), const InactivePill()],
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

class _BannerSheet extends ConsumerStatefulWidget {
  const _BannerSheet({required this.draft});

  final BannerDraft draft;

  @override
  ConsumerState<_BannerSheet> createState() => _BannerSheetState();
}

class _BannerSheetState extends ConsumerState<_BannerSheet> {
  final _form = GlobalKey<FormState>();
  late final BannerDraft _draft = widget.draft;
  late final _url = TextEditingController(text: widget.draft.url);
  late final _order = TextEditingController(text: '${widget.draft.sortOrder}');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    final l = context.l;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
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

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    _draft
      ..url = _url.text.trim()
      ..sortOrder = int.parse(_order.text.trim());
    await _run(() => ref.read(adminRepositoryProvider).saveBanner(_draft));
  }

  Future<void> _delete() async {
    final id = _draft.id!;
    if (!await confirmDelete(context, _draft.title.resolve(context.lang))) return;
    if (mounted) await _run(() => ref.read(adminRepositoryProvider).deleteBanner(id));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Form(
      key: _form,
      child: AdminSheetFrame(
        title: _draft.id == null ? l.newBanner : l.editBanner,
        saveKey: const ValueKey('save-banner'),
        busy: _busy,
        error: _error,
        onSave: _save,
        extraAction: _draft.id == null
            ? null
            : TextButton.icon(
                key: const ValueKey('delete-banner'),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(l.deleteLabel),
              ),
        children: [
          LocalizedField(
            fieldKey: 'banner-title',
            label: l.bannerTitle,
            initial: _draft.title,
            required: true,
            onChanged: (v) => _draft.title = v,
          ),
          const SizedBox(height: 16),
          LocalizedField(
            fieldKey: 'banner-subtitle',
            label: l.bannerSubtitle,
            initial: _draft.subtitle,
            onChanged: (v) => _draft.subtitle = v,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('banner-url'),
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            maxLength: kMaxTextLength,
            decoration: InputDecoration(labelText: l.linkLabel, counterText: ''),
            validator: (v) {
              final url = v?.trim() ?? '';
              return url.startsWith('https://') && url.length > 'https://'.length ? null : l.errUrl;
            },
          ),
          const SizedBox(height: 16),
          FieldLabel(l.city),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChipButton(
              key: const ValueKey('banner-city'),
              icon: Icons.place_outlined,
              label: _cityText(context, _draft.cityId),
              dropdown: true,
              onTap: () async {
                const all = '*';
                final picked = await showOptionSheet(
                  context,
                  title: l.city,
                  options: {all: l.allCities, for (final c in kCities) c.id: c.name.resolve(context.lang)},
                  current: _draft.cityId ?? all,
                );
                if (picked != null) setState(() => _draft.cityId = picked == all ? null : picked);
              },
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('banner-order'),
            controller: _order,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
            decoration: InputDecoration(labelText: l.sortOrderLabel),
            validator: (v) => int.tryParse(v?.trim() ?? '') == null ? l.errInvalidArgument : null,
          ),
          const SizedBox(height: 8),
          AdminSwitch(
            key: const ValueKey('banner-active'),
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
