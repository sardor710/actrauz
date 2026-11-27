import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/booking_engine.dart';
import '../auth/auth_repository.dart';
import '../../domain/games.dart';
import '../../domain/tournaments.dart';

/// The database functions raise their rule violations as an error whose
/// message is a code (`slot_taken`, `full`, …). These turn that code back
/// into the exception the screens already handle.

const _bookingErrors = <String, BookingError>{
  'slot_taken': BookingError.slotTaken,
  'not_contiguous': BookingError.notContiguous,
  'empty_selection': BookingError.emptySelection,
  'in_past': BookingError.inPast,
  'too_far_ahead': BookingError.tooFarAhead,
  'too_many_bookings': BookingError.tooManyBookings,
  'hold_expired': BookingError.holdExpired,
  'not_found': BookingError.notFound,
  'not_cancellable': BookingError.notCancellable,
  'not_allowed': BookingError.notAllowed,
  'not_markable': BookingError.notMarkable,
  'name_required': BookingError.nameRequired,
  'invalid_argument': BookingError.invalidArgument,
  'invalid_hours': BookingError.invalidHours,
  'rules_overlap': BookingError.rulesOverlap,
  'has_bookings': BookingError.hasBookings,
  'already_exists': BookingError.alreadyExists,
  'reliability_too_low': BookingError.reliabilityTooLow,
};

const _joinErrors = <String, JoinError>{
  'full': JoinError.full,
  'already_joined': JoinError.alreadyJoined,
  'level_out_of_range': JoinError.levelOutOfRange,
  'not_participant': JoinError.notParticipant,
  'host_cannot_leave': JoinError.hostCannotLeave,
  'not_found': JoinError.notFound,
  'already_requested': JoinError.alreadyRequested,
  'reliability_too_low': JoinError.reliabilityTooLow,
  'booking_not_usable': JoinError.bookingNotUsable,
  'game_exists': JoinError.gameExists,
  'invalid_argument': JoinError.invalidArgument,
  'in_past': JoinError.inPast,
  'too_far_ahead': JoinError.tooFarAhead,
  'forbidden': JoinError.forbidden,
  'not_cancellable': JoinError.notCancellable,
  'score_closed': JoinError.scoreClosed,
};

/// What the score calls (`enter_score`, `confirm_score`, `dispute_score`)
/// mean by codes other calls use differently (ruling R1): `already_exists` is a
/// result that can no longer change, `not_allowed` a score that is not the
/// player's to enter.
const kScoreErrors = <String, JoinError>{
  'not_allowed': JoinError.forbidden,
  'already_exists': JoinError.scoreClosed,
};

/// What `create_game` means by `not_allowed`: a team game posted by someone
/// who is not the team's captain.
const kCreateGameErrors = <String, JoinError>{'not_allowed': JoinError.forbidden};

/// What `report_player` means by `already_exists` (ruling R1): an open report
/// about the same player and game.
const kReportErrors = <String, JoinError>{'already_exists': JoinError.alreadyReported};

/// What the team calls mean by their own codes, and by `not_allowed` (not
/// the captain).
const kTeamErrors = <String, JoinError>{
  'team_limit': JoinError.teamLimit,
  'captain_cannot_leave': JoinError.captainCannotLeave,
  'not_allowed': JoinError.forbidden,
};

/// [kTeamErrors] for `create_team` and `update_team`, where `already_exists`
/// is a name taken in the city and sport (ruling R1).
const kTeamEditErrors = <String, JoinError>{...kTeamErrors, 'already_exists': JoinError.nameTaken};

const _tournamentErrors = <String, TournamentError>{
  'full': TournamentError.full,
  'deadline_passed': TournamentError.deadlinePassed,
  'level_out_of_range': TournamentError.levelOutOfRange,
  'already_registered': TournamentError.alreadyRegistered,
  'partner_unavailable': TournamentError.partnerUnavailable,
  'not_full': TournamentError.notFull,
  'waitlist_closed': TournamentError.waitlistClosed,
  'not_found': TournamentError.notFound,
  'invalid_argument': TournamentError.invalidArgument,
  'has_registrations': TournamentError.hasRegistrations,
  'reliability_too_low': TournamentError.reliabilityTooLow,
  'rate_limited': TournamentError.rateLimited,
  'not_allowed': TournamentError.notAllowed,
  'not_markable': TournamentError.notMarkable,
};

/// The rule a failed booking call broke, or `unavailable` for anything else
/// (no connection, expired session, a server fault).
BookingException bookingExceptionFor(Object error) {
  if (error is BookingException) return error;
  final code = error is PostgrestException ? _bookingErrors[error.message] : null;
  return BookingException(code ?? BookingError.unavailable);
}

/// [codes] are the meanings one call gives to codes, ahead of the common ones.
JoinException joinExceptionFor(Object error, [Map<String, JoinError> codes = const {}]) {
  if (error is JoinException) return error;
  final code = error is PostgrestException ? codes[error.message] ?? _joinErrors[error.message] : null;
  return JoinException(code ?? JoinError.unavailable);
}

TournamentException tournamentExceptionFor(Object error) {
  if (error is TournamentException) return error;
  final code = error is PostgrestException ? _tournamentErrors[error.message] : null;
  return TournamentException(code ?? TournamentError.unavailable);
}

/// What a failed `delete-account` call means to the app: 403
/// `{"error": "admin_account"}` is an [AdminAccountException]; 401 (from the
/// function or the gateway) is a [SessionInvalidException]; anything else is
/// returned as it is.
Object deleteAccountErrorFor(Object error) {
  if (error is FunctionException && error.status == 401) return const SessionInvalidException();
  if (error is FunctionException && error.status == 403) {
    var details = error.details;
    if (details is String) {
      try {
        details = jsonDecode(details);
      } on FormatException {
        // Plain text: not the refusal.
      }
    }
    if (details is Map && details['error'] == 'admin_account') return const AdminAccountException();
  }
  return error;
}

/// Runs a booking call; every failure surfaces as a [BookingException].
Future<T> guardBooking<T>(Future<T> Function() call) async {
  try {
    return await call();
  } catch (e) {
    throw bookingExceptionFor(e);
  }
}

/// Runs a game call; every failure surfaces as a [JoinException]. [codes]:
/// see [joinExceptionFor].
Future<T> guardJoin<T>(Future<T> Function() call, {Map<String, JoinError> codes = const {}}) async {
  try {
    return await call();
  } catch (e) {
    throw joinExceptionFor(e, codes);
  }
}

/// Runs a tournament call; every failure surfaces as a [TournamentException].
Future<T> guardTournament<T>(Future<T> Function() call) async {
  try {
    return await call();
  } catch (e) {
    throw tournamentExceptionFor(e);
  }
}
