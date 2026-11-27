import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/tournaments.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'tournament_tools.dart';

/// One of the player's entries: its state, who they play with, and what they
/// can do about it (answer an invite, claim an offered spot, cancel). Shown in
/// the tournament and in My tournaments.
///
/// [registrationOpen] gates everything the deadline closes: answering an
/// invite and cancelling. An offered spot can still be claimed, since an admin
/// may offer one after the deadline. Once the category's draw is published
/// there is no cancelling either.
class RegistrationBlock extends ConsumerWidget {
  const RegistrationBlock({super.key, required this.registration, required this.cityId, required this.registrationOpen});

  final Registration registration;
  final String cityId;
  final bool registrationOpen;

  bool get _isMember =>
      registration.role == RegistrationRole.registrant ||
      (registration.role == RegistrationRole.partner && registration.partnerConfirmed);

  Future<void> _answer(BuildContext context, WidgetRef ref, {required bool accept}) => runTournamentAction(
    context,
    ref,
    () => ref.read(tournamentRepositoryProvider).respondPartner(registration.id, accept: accept),
  );

  Future<void> _claim(BuildContext context, WidgetRef ref) =>
      runTournamentAction(context, ref, () => ref.read(tournamentRepositoryProvider).claimOffer(registration.id));

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.cancelRegistrationTitle),
        content: Text(l.cancelRegistrationMsg),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.keepRegistration)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.cancelRegistration)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runTournamentAction(context, ref, () => ref.read(tournamentRepositoryProvider).cancel(registration.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final r = registration;
    final now = tournamentNow(ref, cityId);

    final answerable =
        registrationOpen &&
        r.role == RegistrationRole.partner &&
        !r.partnerConfirmed &&
        (r.status == RegistrationStatus.pendingPartner || r.status == RegistrationStatus.waitlisted);
    final canClaim = r.status == RegistrationStatus.offered && _isMember;
    // A published draw locks the category's entries: the backend refuses a
    // cancel with draw_published (M8a §6.4).
    final locked =
        ref.watch(bracketProvider(r.tournamentId)).valueOrNull?.draw(r.categoryId)?.published ?? false;
    final canCancel = registrationOpen && r.status.live && _isMember && !locked;

    final other = r.role == RegistrationRole.partner ? r.registrant : r.partner;
    final line = other == null
        ? null
        : answerable
        ? l.partnerInvitedYou(playerName(l, other.name, deleted: other.deleted))
        : l.pairedWith(playerName(l, other.name, deleted: other.deleted));
    final waitingForPartner =
        r.status == RegistrationStatus.waitlisted &&
        r.kind == CategoryKind.pairs &&
        !r.partnerConfirmed &&
        r.role == RegistrationRole.registrant;

    String? left;
    final offerEnds = r.offerExpiresAt;
    if (r.status == RegistrationStatus.offered && offerEnds != null) {
      final minutes = offerEnds.difference(now).inMinutes.clamp(0, 1 << 30);
      left = l.offerHeld(minutes >= 60 ? l.durationHm(minutes ~/ 60, minutes % 60) : l.durationMin(minutes));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            RegistrationStatusPill(registration: r),
            if (r.status == RegistrationStatus.registered && r.paid)
              Pill(text: l.statusPaid, icon: Icons.check_rounded, color: AppColors.primarySoft, onColor: AppColors.primaryDark),
            if (r.waitlistPlace != null) Text(l.waitlistPlaceLabel(r.waitlistPlace!), style: AppText.caption),
          ],
        ),
        if (line != null) ...[const SizedBox(height: 6), Text(line, style: AppText.bodyStrong)],
        if (waitingForPartner) ...[const SizedBox(height: 4), Text(l.statusPendingPartner, style: AppText.muted)],
        if (left != null) ...[const SizedBox(height: 6), Text(left, style: AppText.muted)],
        if (answerable) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _answer(context, ref, accept: false),
                  child: Text(l.declineLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(onPressed: () => _answer(context, ref, accept: true), child: Text(l.acceptLabel)),
              ),
            ],
          ),
        ],
        if (canClaim) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => _claim(context, ref), child: Text(l.claimLabel)),
          ),
        ],
        if (canCancel) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: () => _cancel(context, ref), child: Text(l.cancelRegistration)),
          ),
        ],
      ],
    );
  }
}
