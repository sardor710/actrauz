import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/games.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/reliability_badge.dart';
import '../common/widgets.dart';

/// Runs a game action and shows the translated reason when the backend
/// refuses. Refreshes everything that depends on games after a success.
/// Returns whether it went through.
Future<bool> runGameAction(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
  final l = context.l;
  try {
    await action();
    refreshGames(ref);
    return true;
  } on JoinException catch (e) {
    if (context.mounted) showMessage(context, joinErrorText(l, e));
  }
  return false;
}

/// Spots as a stepper, 2 to 30 like the database.
class SpotsStepper extends StatelessWidget {
  const SpotsStepper({super.key, required this.value, required this.onChanged});

  static const min = 2;
  static const max = 30;

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: l.fewerSpots,
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 48,
          child: Text('$value', textAlign: TextAlign.center, style: manrope(20, 800)),
        ),
        IconButton.filledTonal(
          tooltip: l.moreSpots,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// Pending requests to join, for the host: level, reliability, approve or decline.
class JoinRequestsSection extends ConsumerWidget {
  const JoinRequestsSection({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    if (game.joinRequests.isEmpty) return const SizedBox.shrink();
    final repo = ref.read(gameRepositoryProvider);
    String nameOf(GameMember m) => playerName(l, m.name, deleted: m.deleted);

    return SectionCard(
      title: '${l.requestsTitle} · ${game.joinRequests.length}',
      child: Column(
        children: [
          for (final request in game.joinRequests)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InitialAvatar(name: nameOf(request.member), size: 42, deleted: request.member.deleted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nameOf(request.member), style: manrope(15.5, 700)),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Pill(
                                  text: l.level(request.member.level),
                                  icon: Icons.bar_chart_rounded,
                                  color: AppColors.primarySoft,
                                  onColor: AppColors.primaryDark,
                                ),
                                ReliabilityPill(reliability: request.member.reliability),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () =>
                              runGameAction(context, ref, () => repo.decideRequest(request.id, approve: false)),
                          child: Text(l.declineLabel),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
                          onPressed: () =>
                              runGameAction(context, ref, () => repo.decideRequest(request.id, approve: true)),
                          child: Text(l.approveLabel),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Asks the host before removing a player. Returns `true` to go ahead.
Future<bool> confirmRemovePlayer(BuildContext context, String name) async {
  final l = context.l;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.removePlayerTitle(name)),
      content: Text(l.removePlayerMsg),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.removeLabel)),
      ],
    ),
  );
  return ok == true;
}

/// Edit, and cancel, for the host.
class HostToolsSection extends ConsumerWidget {
  const HostToolsSection({super.key, required this.game, required this.onCancelled});

  final Game game;

  /// Called once the game is cancelled, so the screen can leave it.
  final VoidCallback onCancelled;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final choice = await showCancelGameDialog(context, hasBooking: game.bookingId != null);
    if (choice == null || !context.mounted) return;
    final done = await runGameAction(
      context,
      ref,
      () => ref.read(gameRepositoryProvider).cancelGame(game.id, cancelBooking: choice.cancelBooking),
    );
    if (!done || !context.mounted) return;
    if (choice.cancelBooking) refreshBookings(ref);
    showMessage(context, l.gameCancelled);
    onCancelled();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return SectionCard(
      title: l.hostTools,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showEditGameSheet(context, game),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l.editGame),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: () => _cancel(context, ref),
              child: Text(l.cancelGame),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the host chose when cancelling.
typedef CancelChoice = ({bool cancelBooking});

/// Asks before cancelling. With a court booking under the game the host may
/// cancel it too; by default it stays. Null when the host keeps the game.
Future<CancelChoice?> showCancelGameDialog(BuildContext context, {required bool hasBooking}) {
  final l = context.l;
  var cancelBooking = false;
  return showDialog<CancelChoice>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(l.cancelGameTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.cancelGameMsg),
            if (hasBooking)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: cancelBooking,
                onChanged: (v) => setState(() => cancelBooking = v ?? false),
                title: Text(l.alsoCancelBooking),
                subtitle: Text(l.alsoCancelBookingHint),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.keepGame)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop((cancelBooking: cancelBooking)),
            child: Text(l.cancelGame),
          ),
        ],
      ),
    ),
  );
}

/// The host's note and number of spots. Returns `true` when saved.
Future<bool?> showEditGameSheet(BuildContext context, Game game) => showModalBottomSheet<bool>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _EditGameSheet(game: game),
);

class _EditGameSheet extends ConsumerStatefulWidget {
  const _EditGameSheet({required this.game});

  final Game game;

  @override
  ConsumerState<_EditGameSheet> createState() => _EditGameSheetState();
}

class _EditGameSheetState extends ConsumerState<_EditGameSheet> {
  late final _note = TextEditingController(text: widget.game.note ?? '');
  late int _spots = widget.game.spots;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(gameRepositoryProvider).updateGame(widget.game.id, note: _note.text, spots: _spots);
      refreshGames(ref);
      if (mounted) Navigator.of(context).pop(true);
    } on JoinException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // The one way to get this wrong here is too few spots.
        _error = e.error == JoinError.invalidArgument ? l.errSpotsBelowPlayers : joinErrorText(l, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Padding(
      // Keeps the form above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.editGame, style: AppText.title),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text(l.spotsLabel, style: AppText.bodyStrong)),
                  SpotsStepper(value: _spots, onChanged: (v) => setState(() => _spots = v)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('edit-note'),
                controller: _note,
                maxLength: 200,
                maxLines: 2,
                decoration: InputDecoration(labelText: l.noteLabel),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: manrope(13.5, 600, color: AppColors.error)),
              ],
              const SizedBox(height: 12),
              FilledButton(onPressed: _busy ? null : _save, child: Text(l.saveLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
