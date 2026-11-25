import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/sample/sample_data.dart';
import '../../data/sample/sample_media.dart';
import '../../domain/tournaments.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// Wall-clock time in the tournament's city.
DateTime tournamentNow(WidgetRef ref, String cityId) =>
    venueNow(cityById(cityId), utcNow: ref.watch(clockProvider)());

String tournamentErrorText(AppLocalizations l, Object error) {
  if (error is! TournamentException) return l.errGeneric;
  return switch (error.error) {
    TournamentError.full => l.errTournamentFull,
    TournamentError.deadlinePassed => l.errDeadlinePassed,
    TournamentError.levelOutOfRange => l.errTournamentLevel,
    TournamentError.alreadyRegistered => l.errAlreadyRegistered,
    TournamentError.partnerUnavailable => l.errPartnerUnavailable,
    TournamentError.notFull => l.errNotFull,
    TournamentError.waitlistClosed => l.errWaitlistClosed,
    TournamentError.notFound => l.errNotFound,
    TournamentError.invalidArgument => l.errInvalidArgument,
    TournamentError.reliabilityTooLow => l.reliabilityBlockedHint,
    TournamentError.rateLimited => l.errRateLimited,
    TournamentError.unavailable => l.errUnavailable,
    TournamentError.hasRegistrations || TournamentError.notAllowed || TournamentError.notMarkable => l.errGeneric,
  };
}

/// Runs a registration action and shows the translated reason when the
/// backend refuses. Reloads everything that depends on tournaments either way
/// (a refusal usually means the screen was out of date). Returns whether it
/// went through.
Future<bool> runTournamentAction(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
  final l = context.l;
  var done = false;
  String? message;
  try {
    await action();
    done = true;
  } on TournamentException catch (e) {
    message = tournamentErrorText(l, e);
  }
  if (!context.mounted) return done;
  refreshTournaments(ref);
  if (message != null) showMessage(context, message);
  return done;
}

String categoryKindLabel(AppLocalizations l, CategoryKind kind) =>
    kind == CategoryKind.pairs ? l.kindPairs : l.kindSingles;

String categoryGenderLabel(AppLocalizations l, CategoryGender gender) => switch (gender) {
  CategoryGender.men => l.genderMen,
  CategoryGender.women => l.genderWomen,
  CategoryGender.mixed => l.genderMixed,
  CategoryGender.open => l.genderOpen,
};

String registrationStatusLabel(AppLocalizations l, Registration r) => switch (r.status) {
  RegistrationStatus.pendingPartner => r.role == RegistrationRole.partner ? l.statusInvited : l.statusPendingPartner,
  RegistrationStatus.registered => l.statusRegistered,
  RegistrationStatus.waitlisted => l.statusWaitlisted,
  RegistrationStatus.offered => l.statusOffered,
  RegistrationStatus.declined => l.statusDeclined,
  RegistrationStatus.expired => l.statusExpired,
  RegistrationStatus.cancelled => l.statusCancelled,
  RegistrationStatus.removed => l.statusRemoved,
  RegistrationStatus.lapsed => l.statusLapsed,
};

/// "1 200 000 UZS" or "Free".
String feeText(AppLocalizations l, int fee, Currency currency) => fee == 0 ? l.tournamentFree : money(l, fee, currency);

/// "Free", "300 000 UZS" or "300 000 – 500 000 UZS".
String feeRangeText(AppLocalizations l, int min, int max, Currency currency) {
  if (min == max) return feeText(l, min, currency);
  final low = min == 0 ? l.tournamentFree : groupThousands(min);
  return '$low – ${money(l, max, currency)}';
}

/// "12 Dec" style range, or one day.
String tournamentDates(AppLocalizations l, String lang, Tournament t, DateTime now) =>
    datesText(l, lang, t.start, t.end, now);

String datesText(AppLocalizations l, String lang, DateTime start, DateTime end, DateTime now) => start == end
    ? dayLabel(l, lang, start, now)
    : '${dayLabel(l, lang, start, now)} – ${dayLabel(l, lang, end, now)}';

/// The cover photo, or a colour block with the sport's icon. The bundled demo
/// tournaments keep their own photos.
class TournamentCover extends StatelessWidget {
  const TournamentCover({
    super.key,
    required this.id,
    required this.sportId,
    this.coverUrl,
    this.colorSeed = 0,
    this.width,
    this.height,
    this.radius = 14,
    this.darken = 0,
    this.child,
  });

  final String id;
  final String sportId;
  final String? coverUrl;
  final int colorSeed;
  final double? width;
  final double? height;
  final double radius;
  final double darken;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final url = coverUrl;
    if (url == null && kTournamentSeeds.any((t) => t.id == id)) {
      return PhotoBox(
        asset: tournamentPhoto(id),
        width: width,
        height: height,
        radius: radius,
        darken: darken,
        child: child,
      );
    }
    final tint = tintFor('$colorSeed');
    final fallback = ColoredBox(
      color: tint.background,
      child: Center(child: SportBadge(sportId: sportId, size: (height ?? 104) * 0.4)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url == null)
              fallback
            else
              Image.network(url, fit: BoxFit.cover, errorBuilder: (context, error, stack) => fallback),
            if (darken > 0) ColoredBox(color: Colors.black.withValues(alpha: darken)),
            ?child,
          ],
        ),
      ),
    );
  }
}

/// A registration's state as a pill.
class RegistrationStatusPill extends StatelessWidget {
  const RegistrationStatusPill({super.key, required this.registration});

  final Registration registration;

  @override
  Widget build(BuildContext context) {
    final (color, onColor) = switch (registration.status) {
      RegistrationStatus.registered => (AppColors.primarySoft, AppColors.primaryDark),
      RegistrationStatus.pendingPartner ||
      RegistrationStatus.waitlisted ||
      RegistrationStatus.offered => (AppColors.amberSoft, AppColors.ink),
      RegistrationStatus.declined || RegistrationStatus.removed => (AppColors.errorSoft, AppColors.error),
      _ => (AppColors.field, AppColors.muted),
    };
    return Pill(text: registrationStatusLabel(context.l, registration), color: color, onColor: onColor);
  }
}

/// A coloured strip with an icon and one sentence.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.text, this.error = false});

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.error : AppColors.primaryDark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error ? AppColors.errorSoft : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: manrope(14, 700, color: color))),
        ],
      ),
    );
  }
}
