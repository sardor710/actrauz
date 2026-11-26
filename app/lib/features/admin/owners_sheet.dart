import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/admin.dart';
import '../../state/admin_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// Finds a user by name or phone to make them an owner (product spec §12.3).
/// Returns the chosen user; people in [exclude] are already owners and are
/// not offered.
Future<OwnerRef?> showOwnerSearch(BuildContext context, {Set<String> exclude = const {}, String? title}) =>
    showModalBottomSheet<OwnerRef>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _OwnerSearchSheet(exclude: exclude, title: title),
    );

class _OwnerSearchSheet extends ConsumerStatefulWidget {
  const _OwnerSearchSheet({required this.exclude, this.title});

  final Set<String> exclude;

  /// Defaults to "Assign owner".
  final String? title;

  @override
  ConsumerState<_OwnerSearchSheet> createState() => _OwnerSearchSheetState();
}

class _OwnerSearchSheetState extends ConsumerState<_OwnerSearchSheet> {
  String _query = '';
  List<OwnerRef>? _results;
  bool _failed = false;

  Future<void> _search(String text) async {
    final query = text.trim();
    setState(() {
      _query = query;
      _failed = false;
      if (query.length < 2) _results = null;
    });
    if (query.length < 2) return;
    try {
      final found = await ref.read(adminRepositoryProvider).searchUsers(query);
      // Only the answer to the latest query counts.
      if (mounted && query == _query) setState(() => _results = found);
    } catch (_) {
      if (mounted && query == _query) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final results = _results?.where((u) => !widget.exclude.contains(u.userId)).toList();

    Widget body;
    if (_failed) {
      body = EmptyState(icon: Icons.error_outline, text: l.errGeneric);
    } else if (_query.length < 2) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(l.searchUsersMin, style: AppText.muted, textAlign: TextAlign.center),
      );
    } else if (results == null) {
      body = const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    } else if (results.isEmpty) {
      body = EmptyState(icon: Icons.person_search_outlined, text: l.noUsersFound);
    } else {
      body = Column(
        children: [
          for (final user in results)
            ListTile(
              key: ValueKey('user-${user.userId}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: InitialAvatar(name: user.name, size: 40),
              title: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: user.phone == null ? null : Text(user.phone!),
              trailing: const Icon(Icons.person_add_alt_rounded, color: AppColors.primaryDark),
              onTap: () => Navigator.of(context).pop(user),
            ),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title ?? l.assignOwner, style: AppText.title),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('owner-search'),
                autofocus: true,
                decoration: InputDecoration(labelText: l.searchUsers, prefixIcon: const Icon(Icons.search_rounded)),
                onChanged: _search,
              ),
              const SizedBox(height: 8),
              body,
            ],
          ),
        ),
      ),
    );
  }
}
