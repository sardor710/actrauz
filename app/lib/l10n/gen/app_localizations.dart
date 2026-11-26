import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_kk.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_uz.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('kk'),
    Locale('ru'),
    Locale('uz'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Actra'**
  String get appName;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @errGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get errGeneric;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get chooseLanguage;

  /// No description provided for @chooseCity.
  ///
  /// In en, this message translates to:
  /// **'Choose your city'**
  String get chooseCity;

  /// No description provided for @chooseCityHint.
  ///
  /// In en, this message translates to:
  /// **'You can change it any time in your profile'**
  String get chooseCityHint;

  /// No description provided for @detectingCity.
  ///
  /// In en, this message translates to:
  /// **'Finding your city…'**
  String get detectingCity;

  /// No description provided for @cityDetected.
  ///
  /// In en, this message translates to:
  /// **'Found: {city}'**
  String cityDetected(String city);

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInTitle;

  /// No description provided for @signInTelegram.
  ///
  /// In en, this message translates to:
  /// **'Continue with Telegram'**
  String get signInTelegram;

  /// No description provided for @demoNotice.
  ///
  /// In en, this message translates to:
  /// **'Demo mode: Telegram sign-in is connected in the next release. Enter a name to continue. Venues, games and tournaments shown are sample data.'**
  String get demoNotice;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get nameRequired;

  /// No description provided for @telegramHint.
  ///
  /// In en, this message translates to:
  /// **'Telegram will open. Tap Start there and share your phone number — it becomes your Actra account.'**
  String get telegramHint;

  /// No description provided for @telegramWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Telegram. Share your phone number with the Actra bot, then come back here.'**
  String get telegramWaiting;

  /// No description provided for @telegramOpenAgain.
  ///
  /// In en, this message translates to:
  /// **'Open Telegram again'**
  String get telegramOpenAgain;

  /// No description provided for @telegramExpired.
  ///
  /// In en, this message translates to:
  /// **'The sign-in link has expired. Please try again.'**
  String get telegramExpired;

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not sign in. Check your connection and try again.'**
  String get signInFailed;

  /// No description provided for @acceptTerms.
  ///
  /// In en, this message translates to:
  /// **'I accept the Terms of Use and the Privacy Policy'**
  String get acceptTerms;

  /// No description provided for @termsRequired.
  ///
  /// In en, this message translates to:
  /// **'Accept the terms to continue'**
  String get termsRequired;

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabVenues.
  ///
  /// In en, this message translates to:
  /// **'Venues'**
  String get tabVenues;

  /// No description provided for @tabGames.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get tabGames;

  /// No description provided for @tabProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get tabProfile;

  /// No description provided for @greeting.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String greeting(String name);

  /// No description provided for @homeGames.
  ///
  /// In en, this message translates to:
  /// **'Available games'**
  String get homeGames;

  /// No description provided for @homeCourts.
  ///
  /// In en, this message translates to:
  /// **'Free courts today'**
  String get homeCourts;

  /// No description provided for @homeTournaments.
  ///
  /// In en, this message translates to:
  /// **'Tournaments'**
  String get homeTournaments;

  /// No description provided for @noGames.
  ///
  /// In en, this message translates to:
  /// **'No open games yet'**
  String get noGames;

  /// No description provided for @noCourtsToday.
  ///
  /// In en, this message translates to:
  /// **'No free slots left today'**
  String get noCourtsToday;

  /// No description provided for @searchVenues.
  ///
  /// In en, this message translates to:
  /// **'Search venues'**
  String get searchVenues;

  /// No description provided for @allSports.
  ///
  /// In en, this message translates to:
  /// **'All sports'**
  String get allSports;

  /// No description provided for @noVenues.
  ///
  /// In en, this message translates to:
  /// **'No venues found'**
  String get noVenues;

  /// No description provided for @fromPrice.
  ///
  /// In en, this message translates to:
  /// **'from {price}'**
  String fromPrice(String price);

  /// No description provided for @slotLength.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String slotLength(int minutes);

  /// No description provided for @workingHours.
  ///
  /// In en, this message translates to:
  /// **'Working hours'**
  String get workingHours;

  /// No description provided for @closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closed;

  /// No description provided for @weekdays.
  ///
  /// In en, this message translates to:
  /// **'Mon–Fri'**
  String get weekdays;

  /// No description provided for @saturday.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get saturday;

  /// No description provided for @sunday.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get sunday;

  /// No description provided for @amenities.
  ///
  /// In en, this message translates to:
  /// **'Amenities'**
  String get amenities;

  /// No description provided for @amenityParking.
  ///
  /// In en, this message translates to:
  /// **'Parking'**
  String get amenityParking;

  /// No description provided for @amenityShowers.
  ///
  /// In en, this message translates to:
  /// **'Showers'**
  String get amenityShowers;

  /// No description provided for @amenityLighting.
  ///
  /// In en, this message translates to:
  /// **'Lighting'**
  String get amenityLighting;

  /// No description provided for @amenityCafe.
  ///
  /// In en, this message translates to:
  /// **'Café'**
  String get amenityCafe;

  /// No description provided for @amenityRental.
  ///
  /// In en, this message translates to:
  /// **'Equipment rental'**
  String get amenityRental;

  /// No description provided for @courts.
  ///
  /// In en, this message translates to:
  /// **'Courts'**
  String get courts;

  /// No description provided for @indoor.
  ///
  /// In en, this message translates to:
  /// **'Indoor'**
  String get indoor;

  /// No description provided for @outdoor.
  ///
  /// In en, this message translates to:
  /// **'Outdoor'**
  String get outdoor;

  /// No description provided for @book.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get book;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About the venue'**
  String get about;

  /// No description provided for @bookingTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a time'**
  String get bookingTitle;

  /// No description provided for @closedThatDay.
  ///
  /// In en, this message translates to:
  /// **'The court is closed on this day'**
  String get closedThatDay;

  /// No description provided for @selectHint.
  ///
  /// In en, this message translates to:
  /// **'Pick one slot or several in a row'**
  String get selectHint;

  /// No description provided for @slotsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} slot} other{{count} slots}}'**
  String slotsSelected(int count);

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @summaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Booking summary'**
  String get summaryTitle;

  /// No description provided for @heldFor.
  ///
  /// In en, this message translates to:
  /// **'Slots are held for you: {time}'**
  String heldFor(String time);

  /// No description provided for @holdExpiredMsg.
  ///
  /// In en, this message translates to:
  /// **'The hold has expired. Please choose the time again.'**
  String get holdExpiredMsg;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get paymentMethod;

  /// No description provided for @payAtVenue.
  ///
  /// In en, this message translates to:
  /// **'Pay at venue'**
  String get payAtVenue;

  /// No description provided for @payAtVenueHint.
  ///
  /// In en, this message translates to:
  /// **'Cash or card at the venue'**
  String get payAtVenueHint;

  /// No description provided for @playersCount.
  ///
  /// In en, this message translates to:
  /// **'Number of players'**
  String get playersCount;

  /// No description provided for @noteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get noteLabel;

  /// No description provided for @confirmBooking.
  ///
  /// In en, this message translates to:
  /// **'Confirm booking'**
  String get confirmBooking;

  /// No description provided for @bookingConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Booking confirmed'**
  String get bookingConfirmed;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dateLabel;

  /// No description provided for @timeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get timeLabel;

  /// No description provided for @courtLabel.
  ///
  /// In en, this message translates to:
  /// **'Court'**
  String get courtLabel;

  /// No description provided for @errSlotTaken.
  ///
  /// In en, this message translates to:
  /// **'Someone has just taken this time. Choose another one.'**
  String get errSlotTaken;

  /// No description provided for @errNotContiguous.
  ///
  /// In en, this message translates to:
  /// **'Slots must be next to each other'**
  String get errNotContiguous;

  /// No description provided for @errTooManyBookings.
  ///
  /// In en, this message translates to:
  /// **'You already have {count} upcoming bookings'**
  String errTooManyBookings(int count);

  /// No description provided for @errTooFarAhead.
  ///
  /// In en, this message translates to:
  /// **'Booking opens {days} days in advance'**
  String errTooFarAhead(int days);

  /// No description provided for @errInPast.
  ///
  /// In en, this message translates to:
  /// **'This time has already passed'**
  String get errInPast;

  /// No description provided for @myBookings.
  ///
  /// In en, this message translates to:
  /// **'My bookings'**
  String get myBookings;

  /// No description provided for @noBookings.
  ///
  /// In en, this message translates to:
  /// **'You have no bookings yet'**
  String get noBookings;

  /// No description provided for @statusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get statusConfirmed;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @cancelBooking.
  ///
  /// In en, this message translates to:
  /// **'Cancel booking'**
  String get cancelBooking;

  /// No description provided for @cancelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this booking?'**
  String get cancelConfirmTitle;

  /// No description provided for @cancelFreeMsg.
  ///
  /// In en, this message translates to:
  /// **'Cancellation is free.'**
  String get cancelFreeMsg;

  /// No description provided for @cancelLateMsg.
  ///
  /// In en, this message translates to:
  /// **'Less than {hours} hours are left before the start. This counts as a late cancellation and lowers your reliability.'**
  String cancelLateMsg(int hours);

  /// No description provided for @keepBooking.
  ///
  /// In en, this message translates to:
  /// **'Keep booking'**
  String get keepBooking;

  /// No description provided for @bookingCancelled.
  ///
  /// In en, this message translates to:
  /// **'Booking cancelled'**
  String get bookingCancelled;

  /// No description provided for @lateCancellation.
  ///
  /// In en, this message translates to:
  /// **'Late cancellation'**
  String get lateCancellation;

  /// No description provided for @spotsLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Full} one{{count} spot left} other{{count} spots left}}'**
  String spotsLeft(int count);

  /// No description provided for @levelRange.
  ///
  /// In en, this message translates to:
  /// **'Level {min}–{max}'**
  String levelRange(int min, int max);

  /// No description provided for @perPlayer.
  ///
  /// In en, this message translates to:
  /// **'≈ {price} per player'**
  String perPlayer(String price);

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @players.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get players;

  /// No description provided for @joinGame.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinGame;

  /// No description provided for @leaveGame.
  ///
  /// In en, this message translates to:
  /// **'Leave game'**
  String get leaveGame;

  /// No description provided for @errGameFull.
  ///
  /// In en, this message translates to:
  /// **'This game is already full'**
  String get errGameFull;

  /// No description provided for @errLevel.
  ///
  /// In en, this message translates to:
  /// **'Your level is outside the range for this game'**
  String get errLevel;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @entryFee.
  ///
  /// In en, this message translates to:
  /// **'Entry fee'**
  String get entryFee;

  /// No description provided for @filledOf.
  ///
  /// In en, this message translates to:
  /// **'{filled} of {total} filled'**
  String filledOf(int filled, int total);

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'Your upcoming bookings and tournament entries will be cancelled and you will leave your games. Your name and phone number will be removed. This cannot be undone.'**
  String get deleteAccountBody;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAccountConfirm;

  /// No description provided for @deleteAccountAdmin.
  ///
  /// In en, this message translates to:
  /// **'An admin account cannot be deleted. Ask another admin to remove your admin role first.'**
  String get deleteAccountAdmin;

  /// Shown instead of the name of a player who deleted their account (past games, bookings, tournament lists).
  ///
  /// In en, this message translates to:
  /// **'Deleted player'**
  String get deletedPlayer;

  /// No description provided for @currencyUzs.
  ///
  /// In en, this message translates to:
  /// **'UZS'**
  String get currencyUzs;

  /// No description provided for @currencyKzt.
  ///
  /// In en, this message translates to:
  /// **'₸'**
  String get currencyKzt;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search venues and sports'**
  String get searchHint;

  /// No description provided for @gamesBySports.
  ///
  /// In en, this message translates to:
  /// **'Games by sport'**
  String get gamesBySports;

  /// No description provided for @venuesNearYou.
  ///
  /// In en, this message translates to:
  /// **'Venues near you'**
  String get venuesNearYou;

  /// No description provided for @tabTournaments.
  ///
  /// In en, this message translates to:
  /// **'Tournaments'**
  String get tabTournaments;

  /// No description provided for @tabSocial.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get tabSocial;

  /// No description provided for @allDays.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allDays;

  /// No description provided for @filterSport.
  ///
  /// In en, this message translates to:
  /// **'Sport'**
  String get filterSport;

  /// No description provided for @myLevel.
  ///
  /// In en, this message translates to:
  /// **'My level'**
  String get myLevel;

  /// No description provided for @going.
  ///
  /// In en, this message translates to:
  /// **'{count}/{spots} going'**
  String going(int count, int spots);

  /// No description provided for @gameTitle.
  ///
  /// In en, this message translates to:
  /// **'{sport} with {host}'**
  String gameTitle(String host, String sport);

  /// No description provided for @createGame.
  ///
  /// In en, this message translates to:
  /// **'Create a game'**
  String get createGame;

  /// No description provided for @gamesPromoTitle.
  ///
  /// In en, this message translates to:
  /// **'Short of players?'**
  String get gamesPromoTitle;

  /// No description provided for @gamesPromoText.
  ///
  /// In en, this message translates to:
  /// **'Join a game at your level or fill your own court'**
  String get gamesPromoText;

  /// No description provided for @bookable.
  ///
  /// In en, this message translates to:
  /// **'Bookable'**
  String get bookable;

  /// No description provided for @favourites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get favourites;

  /// No description provided for @sortPrice.
  ///
  /// In en, this message translates to:
  /// **'Cheapest first'**
  String get sortPrice;

  /// No description provided for @priceStartingFrom.
  ///
  /// In en, this message translates to:
  /// **'Price starting from'**
  String get priceStartingFrom;

  /// No description provided for @registrationOpen.
  ///
  /// In en, this message translates to:
  /// **'Registration open'**
  String get registrationOpen;

  /// No description provided for @tournamentFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get tournamentFull;

  /// No description provided for @noTournaments.
  ///
  /// In en, this message translates to:
  /// **'No tournaments announced yet'**
  String get noTournaments;

  /// No description provided for @tournamentsPromoTitle.
  ///
  /// In en, this message translates to:
  /// **'Play for the cup'**
  String get tournamentsPromoTitle;

  /// No description provided for @tournamentsPromoText.
  ///
  /// In en, this message translates to:
  /// **'Singles and pairs for every level'**
  String get tournamentsPromoText;

  /// No description provided for @discoverTeams.
  ///
  /// In en, this message translates to:
  /// **'Discover teams'**
  String get discoverTeams;

  /// No description provided for @noTeams.
  ///
  /// In en, this message translates to:
  /// **'No teams in this city yet'**
  String get noTeams;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} member} other{{count} members}}'**
  String members(int count);

  /// No description provided for @upcomingGames.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} game soon} other{{count} games soon}}'**
  String upcomingGames(int count);

  /// No description provided for @playersNearYou.
  ///
  /// In en, this message translates to:
  /// **'Players near you'**
  String get playersNearYou;

  /// No description provided for @level.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String level(int level);

  /// No description provided for @inviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Bring your friends'**
  String get inviteTitle;

  /// No description provided for @inviteText.
  ///
  /// In en, this message translates to:
  /// **'Invite friends to Actra and fill your games faster.'**
  String get inviteText;

  /// No description provided for @inviteCta.
  ///
  /// In en, this message translates to:
  /// **'Invite friends'**
  String get inviteCta;

  /// No description provided for @statBookings.
  ///
  /// In en, this message translates to:
  /// **'Bookings'**
  String get statBookings;

  /// No description provided for @statGames.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get statGames;

  /// No description provided for @statLate.
  ///
  /// In en, this message translates to:
  /// **'Late cancels'**
  String get statLate;

  /// No description provided for @mySports.
  ///
  /// In en, this message translates to:
  /// **'My sports'**
  String get mySports;

  /// No description provided for @morning.
  ///
  /// In en, this message translates to:
  /// **'Morning'**
  String get morning;

  /// No description provided for @afternoon.
  ///
  /// In en, this message translates to:
  /// **'Afternoon'**
  String get afternoon;

  /// No description provided for @evening.
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get evening;

  /// No description provided for @everyDay.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get everyDay;

  /// No description provided for @gamesPromoCta.
  ///
  /// In en, this message translates to:
  /// **'Book a court'**
  String get gamesPromoCta;

  /// No description provided for @myVenues.
  ///
  /// In en, this message translates to:
  /// **'My venues'**
  String get myVenues;

  /// No description provided for @ownerCalendar.
  ///
  /// In en, this message translates to:
  /// **'Booking calendar'**
  String get ownerCalendar;

  /// No description provided for @noVenuesAssigned.
  ///
  /// In en, this message translates to:
  /// **'No venues are assigned to you yet'**
  String get noVenuesAssigned;

  /// No description provided for @prevWeek.
  ///
  /// In en, this message translates to:
  /// **'Previous week'**
  String get prevWeek;

  /// No description provided for @nextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get nextWeek;

  /// No description provided for @slotFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get slotFree;

  /// No description provided for @slotBooked.
  ///
  /// In en, this message translates to:
  /// **'Booked'**
  String get slotBooked;

  /// No description provided for @slotBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get slotBlocked;

  /// No description provided for @closedThatWeek.
  ///
  /// In en, this message translates to:
  /// **'The court is closed this week'**
  String get closedThatWeek;

  /// No description provided for @newBooking.
  ///
  /// In en, this message translates to:
  /// **'New booking'**
  String get newBooking;

  /// No description provided for @blockTime.
  ///
  /// In en, this message translates to:
  /// **'Block time'**
  String get blockTime;

  /// No description provided for @customerName.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get customerName;

  /// No description provided for @customerNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the customer name'**
  String get customerNameRequired;

  /// No description provided for @customerPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number (optional)'**
  String get customerPhone;

  /// No description provided for @slotsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Number of slots'**
  String get slotsCountLabel;

  /// No description provided for @payCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get payCash;

  /// No description provided for @payCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get payCard;

  /// No description provided for @payTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get payTransfer;

  /// No description provided for @saveBooking.
  ///
  /// In en, this message translates to:
  /// **'Save booking'**
  String get saveBooking;

  /// No description provided for @blockReason.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get blockReason;

  /// No description provided for @blockConfirm.
  ///
  /// In en, this message translates to:
  /// **'Block this time'**
  String get blockConfirm;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Open this time again'**
  String get unblock;

  /// No description provided for @customerLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customerLabel;

  /// No description provided for @sourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get sourceLabel;

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// No description provided for @reasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reasonLabel;

  /// No description provided for @sourceApp.
  ///
  /// In en, this message translates to:
  /// **'Booked in the app'**
  String get sourceApp;

  /// No description provided for @sourceWalkIn.
  ///
  /// In en, this message translates to:
  /// **'Walk-in or phone'**
  String get sourceWalkIn;

  /// No description provided for @sourceBlock.
  ///
  /// In en, this message translates to:
  /// **'Blocked by the venue'**
  String get sourceBlock;

  /// No description provided for @markPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark paid'**
  String get markPaid;

  /// No description provided for @markNoShow.
  ///
  /// In en, this message translates to:
  /// **'Mark no-show'**
  String get markNoShow;

  /// No description provided for @statusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get statusPaid;

  /// No description provided for @statusNoShow.
  ///
  /// In en, this message translates to:
  /// **'No-show'**
  String get statusNoShow;

  /// No description provided for @statusUnverified.
  ///
  /// In en, this message translates to:
  /// **'Not confirmed'**
  String get statusUnverified;

  /// No description provided for @statusCancelledByVenue.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by the venue'**
  String get statusCancelledByVenue;

  /// No description provided for @markAfterStart.
  ///
  /// In en, this message translates to:
  /// **'Paid and no-show can be marked once the booking has started'**
  String get markAfterStart;

  /// No description provided for @cancelByVenueMsg.
  ///
  /// In en, this message translates to:
  /// **'The time becomes free at once. A player who booked in the app will see that the venue cancelled it.'**
  String get cancelByVenueMsg;

  /// No description provided for @errNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'You do not manage this venue'**
  String get errNotAllowed;

  /// No description provided for @bookingSaved.
  ///
  /// In en, this message translates to:
  /// **'Booking saved'**
  String get bookingSaved;

  /// No description provided for @ownerSettings.
  ///
  /// In en, this message translates to:
  /// **'Hours and prices'**
  String get ownerSettings;

  /// No description provided for @ownerDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get ownerDashboard;

  /// No description provided for @venueHours.
  ///
  /// In en, this message translates to:
  /// **'Venue working hours'**
  String get venueHours;

  /// No description provided for @courtHours.
  ///
  /// In en, this message translates to:
  /// **'Court hours'**
  String get courtHours;

  /// No description provided for @sameAsVenue.
  ///
  /// In en, this message translates to:
  /// **'Same as venue'**
  String get sameAsVenue;

  /// No description provided for @openLabel.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openLabel;

  /// No description provided for @editLabel.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editLabel;

  /// No description provided for @saveLabel.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveLabel;

  /// No description provided for @savedMsg.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedMsg;

  /// No description provided for @pricesTitle.
  ///
  /// In en, this message translates to:
  /// **'Prices'**
  String get pricesTitle;

  /// No description provided for @hoursTitle.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get hoursTitle;

  /// No description provided for @slotLengthLabel.
  ///
  /// In en, this message translates to:
  /// **'Slot length'**
  String get slotLengthLabel;

  /// No description provided for @basePrice.
  ///
  /// In en, this message translates to:
  /// **'Base price per slot'**
  String get basePrice;

  /// No description provided for @priceRules.
  ///
  /// In en, this message translates to:
  /// **'Price rules'**
  String get priceRules;

  /// No description provided for @addRule.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get addRule;

  /// No description provided for @removeRule.
  ///
  /// In en, this message translates to:
  /// **'Remove rule'**
  String get removeRule;

  /// No description provided for @ruleFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get ruleFrom;

  /// No description provided for @ruleTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get ruleTo;

  /// No description provided for @rulePrice.
  ///
  /// In en, this message translates to:
  /// **'Price per slot'**
  String get rulePrice;

  /// No description provided for @noRules.
  ///
  /// In en, this message translates to:
  /// **'No rules: every slot costs the base price'**
  String get noRules;

  /// No description provided for @rulesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No price rules} one{{count} price rule} other{{count} price rules}}'**
  String rulesCount(int count);

  /// No description provided for @errInvalidHours.
  ///
  /// In en, this message translates to:
  /// **'Opening must be earlier than closing'**
  String get errInvalidHours;

  /// No description provided for @errRulesOverlap.
  ///
  /// In en, this message translates to:
  /// **'Two rules cover the same day and time'**
  String get errRulesOverlap;

  /// No description provided for @errInvalidArgument.
  ///
  /// In en, this message translates to:
  /// **'Check the values and try again'**
  String get errInvalidArgument;

  /// No description provided for @errPickWeekday.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one day'**
  String get errPickWeekday;

  /// No description provided for @errPrice.
  ///
  /// In en, this message translates to:
  /// **'Enter a price'**
  String get errPrice;

  /// No description provided for @period7.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get period7;

  /// No description provided for @periodMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get periodMonth;

  /// No description provided for @allCourts.
  ///
  /// In en, this message translates to:
  /// **'All courts'**
  String get allCourts;

  /// No description provided for @metricSplit.
  ///
  /// In en, this message translates to:
  /// **'App {app} · walk-in {walkIn}'**
  String metricSplit(int app, int walkIn);

  /// No description provided for @metricRevenue.
  ///
  /// In en, this message translates to:
  /// **'Paid revenue'**
  String get metricRevenue;

  /// No description provided for @metricUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Unconfirmed revenue'**
  String get metricUnconfirmed;

  /// No description provided for @metricDailyAvg.
  ///
  /// In en, this message translates to:
  /// **'Bookings per day'**
  String get metricDailyAvg;

  /// No description provided for @metricUtilisation.
  ///
  /// In en, this message translates to:
  /// **'Utilisation'**
  String get metricUtilisation;

  /// No description provided for @metricNoShows.
  ///
  /// In en, this message translates to:
  /// **'No-shows'**
  String get metricNoShows;

  /// No description provided for @peakHours.
  ///
  /// In en, this message translates to:
  /// **'Peak hours'**
  String get peakHours;

  /// No description provided for @noDataPeriod.
  ///
  /// In en, this message translates to:
  /// **'No bookings in this period'**
  String get noDataPeriod;

  /// No description provided for @adminTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get adminTitle;

  /// No description provided for @adminOnly.
  ///
  /// In en, this message translates to:
  /// **'Only Actra administrators can open this page'**
  String get adminOnly;

  /// No description provided for @adminSports.
  ///
  /// In en, this message translates to:
  /// **'Sports'**
  String get adminSports;

  /// No description provided for @adminBanners.
  ///
  /// In en, this message translates to:
  /// **'Banners'**
  String get adminBanners;

  /// No description provided for @adminAudit.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get adminAudit;

  /// No description provided for @adminAuditHint.
  ///
  /// In en, this message translates to:
  /// **'Who changed what, and when'**
  String get adminAuditHint;

  /// No description provided for @venuesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} venue} other{{count} venues}}'**
  String venuesCount(int count);

  /// No description provided for @sportsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} sport} other{{count} sports}}'**
  String sportsCount(int count);

  /// No description provided for @bannersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} banner} other{{count} banners}}'**
  String bannersCount(int count);

  /// No description provided for @courtsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} court} other{{count} courts}}'**
  String courtsCount(int count);

  /// No description provided for @ownersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No owners} one{{count} owner} other{{count} owners}}'**
  String ownersCount(int count);

  /// No description provided for @playersN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} player} other{{count} players}}'**
  String playersN(int count);

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @activeLabel.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeLabel;

  /// No description provided for @activeHint.
  ///
  /// In en, this message translates to:
  /// **'Players can see it'**
  String get activeHint;

  /// No description provided for @addVenue.
  ///
  /// In en, this message translates to:
  /// **'Add venue'**
  String get addVenue;

  /// No description provided for @newVenue.
  ///
  /// In en, this message translates to:
  /// **'New venue'**
  String get newVenue;

  /// No description provided for @venueDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get venueDetails;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @descriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionLabel;

  /// No description provided for @districtLabel.
  ///
  /// In en, this message translates to:
  /// **'District'**
  String get districtLabel;

  /// No description provided for @nameRequiredAny.
  ///
  /// In en, this message translates to:
  /// **'Fill in at least one language'**
  String get nameRequiredAny;

  /// No description provided for @saveVenueFirst.
  ///
  /// In en, this message translates to:
  /// **'Save the venue to add courts and owners'**
  String get saveVenueFirst;

  /// No description provided for @addCourt.
  ///
  /// In en, this message translates to:
  /// **'Add court'**
  String get addCourt;

  /// No description provided for @newCourt.
  ///
  /// In en, this message translates to:
  /// **'New court'**
  String get newCourt;

  /// No description provided for @editCourt.
  ///
  /// In en, this message translates to:
  /// **'Edit court'**
  String get editCourt;

  /// No description provided for @noCourts.
  ///
  /// In en, this message translates to:
  /// **'No courts yet'**
  String get noCourts;

  /// No description provided for @courtActions.
  ///
  /// In en, this message translates to:
  /// **'Court actions'**
  String get courtActions;

  /// No description provided for @duplicateLabel.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicateLabel;

  /// No description provided for @deleteLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteLabel;

  /// No description provided for @deleteVenue.
  ///
  /// In en, this message translates to:
  /// **'Delete venue'**
  String get deleteVenue;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String deleteConfirmTitle(String name);

  /// No description provided for @deleteConfirmMsg.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get deleteConfirmMsg;

  /// No description provided for @errHasBookings.
  ///
  /// In en, this message translates to:
  /// **'It has bookings, so it cannot be deleted. Deactivate it to hide it from players.'**
  String get errHasBookings;

  /// No description provided for @deactivateInstead.
  ///
  /// In en, this message translates to:
  /// **'Deactivate instead'**
  String get deactivateInstead;

  /// No description provided for @errAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'This ID is already taken'**
  String get errAlreadyExists;

  /// No description provided for @errNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found. Refresh and try again.'**
  String get errNotFound;

  /// No description provided for @ownersTitle.
  ///
  /// In en, this message translates to:
  /// **'Owners'**
  String get ownersTitle;

  /// No description provided for @assignOwner.
  ///
  /// In en, this message translates to:
  /// **'Assign owner'**
  String get assignOwner;

  /// No description provided for @removeOwner.
  ///
  /// In en, this message translates to:
  /// **'Remove owner'**
  String get removeOwner;

  /// No description provided for @noOwners.
  ///
  /// In en, this message translates to:
  /// **'No owners assigned'**
  String get noOwners;

  /// No description provided for @searchUsers.
  ///
  /// In en, this message translates to:
  /// **'Name or phone'**
  String get searchUsers;

  /// No description provided for @searchUsersMin.
  ///
  /// In en, this message translates to:
  /// **'Type at least 2 characters'**
  String get searchUsersMin;

  /// No description provided for @noUsersFound.
  ///
  /// In en, this message translates to:
  /// **'Nobody found'**
  String get noUsersFound;

  /// No description provided for @addSport.
  ///
  /// In en, this message translates to:
  /// **'Add sport'**
  String get addSport;

  /// No description provided for @newSport.
  ///
  /// In en, this message translates to:
  /// **'New sport'**
  String get newSport;

  /// No description provided for @editSport.
  ///
  /// In en, this message translates to:
  /// **'Edit sport'**
  String get editSport;

  /// No description provided for @sportIdLabel.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get sportIdLabel;

  /// No description provided for @sportIdHint.
  ///
  /// In en, this message translates to:
  /// **'Lowercase Latin letters, digits and _, for example squash. Cannot be changed later.'**
  String get sportIdHint;

  /// No description provided for @errSportId.
  ///
  /// In en, this message translates to:
  /// **'2–30 characters: lowercase Latin letters, digits or _, starting with a letter'**
  String get errSportId;

  /// No description provided for @iconLabel.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get iconLabel;

  /// No description provided for @sportTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get sportTypeLabel;

  /// No description provided for @placeOnly.
  ///
  /// In en, this message translates to:
  /// **'Place only'**
  String get placeOnly;

  /// No description provided for @ratingLabel.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get ratingLabel;

  /// No description provided for @ratingSimple.
  ///
  /// In en, this message translates to:
  /// **'Level 1–5'**
  String get ratingSimple;

  /// No description provided for @ratingCompetitive.
  ///
  /// In en, this message translates to:
  /// **'Rating 1.0–7.0'**
  String get ratingCompetitive;

  /// No description provided for @defaultPlayers.
  ///
  /// In en, this message translates to:
  /// **'Default players'**
  String get defaultPlayers;

  /// No description provided for @sortOrderLabel.
  ///
  /// In en, this message translates to:
  /// **'Position in list'**
  String get sortOrderLabel;

  /// No description provided for @addBanner.
  ///
  /// In en, this message translates to:
  /// **'Add banner'**
  String get addBanner;

  /// No description provided for @newBanner.
  ///
  /// In en, this message translates to:
  /// **'New banner'**
  String get newBanner;

  /// No description provided for @editBanner.
  ///
  /// In en, this message translates to:
  /// **'Edit banner'**
  String get editBanner;

  /// No description provided for @bannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get bannerTitle;

  /// No description provided for @bannerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle'**
  String get bannerSubtitle;

  /// No description provided for @linkLabel.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get linkLabel;

  /// No description provided for @errUrl.
  ///
  /// In en, this message translates to:
  /// **'The link must start with https://'**
  String get errUrl;

  /// No description provided for @allCities.
  ///
  /// In en, this message translates to:
  /// **'All cities'**
  String get allCities;

  /// No description provided for @noBanners.
  ///
  /// In en, this message translates to:
  /// **'No banners yet'**
  String get noBanners;

  /// No description provided for @auditEmpty.
  ///
  /// In en, this message translates to:
  /// **'No changes recorded yet'**
  String get auditEmpty;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @auditBefore.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get auditBefore;

  /// No description provided for @auditAfter.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get auditAfter;

  /// No description provided for @auditSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get auditSystem;

  /// No description provided for @auditCreateVenue.
  ///
  /// In en, this message translates to:
  /// **'Venue created'**
  String get auditCreateVenue;

  /// No description provided for @auditUpdateVenue.
  ///
  /// In en, this message translates to:
  /// **'Venue updated'**
  String get auditUpdateVenue;

  /// No description provided for @auditDeleteVenue.
  ///
  /// In en, this message translates to:
  /// **'Venue deleted'**
  String get auditDeleteVenue;

  /// No description provided for @auditCreateCourt.
  ///
  /// In en, this message translates to:
  /// **'Court created'**
  String get auditCreateCourt;

  /// No description provided for @auditUpdateCourt.
  ///
  /// In en, this message translates to:
  /// **'Court updated'**
  String get auditUpdateCourt;

  /// No description provided for @auditDuplicateCourt.
  ///
  /// In en, this message translates to:
  /// **'Court duplicated'**
  String get auditDuplicateCourt;

  /// No description provided for @auditDeleteCourt.
  ///
  /// In en, this message translates to:
  /// **'Court deleted'**
  String get auditDeleteCourt;

  /// No description provided for @auditAssignOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner assigned'**
  String get auditAssignOwner;

  /// No description provided for @auditRemoveOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner removed'**
  String get auditRemoveOwner;

  /// No description provided for @auditCreateSport.
  ///
  /// In en, this message translates to:
  /// **'Sport created'**
  String get auditCreateSport;

  /// No description provided for @auditUpdateSport.
  ///
  /// In en, this message translates to:
  /// **'Sport updated'**
  String get auditUpdateSport;

  /// No description provided for @auditCreateBanner.
  ///
  /// In en, this message translates to:
  /// **'Banner created'**
  String get auditCreateBanner;

  /// No description provided for @auditUpdateBanner.
  ///
  /// In en, this message translates to:
  /// **'Banner updated'**
  String get auditUpdateBanner;

  /// No description provided for @auditDeleteBanner.
  ///
  /// In en, this message translates to:
  /// **'Banner deleted'**
  String get auditDeleteBanner;

  /// No description provided for @auditVenueHours.
  ///
  /// In en, this message translates to:
  /// **'Venue hours changed'**
  String get auditVenueHours;

  /// No description provided for @auditCourtHours.
  ///
  /// In en, this message translates to:
  /// **'Court hours changed'**
  String get auditCourtHours;

  /// No description provided for @auditCourtPricing.
  ///
  /// In en, this message translates to:
  /// **'Court prices changed'**
  String get auditCourtPricing;

  /// No description provided for @auditWalkIn.
  ///
  /// In en, this message translates to:
  /// **'Walk-in booking added'**
  String get auditWalkIn;

  /// No description provided for @auditBlock.
  ///
  /// In en, this message translates to:
  /// **'Time blocked'**
  String get auditBlock;

  /// No description provided for @auditMarkBooking.
  ///
  /// In en, this message translates to:
  /// **'Booking marked'**
  String get auditMarkBooking;

  /// No description provided for @entityVenue.
  ///
  /// In en, this message translates to:
  /// **'Venue'**
  String get entityVenue;

  /// No description provided for @entityBanner.
  ///
  /// In en, this message translates to:
  /// **'Banner'**
  String get entityBanner;

  /// No description provided for @entityBooking.
  ///
  /// In en, this message translates to:
  /// **'Booking'**
  String get entityBooking;

  /// No description provided for @entityOwner.
  ///
  /// In en, this message translates to:
  /// **'Venue owner'**
  String get entityOwner;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @notificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification settings'**
  String get notificationSettings;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotifications;

  /// No description provided for @notificationsAndPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Notifications and privacy'**
  String get notificationsAndPrivacy;

  /// No description provided for @notificationsMuteHint.
  ///
  /// In en, this message translates to:
  /// **'Choose what you hear about. Switch a group off to stop its notifications.'**
  String get notificationsMuteHint;

  /// No description provided for @notifCategoryBookings.
  ///
  /// In en, this message translates to:
  /// **'Bookings'**
  String get notifCategoryBookings;

  /// No description provided for @notifCategoryVenue.
  ///
  /// In en, this message translates to:
  /// **'My venues'**
  String get notifCategoryVenue;

  /// No description provided for @notifCategoryGames.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get notifCategoryGames;

  /// No description provided for @notifCategoryRequests.
  ///
  /// In en, this message translates to:
  /// **'Game Requests'**
  String get notifCategoryRequests;

  /// No description provided for @notifCategoryInvites.
  ///
  /// In en, this message translates to:
  /// **'Invitations'**
  String get notifCategoryInvites;

  /// No description provided for @notifCategoryTournaments.
  ///
  /// In en, this message translates to:
  /// **'Tournaments'**
  String get notifCategoryTournaments;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyTitle;

  /// No description provided for @hideFromSearch.
  ///
  /// In en, this message translates to:
  /// **'Hide me from player search'**
  String get hideFromSearch;

  /// No description provided for @hideFromSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Other players will not find you when they look for people to invite.'**
  String get hideFromSearchHint;

  /// No description provided for @notifSomeone.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get notifSomeone;

  /// No description provided for @notifVenueFallback.
  ///
  /// In en, this message translates to:
  /// **'the venue'**
  String get notifVenueFallback;

  /// No description provided for @notifCourtFallback.
  ///
  /// In en, this message translates to:
  /// **'a court'**
  String get notifCourtFallback;

  /// No description provided for @notifBookingConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Your booking at {venue} is confirmed'**
  String notifBookingConfirmed(String venue);

  /// No description provided for @notifBookingCancelledByVenue.
  ///
  /// In en, this message translates to:
  /// **'{venue} cancelled your booking'**
  String notifBookingCancelledByVenue(String venue);

  /// No description provided for @notifBookingReminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder: your booking at {venue} is coming up'**
  String notifBookingReminder(String venue);

  /// No description provided for @notifVenueNewBooking.
  ///
  /// In en, this message translates to:
  /// **'{actor} booked {court}'**
  String notifVenueNewBooking(String actor, String court);

  /// No description provided for @notifVenueBookingCancelled.
  ///
  /// In en, this message translates to:
  /// **'{actor} cancelled {court}'**
  String notifVenueBookingCancelled(String actor, String court);

  /// No description provided for @notifGameJoined.
  ///
  /// In en, this message translates to:
  /// **'{actor} joined your game'**
  String notifGameJoined(String actor);

  /// No description provided for @notifGameLeft.
  ///
  /// In en, this message translates to:
  /// **'{actor} left your game'**
  String notifGameLeft(String actor);

  /// No description provided for @notifJoinRequest.
  ///
  /// In en, this message translates to:
  /// **'{actor} asked to join your game'**
  String notifJoinRequest(String actor);

  /// No description provided for @notifJoinApproved.
  ///
  /// In en, this message translates to:
  /// **'You are in! The host approved your request'**
  String get notifJoinApproved;

  /// No description provided for @notifJoinDeclined.
  ///
  /// In en, this message translates to:
  /// **'The host declined your request'**
  String get notifJoinDeclined;

  /// No description provided for @notifGameFull.
  ///
  /// In en, this message translates to:
  /// **'Your game is full'**
  String get notifGameFull;

  /// No description provided for @notifGameChanged.
  ///
  /// In en, this message translates to:
  /// **'The host changed the game details'**
  String get notifGameChanged;

  /// No description provided for @notifGameCancelled.
  ///
  /// In en, this message translates to:
  /// **'The game was cancelled'**
  String get notifGameCancelled;

  /// No description provided for @notifGameRemoved.
  ///
  /// In en, this message translates to:
  /// **'The host removed you from the game'**
  String get notifGameRemoved;

  /// No description provided for @notifGameReminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder: your game starts soon'**
  String get notifGameReminder;

  /// No description provided for @notifGameInvite.
  ///
  /// In en, this message translates to:
  /// **'{actor} invited you to a game'**
  String notifGameInvite(String actor);

  /// No description provided for @notifRequestInterest.
  ///
  /// In en, this message translates to:
  /// **'{actor} is in for your Game Request'**
  String notifRequestInterest(String actor);

  /// No description provided for @notifRequestConvertedIn.
  ///
  /// In en, this message translates to:
  /// **'Your Game Request became a game, and you are in'**
  String get notifRequestConvertedIn;

  /// No description provided for @notifRequestConvertedFull.
  ///
  /// In en, this message translates to:
  /// **'Your Game Request became a game, but it filled up before you'**
  String get notifRequestConvertedFull;

  /// No description provided for @notifRequestExpired.
  ///
  /// In en, this message translates to:
  /// **'A Game Request expired'**
  String get notifRequestExpired;

  /// No description provided for @notifUnknown.
  ///
  /// In en, this message translates to:
  /// **'New notification'**
  String get notifUnknown;

  /// No description provided for @reliabilityNew.
  ///
  /// In en, this message translates to:
  /// **'New player'**
  String get reliabilityNew;

  /// No description provided for @reliabilityReliable.
  ///
  /// In en, this message translates to:
  /// **'Reliable'**
  String get reliabilityReliable;

  /// No description provided for @reliabilityLimited.
  ///
  /// In en, this message translates to:
  /// **'Limited'**
  String get reliabilityLimited;

  /// No description provided for @reliabilityBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get reliabilityBlocked;

  /// No description provided for @reliabilityScore.
  ///
  /// In en, this message translates to:
  /// **'Reliability score {score} of 100'**
  String reliabilityScore(int score);

  /// No description provided for @reliabilityLimitedHint.
  ///
  /// In en, this message translates to:
  /// **'You can hold one upcoming booking at a time. Show up and play to recover.'**
  String get reliabilityLimitedHint;

  /// No description provided for @reliabilityBlockedHint.
  ///
  /// In en, this message translates to:
  /// **'You cannot book, join or post until older missed games pass 90 days.'**
  String get reliabilityBlockedHint;

  /// No description provided for @gameSportLabel.
  ///
  /// In en, this message translates to:
  /// **'Sport'**
  String get gameSportLabel;

  /// No description provided for @pickSportHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a sport to set up your game'**
  String get pickSportHint;

  /// No description provided for @gameBookingLabel.
  ///
  /// In en, this message translates to:
  /// **'Your court booking'**
  String get gameBookingLabel;

  /// No description provided for @noBookingForSport.
  ///
  /// In en, this message translates to:
  /// **'You have no upcoming confirmed booking for this sport. Book a court first, then create a game on it.'**
  String get noBookingForSport;

  /// No description provided for @bookACourt.
  ///
  /// In en, this message translates to:
  /// **'Book a court'**
  String get bookACourt;

  /// No description provided for @gamePlaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Where'**
  String get gamePlaceLabel;

  /// No description provided for @placeVenue.
  ///
  /// In en, this message translates to:
  /// **'Venue'**
  String get placeVenue;

  /// No description provided for @placeMeetingPoint.
  ///
  /// In en, this message translates to:
  /// **'Meeting point'**
  String get placeMeetingPoint;

  /// No description provided for @chooseVenue.
  ///
  /// In en, this message translates to:
  /// **'Choose a venue'**
  String get chooseVenue;

  /// No description provided for @meetingPointHint.
  ///
  /// In en, this message translates to:
  /// **'For example: main gate of the park'**
  String get meetingPointHint;

  /// No description provided for @meetingPointRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a meeting point'**
  String get meetingPointRequired;

  /// No description provided for @venueRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a venue'**
  String get venueRequired;

  /// No description provided for @gameWhenLabel.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get gameWhenLabel;

  /// No description provided for @gameStartTime.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get gameStartTime;

  /// No description provided for @gameDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get gameDuration;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minutesShort(int count);

  /// No description provided for @distanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Distance, km (optional)'**
  String get distanceLabel;

  /// No description provided for @paceLabel.
  ///
  /// In en, this message translates to:
  /// **'Pace (optional)'**
  String get paceLabel;

  /// No description provided for @paceHint.
  ///
  /// In en, this message translates to:
  /// **'For example 6:00 min/km'**
  String get paceHint;

  /// No description provided for @distanceValue.
  ///
  /// In en, this message translates to:
  /// **'{km} km'**
  String distanceValue(String km);

  /// No description provided for @paceValue.
  ///
  /// In en, this message translates to:
  /// **'Pace {pace}'**
  String paceValue(String pace);

  /// No description provided for @spotsLabel.
  ///
  /// In en, this message translates to:
  /// **'Spots, host included'**
  String get spotsLabel;

  /// No description provided for @fewerSpots.
  ///
  /// In en, this message translates to:
  /// **'Fewer spots'**
  String get fewerSpots;

  /// No description provided for @moreSpots.
  ///
  /// In en, this message translates to:
  /// **'More spots'**
  String get moreSpots;

  /// No description provided for @levelRangeLabel.
  ///
  /// In en, this message translates to:
  /// **'Level range'**
  String get levelRangeLabel;

  /// No description provided for @visibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Who can see it'**
  String get visibilityLabel;

  /// No description provided for @visibilityPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get visibilityPublic;

  /// No description provided for @visibilityInviteOnly.
  ///
  /// In en, this message translates to:
  /// **'Invite only'**
  String get visibilityInviteOnly;

  /// No description provided for @askToJoin.
  ///
  /// In en, this message translates to:
  /// **'Ask to join'**
  String get askToJoin;

  /// No description provided for @requested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get requested;

  /// No description provided for @withdrawRequest.
  ///
  /// In en, this message translates to:
  /// **'Withdraw request'**
  String get withdrawRequest;

  /// No description provided for @invitedToGame.
  ///
  /// In en, this message translates to:
  /// **'You are invited to this game'**
  String get invitedToGame;

  /// No description provided for @invitedPill.
  ///
  /// In en, this message translates to:
  /// **'Invited'**
  String get invitedPill;

  /// No description provided for @acceptInvite.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get acceptInvite;

  /// No description provided for @declineLabel.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get declineLabel;

  /// No description provided for @approveLabel.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approveLabel;

  /// No description provided for @requestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requestsTitle;

  /// No description provided for @hostTools.
  ///
  /// In en, this message translates to:
  /// **'Host tools'**
  String get hostTools;

  /// No description provided for @editGame.
  ///
  /// In en, this message translates to:
  /// **'Edit game'**
  String get editGame;

  /// No description provided for @cancelGame.
  ///
  /// In en, this message translates to:
  /// **'Cancel game'**
  String get cancelGame;

  /// No description provided for @cancelGameTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this game?'**
  String get cancelGameTitle;

  /// No description provided for @cancelGameMsg.
  ///
  /// In en, this message translates to:
  /// **'The players will be told.'**
  String get cancelGameMsg;

  /// No description provided for @alsoCancelBooking.
  ///
  /// In en, this message translates to:
  /// **'Also cancel my court booking'**
  String get alsoCancelBooking;

  /// No description provided for @alsoCancelBookingHint.
  ///
  /// In en, this message translates to:
  /// **'Frees the court for others. Late cancellation rules still apply.'**
  String get alsoCancelBookingHint;

  /// No description provided for @keepGame.
  ///
  /// In en, this message translates to:
  /// **'Keep game'**
  String get keepGame;

  /// No description provided for @gameCancelled.
  ///
  /// In en, this message translates to:
  /// **'Game cancelled'**
  String get gameCancelled;

  /// No description provided for @gameCancelledBanner.
  ///
  /// In en, this message translates to:
  /// **'This game was cancelled'**
  String get gameCancelledBanner;

  /// No description provided for @removePlayer.
  ///
  /// In en, this message translates to:
  /// **'Remove player'**
  String get removePlayer;

  /// No description provided for @removePlayerTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String removePlayerTitle(String name);

  /// No description provided for @removePlayerMsg.
  ///
  /// In en, this message translates to:
  /// **'They will be told they were removed.'**
  String get removePlayerMsg;

  /// No description provided for @removeLabel.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeLabel;

  /// No description provided for @createGameFromBooking.
  ///
  /// In en, this message translates to:
  /// **'Create a game from this booking'**
  String get createGameFromBooking;

  /// No description provided for @errSpotsBelowPlayers.
  ///
  /// In en, this message translates to:
  /// **'Spots cannot be fewer than the players already in the game'**
  String get errSpotsBelowPlayers;

  /// No description provided for @errAlreadyJoined.
  ///
  /// In en, this message translates to:
  /// **'You are already in this game'**
  String get errAlreadyJoined;

  /// No description provided for @errNotParticipant.
  ///
  /// In en, this message translates to:
  /// **'You are not in this game'**
  String get errNotParticipant;

  /// No description provided for @errHostCannotLeave.
  ///
  /// In en, this message translates to:
  /// **'The host cannot leave. Cancel the game instead.'**
  String get errHostCannotLeave;

  /// No description provided for @errAlreadyRequested.
  ///
  /// In en, this message translates to:
  /// **'You have already asked to join this game'**
  String get errAlreadyRequested;

  /// No description provided for @errBookingNotUsable.
  ///
  /// In en, this message translates to:
  /// **'Choose your own confirmed booking for this sport that has not started yet'**
  String get errBookingNotUsable;

  /// No description provided for @errGameExists.
  ///
  /// In en, this message translates to:
  /// **'This booking already has a game'**
  String get errGameExists;

  /// No description provided for @errForbidden.
  ///
  /// In en, this message translates to:
  /// **'You cannot do this in this game'**
  String get errForbidden;

  /// No description provided for @errNotCancellable.
  ///
  /// In en, this message translates to:
  /// **'The game has already started, so it cannot be cancelled'**
  String get errNotCancellable;

  /// No description provided for @errUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check your connection.'**
  String get errUnavailable;

  /// No description provided for @gamesTabRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get gamesTabRequests;

  /// No description provided for @homeRequests.
  ///
  /// In en, this message translates to:
  /// **'Game Requests'**
  String get homeRequests;

  /// No description provided for @interestedOf.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} interested'**
  String interestedOf(int count, int total);

  /// No description provided for @requestTitle.
  ///
  /// In en, this message translates to:
  /// **'{host} wants to play {sport}'**
  String requestTitle(String host, String sport);

  /// No description provided for @needsPlayers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Needs {count} more player} other{Needs {count} more players}}'**
  String needsPlayers(int count);

  /// No description provided for @noRequests.
  ///
  /// In en, this message translates to:
  /// **'No Game Requests yet. Post one to find players.'**
  String get noRequests;

  /// No description provided for @postRequest.
  ///
  /// In en, this message translates to:
  /// **'Post a request'**
  String get postRequest;

  /// No description provided for @createRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Game Request'**
  String get createRequestTitle;

  /// No description provided for @requestPlayersNeeded.
  ///
  /// In en, this message translates to:
  /// **'Players needed'**
  String get requestPlayersNeeded;

  /// No description provided for @requestWindowLabel.
  ///
  /// In en, this message translates to:
  /// **'When can you play?'**
  String get requestWindowLabel;

  /// No description provided for @requestFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get requestFrom;

  /// No description provided for @requestTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get requestTo;

  /// No description provided for @areaLabel.
  ///
  /// In en, this message translates to:
  /// **'Area (optional)'**
  String get areaLabel;

  /// No description provided for @areaHint.
  ///
  /// In en, this message translates to:
  /// **'For example, Yunusobod'**
  String get areaHint;

  /// No description provided for @venueOptional.
  ///
  /// In en, this message translates to:
  /// **'Venue (optional)'**
  String get venueOptional;

  /// No description provided for @anyVenue.
  ///
  /// In en, this message translates to:
  /// **'Any venue'**
  String get anyVenue;

  /// No description provided for @postRequestCta.
  ///
  /// In en, this message translates to:
  /// **'Post request'**
  String get postRequestCta;

  /// No description provided for @imIn.
  ///
  /// In en, this message translates to:
  /// **'I\'m in'**
  String get imIn;

  /// No description provided for @leaveRequest.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leaveRequest;

  /// No description provided for @interestedPlayers.
  ///
  /// In en, this message translates to:
  /// **'Interested'**
  String get interestedPlayers;

  /// No description provided for @noInterestedYet.
  ///
  /// In en, this message translates to:
  /// **'Nobody has said they are in yet'**
  String get noInterestedYet;

  /// No description provided for @makeItAGame.
  ///
  /// In en, this message translates to:
  /// **'Make it a game'**
  String get makeItAGame;

  /// No description provided for @convertHint.
  ///
  /// In en, this message translates to:
  /// **'The players who are in are added in the order they tapped, while spots last.'**
  String get convertHint;

  /// No description provided for @gameEndTime.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get gameEndTime;

  /// No description provided for @cancelRequestLabel.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get cancelRequestLabel;

  /// No description provided for @cancelRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this request?'**
  String get cancelRequestTitle;

  /// No description provided for @cancelRequestMsg.
  ///
  /// In en, this message translates to:
  /// **'The players who said they are in will no longer see it.'**
  String get cancelRequestMsg;

  /// No description provided for @keepRequest.
  ///
  /// In en, this message translates to:
  /// **'Keep request'**
  String get keepRequest;

  /// No description provided for @requestCancelledMsg.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled'**
  String get requestCancelledMsg;

  /// No description provided for @removeInterestedMsg.
  ///
  /// In en, this message translates to:
  /// **'They will be taken off the list.'**
  String get removeInterestedMsg;

  /// No description provided for @requestConvertedBanner.
  ///
  /// In en, this message translates to:
  /// **'This request became a game'**
  String get requestConvertedBanner;

  /// No description provided for @openGameCta.
  ///
  /// In en, this message translates to:
  /// **'Open the game'**
  String get openGameCta;

  /// No description provided for @requestClosedBanner.
  ///
  /// In en, this message translates to:
  /// **'This request is closed'**
  String get requestClosedBanner;

  /// No description provided for @findPlayers.
  ///
  /// In en, this message translates to:
  /// **'Find players'**
  String get findPlayers;

  /// No description provided for @searchPlayersHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name'**
  String get searchPlayersHint;

  /// No description provided for @noPlayersFound.
  ///
  /// In en, this message translates to:
  /// **'No players found'**
  String get noPlayersFound;

  /// No description provided for @gamesPlayed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} game played} other{{count} games played}}'**
  String gamesPlayed(int count);

  /// No description provided for @playerProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Player profile'**
  String get playerProfileTitle;

  /// No description provided for @profileLevels.
  ///
  /// In en, this message translates to:
  /// **'Levels'**
  String get profileLevels;

  /// No description provided for @noLevelsYet.
  ///
  /// In en, this message translates to:
  /// **'No levels set yet'**
  String get noLevelsYet;

  /// No description provided for @inviteToGame.
  ///
  /// In en, this message translates to:
  /// **'Invite to a game'**
  String get inviteToGame;

  /// No description provided for @chooseGameToInvite.
  ///
  /// In en, this message translates to:
  /// **'Choose a game'**
  String get chooseGameToInvite;

  /// No description provided for @noGamesToInvite.
  ///
  /// In en, this message translates to:
  /// **'You have no open game with a free spot. Create one first.'**
  String get noGamesToInvite;

  /// No description provided for @inviteSent.
  ///
  /// In en, this message translates to:
  /// **'{name} was invited'**
  String inviteSent(String name);

  /// No description provided for @tournamentsMine.
  ///
  /// In en, this message translates to:
  /// **'My tournaments'**
  String get tournamentsMine;

  /// No description provided for @tournamentFilterDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get tournamentFilterDate;

  /// No description provided for @tournamentFilterFrom.
  ///
  /// In en, this message translates to:
  /// **'From {date}'**
  String tournamentFilterFrom(String date);

  /// No description provided for @tournamentSortAz.
  ///
  /// In en, this message translates to:
  /// **'A–Z'**
  String get tournamentSortAz;

  /// No description provided for @registrationClosed.
  ///
  /// In en, this message translates to:
  /// **'Registration closed'**
  String get registrationClosed;

  /// No description provided for @tournamentFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get tournamentFree;

  /// No description provided for @tournamentCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get tournamentCategories;

  /// No description provided for @tournamentDeadline.
  ///
  /// In en, this message translates to:
  /// **'Registration closes {when}'**
  String tournamentDeadline(String when);

  /// No description provided for @tournamentClosedBanner.
  ///
  /// In en, this message translates to:
  /// **'Registration is closed'**
  String get tournamentClosedBanner;

  /// No description provided for @kindSingles.
  ///
  /// In en, this message translates to:
  /// **'Singles'**
  String get kindSingles;

  /// No description provided for @kindPairs.
  ///
  /// In en, this message translates to:
  /// **'Pairs'**
  String get kindPairs;

  /// No description provided for @genderMen.
  ///
  /// In en, this message translates to:
  /// **'Men'**
  String get genderMen;

  /// No description provided for @genderWomen.
  ///
  /// In en, this message translates to:
  /// **'Women'**
  String get genderWomen;

  /// No description provided for @genderMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get genderMixed;

  /// No description provided for @genderOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get genderOpen;

  /// No description provided for @waitlistCount.
  ///
  /// In en, this message translates to:
  /// **'{count} waiting'**
  String waitlistCount(int count);

  /// No description provided for @joinWaitlist.
  ///
  /// In en, this message translates to:
  /// **'Join waitlist'**
  String get joinWaitlist;

  /// No description provided for @registerLabel.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get registerLabel;

  /// No description provided for @confirmRegistration.
  ///
  /// In en, this message translates to:
  /// **'Confirm registration'**
  String get confirmRegistration;

  /// No description provided for @registerSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Register: {category}'**
  String registerSheetTitle(String category);

  /// No description provided for @waitlistSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Waitlist: {category}'**
  String waitlistSheetTitle(String category);

  /// No description provided for @registrationFeeNote.
  ///
  /// In en, this message translates to:
  /// **'Entry fee {fee}, paid to the organiser.'**
  String registrationFeeNote(String fee);

  /// No description provided for @waitlistSheetNote.
  ///
  /// In en, this message translates to:
  /// **'The category is full. If a spot frees up, you get 24 hours to claim it.'**
  String get waitlistSheetNote;

  /// No description provided for @partnerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a partner'**
  String get partnerTitle;

  /// No description provided for @partnerTabPlayers.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get partnerTabPlayers;

  /// No description provided for @partnerTabPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get partnerTabPhone;

  /// No description provided for @partnerPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'+998 90 123 45 67'**
  String get partnerPhoneHint;

  /// No description provided for @partnerFind.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get partnerFind;

  /// No description provided for @partnerNotFound.
  ///
  /// In en, this message translates to:
  /// **'No player has this number'**
  String get partnerNotFound;

  /// No description provided for @partnerPickFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose a partner first'**
  String get partnerPickFirst;

  /// No description provided for @sendInvite.
  ///
  /// In en, this message translates to:
  /// **'Send invite'**
  String get sendInvite;

  /// No description provided for @inviteNote.
  ///
  /// In en, this message translates to:
  /// **'Your partner has 48 hours to accept, or until registration closes if that is sooner. The pair takes a spot once they accept.'**
  String get inviteNote;

  /// No description provided for @statusRegistered.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get statusRegistered;

  /// No description provided for @statusPendingPartner.
  ///
  /// In en, this message translates to:
  /// **'Waiting for partner'**
  String get statusPendingPartner;

  /// No description provided for @statusInvited.
  ///
  /// In en, this message translates to:
  /// **'Invitation'**
  String get statusInvited;

  /// No description provided for @statusWaitlisted.
  ///
  /// In en, this message translates to:
  /// **'On the waitlist'**
  String get statusWaitlisted;

  /// No description provided for @statusOffered.
  ///
  /// In en, this message translates to:
  /// **'Spot offered'**
  String get statusOffered;

  /// No description provided for @statusDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get statusDeclined;

  /// No description provided for @statusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get statusExpired;

  /// No description provided for @statusRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get statusRemoved;

  /// No description provided for @statusLapsed.
  ///
  /// In en, this message translates to:
  /// **'Offer lapsed'**
  String get statusLapsed;

  /// No description provided for @waitlistPlaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Place {place} in line'**
  String waitlistPlaceLabel(int place);

  /// No description provided for @pairedWith.
  ///
  /// In en, this message translates to:
  /// **'With {name}'**
  String pairedWith(String name);

  /// No description provided for @partnerInvitedYou.
  ///
  /// In en, this message translates to:
  /// **'{name} invited you as a partner'**
  String partnerInvitedYou(String name);

  /// No description provided for @acceptLabel.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get acceptLabel;

  /// No description provided for @claimLabel.
  ///
  /// In en, this message translates to:
  /// **'Claim'**
  String get claimLabel;

  /// No description provided for @offerHeld.
  ///
  /// In en, this message translates to:
  /// **'Held for you · {left} left'**
  String offerHeld(String left);

  /// No description provided for @durationHm.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String durationHm(int hours, int minutes);

  /// No description provided for @durationMin.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String durationMin(int minutes);

  /// No description provided for @cancelRegistration.
  ///
  /// In en, this message translates to:
  /// **'Cancel registration'**
  String get cancelRegistration;

  /// No description provided for @cancelRegistrationTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel registration?'**
  String get cancelRegistrationTitle;

  /// No description provided for @cancelRegistrationMsg.
  ///
  /// In en, this message translates to:
  /// **'Your spot goes to the next player in line. You can register again before the deadline if there is room.'**
  String get cancelRegistrationMsg;

  /// No description provided for @keepRegistration.
  ///
  /// In en, this message translates to:
  /// **'Keep registration'**
  String get keepRegistration;

  /// No description provided for @myTournamentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'You have no tournament entries yet'**
  String get myTournamentsEmpty;

  /// No description provided for @errTournamentFull.
  ///
  /// In en, this message translates to:
  /// **'This category just filled up'**
  String get errTournamentFull;

  /// No description provided for @errDeadlinePassed.
  ///
  /// In en, this message translates to:
  /// **'Registration has closed'**
  String get errDeadlinePassed;

  /// No description provided for @errTournamentLevel.
  ///
  /// In en, this message translates to:
  /// **'Your level, or that of your partner, is outside the range for this category'**
  String get errTournamentLevel;

  /// No description provided for @errAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'You are already in this category'**
  String get errAlreadyRegistered;

  /// No description provided for @errPartnerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This partner is already in the category'**
  String get errPartnerUnavailable;

  /// No description provided for @errNotFull.
  ///
  /// In en, this message translates to:
  /// **'There is room again. Register instead'**
  String get errNotFull;

  /// No description provided for @errWaitlistClosed.
  ///
  /// In en, this message translates to:
  /// **'This category has no waitlist'**
  String get errWaitlistClosed;

  /// No description provided for @errRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many phone lookups. Try again in an hour'**
  String get errRateLimited;

  /// No description provided for @notifTournamentFallback.
  ///
  /// In en, this message translates to:
  /// **'the tournament'**
  String get notifTournamentFallback;

  /// No description provided for @notifTournamentRegistered.
  ///
  /// In en, this message translates to:
  /// **'You are registered for {title}'**
  String notifTournamentRegistered(String title);

  /// No description provided for @notifTournamentPartnerInvite.
  ///
  /// In en, this message translates to:
  /// **'{actor} invited you to be their partner in {title}'**
  String notifTournamentPartnerInvite(String actor, String title);

  /// No description provided for @notifTournamentPartnerAccepted.
  ///
  /// In en, this message translates to:
  /// **'{actor} accepted your invitation for {title}'**
  String notifTournamentPartnerAccepted(String actor, String title);

  /// No description provided for @notifTournamentPartnerDeclined.
  ///
  /// In en, this message translates to:
  /// **'{actor} declined your invitation for {title}'**
  String notifTournamentPartnerDeclined(String actor, String title);

  /// No description provided for @notifTournamentPartnerCancelled.
  ///
  /// In en, this message translates to:
  /// **'{actor} cancelled your pair entry for {title}'**
  String notifTournamentPartnerCancelled(String actor, String title);

  /// No description provided for @notifTournamentPartnerExpired.
  ///
  /// In en, this message translates to:
  /// **'Your partner did not answer in time for {title}'**
  String notifTournamentPartnerExpired(String title);

  /// No description provided for @notifTournamentSpotOffered.
  ///
  /// In en, this message translates to:
  /// **'A spot opened for you in {title}. Claim it before it goes'**
  String notifTournamentSpotOffered(String title);

  /// No description provided for @notifTournamentDeadlineReminder.
  ///
  /// In en, this message translates to:
  /// **'Registration for {title} closes soon and your partner has not answered'**
  String notifTournamentDeadlineReminder(String title);

  /// No description provided for @notifTournamentRemoved.
  ///
  /// In en, this message translates to:
  /// **'You were removed from {title}'**
  String notifTournamentRemoved(String title);

  /// No description provided for @notifTournamentMoved.
  ///
  /// In en, this message translates to:
  /// **'You were moved to another category in {title}'**
  String notifTournamentMoved(String title);

  /// No description provided for @notifTournamentMovedTo.
  ///
  /// In en, this message translates to:
  /// **'You were moved to {category} in {title}'**
  String notifTournamentMovedTo(String category, String title);

  /// No description provided for @adminTournaments.
  ///
  /// In en, this message translates to:
  /// **'Tournaments'**
  String get adminTournaments;

  /// No description provided for @adminTournamentsHint.
  ///
  /// In en, this message translates to:
  /// **'Categories and participants'**
  String get adminTournamentsHint;

  /// No description provided for @adminDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get adminDashboard;

  /// No description provided for @adminDashboardHint.
  ///
  /// In en, this message translates to:
  /// **'Users, revenue and activity'**
  String get adminDashboardHint;

  /// No description provided for @addTournament.
  ///
  /// In en, this message translates to:
  /// **'Add tournament'**
  String get addTournament;

  /// No description provided for @newTournament.
  ///
  /// In en, this message translates to:
  /// **'New tournament'**
  String get newTournament;

  /// No description provided for @noAdminTournaments.
  ///
  /// In en, this message translates to:
  /// **'No tournaments match'**
  String get noAdminTournaments;

  /// No description provided for @tournamentCounts.
  ///
  /// In en, this message translates to:
  /// **'{categories} categories · {entries} entries'**
  String tournamentCounts(int categories, int entries);

  /// No description provided for @tournamentDetails.
  ///
  /// In en, this message translates to:
  /// **'Tournament details'**
  String get tournamentDetails;

  /// No description provided for @noVenue.
  ///
  /// In en, this message translates to:
  /// **'No venue'**
  String get noVenue;

  /// No description provided for @firstDayLabel.
  ///
  /// In en, this message translates to:
  /// **'First day'**
  String get firstDayLabel;

  /// No description provided for @lastDayLabel.
  ///
  /// In en, this message translates to:
  /// **'Last day'**
  String get lastDayLabel;

  /// No description provided for @deadlineLabel.
  ///
  /// In en, this message translates to:
  /// **'Registration closes'**
  String get deadlineLabel;

  /// No description provided for @coverUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Cover image link (https://…)'**
  String get coverUrlLabel;

  /// No description provided for @participantsLabel.
  ///
  /// In en, this message translates to:
  /// **'Participants'**
  String get participantsLabel;

  /// No description provided for @addCategory.
  ///
  /// In en, this message translates to:
  /// **'Add category'**
  String get addCategory;

  /// No description provided for @newCategory.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get newCategory;

  /// No description provided for @editCategory.
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get editCategory;

  /// No description provided for @deleteCategory.
  ///
  /// In en, this message translates to:
  /// **'Delete category'**
  String get deleteCategory;

  /// No description provided for @addCategoryFirst.
  ///
  /// In en, this message translates to:
  /// **'Add at least one category'**
  String get addCategoryFirst;

  /// No description provided for @categoriesHint.
  ///
  /// In en, this message translates to:
  /// **'Players register in a category. A tournament always keeps at least one.'**
  String get categoriesHint;

  /// No description provided for @capLabel.
  ///
  /// In en, this message translates to:
  /// **'Places'**
  String get capLabel;

  /// No description provided for @typeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get typeLabel;

  /// No description provided for @genderLabel.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get genderLabel;

  /// No description provided for @minLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Lowest level'**
  String get minLevelLabel;

  /// No description provided for @maxLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Highest level'**
  String get maxLevelLabel;

  /// No description provided for @waitlistLabel.
  ///
  /// In en, this message translates to:
  /// **'Waitlist'**
  String get waitlistLabel;

  /// No description provided for @waitlistHint.
  ///
  /// In en, this message translates to:
  /// **'When a spot frees up, the next in line gets 24 hours to claim it'**
  String get waitlistHint;

  /// No description provided for @capBelowFilled.
  ///
  /// In en, this message translates to:
  /// **'The places cannot be lower than the {filled} entries already holding a spot'**
  String capBelowFilled(int filled);

  /// No description provided for @errHasRegistrations.
  ///
  /// In en, this message translates to:
  /// **'This category has registrations and cannot be deleted or changed to another type'**
  String get errHasRegistrations;

  /// No description provided for @errNotMarkable.
  ///
  /// In en, this message translates to:
  /// **'Only registered entries can be marked paid'**
  String get errNotMarkable;

  /// No description provided for @paidLabel.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paidLabel;

  /// No description provided for @moveRegistration.
  ///
  /// In en, this message translates to:
  /// **'Move to another category'**
  String get moveRegistration;

  /// No description provided for @removeEntry.
  ///
  /// In en, this message translates to:
  /// **'Remove entry'**
  String get removeEntry;

  /// No description provided for @addPlayer.
  ///
  /// In en, this message translates to:
  /// **'Add player'**
  String get addPlayer;

  /// No description provided for @addPlayerNote.
  ///
  /// In en, this message translates to:
  /// **'Added players skip the level check, never the places limit'**
  String get addPlayerNote;

  /// No description provided for @offerNext.
  ///
  /// In en, this message translates to:
  /// **'Offer next'**
  String get offerNext;

  /// No description provided for @offerNextResult.
  ///
  /// In en, this message translates to:
  /// **'Offers sent: {count}'**
  String offerNextResult(int count);

  /// No description provided for @copyCsv.
  ///
  /// In en, this message translates to:
  /// **'Copy CSV'**
  String get copyCsv;

  /// No description provided for @csvCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to the clipboard'**
  String get csvCopied;

  /// No description provided for @noEntriesYet.
  ///
  /// In en, this message translates to:
  /// **'No entries yet'**
  String get noEntriesYet;

  /// No description provided for @pastEntries.
  ///
  /// In en, this message translates to:
  /// **'Past entries ({count})'**
  String pastEntries(int count);

  /// No description provided for @periodCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get periodCustom;

  /// No description provided for @usersTitle.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get usersTitle;

  /// No description provided for @usersTotal.
  ///
  /// In en, this message translates to:
  /// **'Total users'**
  String get usersTotal;

  /// No description provided for @usersActive.
  ///
  /// In en, this message translates to:
  /// **'Active in 30 days'**
  String get usersActive;

  /// No description provided for @usersNewToday.
  ///
  /// In en, this message translates to:
  /// **'New today'**
  String get usersNewToday;

  /// No description provided for @usersNew7.
  ///
  /// In en, this message translates to:
  /// **'New in 7 days'**
  String get usersNew7;

  /// No description provided for @usersNewMonth.
  ///
  /// In en, this message translates to:
  /// **'New this month'**
  String get usersNewMonth;

  /// No description provided for @revenueTitle.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get revenueTitle;

  /// No description provided for @revenueCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get revenueCurrency;

  /// No description provided for @revenueVenues.
  ///
  /// In en, this message translates to:
  /// **'Venues'**
  String get revenueVenues;

  /// No description provided for @revenueTournaments.
  ///
  /// In en, this message translates to:
  /// **'Tournaments'**
  String get revenueTournaments;

  /// No description provided for @revenueNote.
  ///
  /// In en, this message translates to:
  /// **'Each currency has its own row. Amounts in different currencies are never added together.'**
  String get revenueNote;

  /// No description provided for @noRevenue.
  ///
  /// In en, this message translates to:
  /// **'No paid bookings or entry fees in this period'**
  String get noRevenue;

  /// No description provided for @activityTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activityTitle;

  /// No description provided for @countBookings.
  ///
  /// In en, this message translates to:
  /// **'Bookings created'**
  String get countBookings;

  /// No description provided for @countBookingsNote.
  ///
  /// In en, this message translates to:
  /// **'including cancelled'**
  String get countBookingsNote;

  /// No description provided for @countGames.
  ///
  /// In en, this message translates to:
  /// **'Games created'**
  String get countGames;

  /// No description provided for @countRegistrations.
  ///
  /// In en, this message translates to:
  /// **'Tournament entries'**
  String get countRegistrations;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'kk', 'ru', 'uz'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'kk':
      return AppLocalizationsKk();
    case 'ru':
      return AppLocalizationsRu();
    case 'uz':
      return AppLocalizationsUz();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
