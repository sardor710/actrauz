import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
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
      <String>['en', 'ru', 'uz'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
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
