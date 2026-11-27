import 'package:flutter/material.dart' show TimeOfDay;

import '../domain/brackets.dart';
import '../domain/tournaments.dart';

/// What a tournament's organisers (and admins) do with its draws and matches
/// (M8a design §5–§7). Every failure is a [TournamentException]:
/// `notAllowed` for someone who does not organise the tournament, then
/// `notFound`, `invalidArgument` or the bracket errors named below.
///
/// The draw calls return the category's draw as the caller sees it
/// afterwards.
abstract class OrganizerRepository {
  /// Active tournaments the player is a named organiser of, earliest first.
  Future<List<TournamentSummary>> organizedTournaments();

  /// Every entry of the tournament, any state, with names and phones (as the
  /// admin's participants list).
  Future<List<AdminRegistration>> entries(String tournamentId);

  /// Makes, or makes again, the category's draft from its registered
  /// entries. Groups need [groupSize] 3 or 4 and [advance] 1 or 2.
  /// `tooFewEntries` under 2 entries (3 for groups); `drawPublished` once
  /// published.
  Future<CategoryDraw> makeDraw(String categoryId, DrawFormat format, {int? groupSize, int? advance});

  /// Swaps two entries of a draft: their seeds (knockout) or their groups.
  Future<CategoryDraw> swapEntries(String categoryId, String registrationA, String registrationB);

  /// Shows the draft to everyone and locks the category's entries.
  /// `drawOutdated` when entries changed since it was made.
  Future<CategoryDraw> publish(String categoryId);

  /// Throws a published draw away and makes a new draft, until the first
  /// score (`drawFinal` after). `invalidArgument` for a draft.
  Future<CategoryDraw> redo(String categoryId);

  /// Sets, moves or (a null [startsAt]) clears a match's court and time
  /// (wall-clock). At a venue: one slot of a court of the venue on the
  /// tournament's dates (`slotTaken`, `playerBusy`, `inPast`). Without a
  /// venue: no court, an optional [placeNote] of up to 100 characters.
  Future<TournamentMatch> scheduleMatch(String matchId, {String? courtId, DateTime? startsAt, String? placeNote});

  /// Lays the unscheduled matches of the ticked categories ([categoryIds]
  /// null: all) into free slots of [courtIds] on [day] from [from].
  Future<FillResult> fillDay(
    String tournamentId,
    DateTime day,
    List<String> courtIds,
    TimeOfDay from, {
    List<String>? categoryIds,
  });

  /// Enters or corrects a match's result. [winner] for walkovers,
  /// retirements, deciders and to settle a level score; [sets] for played,
  /// retired and decider matches. `drawNotAllowed` for a level knockout
  /// score; `nextMatchPlayed` once the match that depends on it has a score.
  Future<CategoryDraw> enterScore(String matchId, MatchOutcome outcome, {Side? winner, List<List<int>>? sets});

  /// Withdraws an entry from a published draw: its unplayed matches become
  /// walkovers.
  Future<CategoryDraw> withdraw(String registrationId);
}
