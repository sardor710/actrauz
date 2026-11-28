import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/markets.dart';
import '../../core/money.dart';
import '../../domain/booking_engine.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/teams.dart';
import '../../l10n/gen/app_localizations.dart';

extension ContextL10n on BuildContext {
  AppLocalizations get l => AppLocalizations.of(this);

  /// Language code for admin-entered content and date formatting.
  String get lang => Localizations.localeOf(this).languageCode;
}

/// "250 000 soʻm" / "12 000 ₸": always the venue's own currency.
String money(AppLocalizations l, int amount, Currency currency) {
  final label = switch (currency) {
    Currency.uzs => l.currencyUzs,
    Currency.kzt => l.currencyKzt,
  };
  return '${groupThousands(amount)} $label';
}

/// Another player's name as the screens show it: "Deleted player" once
/// their account is gone (the name is empty by then).
String playerName(AppLocalizations l, String name, {required bool deleted}) => deleted ? l.deletedPlayer : name;

String _two(int n) => n.toString().padLeft(2, '0');

/// 24-hour clock in every language.
String hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String minutesHm(int minutes) => '${_two(minutes ~/ 60)}:${_two(minutes % 60)}';

String timeRange(DateTime start, DateTime end) => '${hm(start)}–${hm(end)}';

String hoursText(AppLocalizations l, DayHours? hours) =>
    hours == null ? l.closed : '${minutesHm(hours.openMinute)}–${minutesHm(hours.closeMinute)}';

/// "Today", "Tomorrow", or "Tue, 24 Nov" in the app language.
String dayLabel(AppLocalizations l, String lang, DateTime date, DateTime now) {
  final days = dateOnly(date).difference(dateOnly(now)).inDays;
  if (days == 0) return l.today;
  if (days == 1) return l.tomorrow;
  return DateFormat('EEE, d MMM', lang).format(date);
}

String weekdayShort(String lang, DateTime date) => DateFormat('EEE', lang).format(date);

IconData sportIcon(String iconKey) => switch (iconKey) {
  'football' => Icons.sports_soccer,
  'tennis' => Icons.sports_tennis,
  'padel' => Icons.sports_tennis,
  'basketball' => Icons.sports_basketball,
  'volleyball' => Icons.sports_volleyball,
  _ => Icons.sports,
};

String amenityText(AppLocalizations l, String key) => switch (key) {
  'parking' => l.amenityParking,
  'showers' => l.amenityShowers,
  'lighting' => l.amenityLighting,
  'cafe' => l.amenityCafe,
  'rental' => l.amenityRental,
  _ => key,
};

String bookingErrorText(AppLocalizations l, Object error) {
  if (error is! BookingException) return l.errGeneric;
  return switch (error.error) {
    BookingError.slotTaken => l.errSlotTaken,
    BookingError.notContiguous => l.errNotContiguous,
    BookingError.tooManyBookings => l.errTooManyBookings(BookingEngine.maxUpcoming),
    BookingError.tooFarAhead => l.errTooFarAhead(BookingEngine.maxDaysAhead),
    BookingError.inPast => l.errInPast,
    BookingError.holdExpired => l.holdExpiredMsg,
    BookingError.notAllowed => l.errNotAllowed,
    BookingError.notMarkable => l.markAfterStart,
    BookingError.nameRequired => l.customerNameRequired,
    BookingError.invalidHours => l.errInvalidHours,
    BookingError.rulesOverlap => l.errRulesOverlap,
    BookingError.invalidArgument => l.errInvalidArgument,
    BookingError.hasBookings => l.errHasBookings,
    BookingError.alreadyExists => l.errAlreadyExists,
    BookingError.notFound => l.errNotFound,
    BookingError.tournamentBlock => l.errTournamentBlock,
    _ => l.errGeneric,
  };
}

String joinErrorText(AppLocalizations l, Object error) {
  if (error is! JoinException) return l.errGeneric;
  return switch (error.error) {
    JoinError.full => l.errGameFull,
    JoinError.alreadyJoined => l.errAlreadyJoined,
    JoinError.levelOutOfRange => l.errLevel,
    JoinError.notParticipant => l.errNotParticipant,
    JoinError.hostCannotLeave => l.errHostCannotLeave,
    JoinError.notFound => l.errNotFound,
    JoinError.alreadyRequested => l.errAlreadyRequested,
    JoinError.reliabilityTooLow => l.reliabilityBlockedHint,
    JoinError.bookingNotUsable => l.errBookingNotUsable,
    JoinError.gameExists => l.errGameExists,
    JoinError.invalidArgument => l.errInvalidArgument,
    JoinError.inPast => l.errInPast,
    JoinError.tooFarAhead => l.errTooFarAhead(BookingEngine.maxDaysAhead),
    JoinError.forbidden => l.errForbidden,
    JoinError.notCancellable => l.errNotCancellable,
    JoinError.scoreClosed => l.errScoreClosed,
    JoinError.alreadyReported => l.errAlreadyReported,
    JoinError.teamLimit => l.errTeamLimit(Team.maxCaptained),
    JoinError.captainCannotLeave => l.errCaptainCannotLeave,
    JoinError.nameTaken => l.errTeamNameTaken,
    JoinError.alreadyInTeam => l.errAlreadyInTeam,
    JoinError.alreadyAskedTeam => l.errAlreadyAskedTeam,
    JoinError.captainOnly => l.errCaptainOnly,
    JoinError.windowClosed => l.errWindowClosed,
    JoinError.unavailable => l.errUnavailable,
  };
}
