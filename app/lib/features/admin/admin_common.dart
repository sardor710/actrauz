import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/booking_engine.dart';
import '../../state/admin_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// Widest the admin lists and forms grow on a desktop screen.
const kAdminMaxWidth = 900.0;

/// Horizontal padding that keeps content in a centred column of at most
/// [maxWidth], with the usual 16 px gutter on a phone.
double adminGutter(double width, {double maxWidth = kAdminMaxWidth}) => math.max(16, (width - maxWidth) / 2);

/// Scaffold for an admin page: back to [fallback], a title, an optional
/// add button, and [body] only for admins (everyone else sees a locked
/// state, as the owner screens do).
class AdminScaffold extends ConsumerWidget {
  const AdminScaffold({
    super.key,
    required this.title,
    required this.fallback,
    required this.body,
    this.actions = const [],
    this.floatingActionButton,
  });

  final String title;

  /// Where the back button goes when there is nothing to pop.
  final String fallback;
  final WidgetBuilder body;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final allowed = isAdmin.valueOrNull == true;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(fallback)),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: allowed ? actions : const [],
      ),
      floatingActionButton: allowed ? floatingActionButton : null,
      body: AsyncBody(
        value: isAdmin,
        builder: (admin) => admin
            ? body(context)
            : Center(child: EmptyState(icon: Icons.lock_outline_rounded, text: context.l.adminOnly)),
      ),
    );
  }
}

/// A scrolling list centred in a column of at most [kAdminMaxWidth].
class AdminListView extends StatelessWidget {
  const AdminListView({super.key, required this.children, this.bottom = 96});

  final List<Widget> children;

  /// Room under the last item, so a floating button never covers it.
  final double bottom;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = adminGutter(constraints.maxWidth);
      return ListView(
        padding: EdgeInsets.fromLTRB(side, 4, side, bottom),
        children: children,
      );
    },
  );
}

/// Runs an admin write; on success refreshes every screen that shows catalog
/// data and says "Saved". Returns whether it succeeded. A refusal with
/// `hasBookings` offers [onDeactivate] instead of only showing the error.
Future<bool> adminWrite(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action, {
  Future<void> Function()? onDeactivate,
}) async {
  final l = context.l;
  try {
    await action();
    refreshAdmin(ref);
    if (context.mounted) showMessage(context, l.savedMsg);
    return true;
  } on BookingException catch (e) {
    if (!context.mounted) return false;
    if (e.error == BookingError.hasBookings && onDeactivate != null) {
      final deactivate = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l.errHasBookings),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.deactivateInstead)),
          ],
        ),
      );
      if (deactivate == true && context.mounted) return adminWrite(context, ref, onDeactivate);
      return false;
    }
    showMessage(context, bookingErrorText(l, e));
    return false;
  } catch (e) {
    if (context.mounted) showMessage(context, bookingErrorText(l, e));
    return false;
  }
}

/// "Delete “Court 1”? This cannot be undone." Returns whether to go ahead.
Future<bool> confirmDelete(BuildContext context, String name) async {
  final l = context.l;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.deleteConfirmTitle(name)),
      content: Text(l.deleteConfirmMsg),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.deleteLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// The "Inactive" label on a venue, court, sport or banner.
class InactivePill extends StatelessWidget {
  const InactivePill({super.key});

  @override
  Widget build(BuildContext context) => Pill(
    text: context.l.inactive,
    icon: Icons.visibility_off_outlined,
    color: AppColors.amberSoft,
    onColor: const Color(0xFF7A4B00),
  );
}

/// Opens an admin form sheet: scrollable, above the keyboard.
Future<bool?> showAdminSheet(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<bool>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: builder,
);

/// The common frame of an admin form sheet: title, fields, inline error and
/// a save button, kept above the on-screen keyboard.
class AdminSheetFrame extends StatelessWidget {
  const AdminSheetFrame({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    required this.saveKey,
    this.error,
    this.busy = false,
    this.extraAction,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final Key saveKey;
  final String? error;
  final bool busy;

  /// Shown under the save button, for example Delete.
  final Widget? extraAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppText.title),
            const SizedBox(height: 16),
            ...children,
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: manrope(14, 600, color: AppColors.error)),
            ],
            const SizedBox(height: 18),
            FilledButton(key: saveKey, onPressed: busy ? null : onSave, child: Text(context.l.saveLabel)),
            if (extraAction != null) ...[const SizedBox(height: 8), extraAction!],
          ],
        ),
      ),
    ),
  );
}

/// A switch row with a label and an optional hint, used for Active and
/// Indoor.
class AdminSwitch extends StatelessWidget {
  const AdminSwitch({super.key, required this.label, required this.value, required this.onChanged, this.hint});

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: AppText.bodyStrong),
    subtitle: hint == null ? null : Text(hint!, style: AppText.muted),
    value: value,
    onChanged: onChanged,
  );
}

/// Bold label above a control.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: AppText.bodyStrong),
  );
}
