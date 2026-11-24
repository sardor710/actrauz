import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/booking_engine.dart';
import '../../domain/games.dart';

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
