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

JoinException joinExceptionFor(Object error) {
  if (error is JoinException) return error;
  final code = error is PostgrestException ? _joinErrors[error.message] : null;
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

/// Runs a game call; every failure surfaces as a [JoinException].
Future<T> guardJoin<T>(Future<T> Function() call) async {
  try {
    return await call();
  } catch (e) {
    throw joinExceptionFor(e);
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
