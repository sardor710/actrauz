// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Actra';

  @override
  String get continueLabel => 'Continue';

  @override
  String get cancel => 'Cancel';

  @override
  String get seeAll => 'See all';

  @override
  String get today => 'Today';

  @override
  String get tomorrow => 'Tomorrow';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get errGeneric => 'Something went wrong. Try again.';

  @override
  String get chooseLanguage => 'Choose your language';

  @override
  String get chooseCity => 'Choose your city';

  @override
  String get chooseCityHint => 'You can change it any time in your profile';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get signInTelegram => 'Continue with Telegram';

  @override
  String get demoNotice =>
      'Demo mode: Telegram sign-in is connected in the next release. Enter a name to continue. Venues, games and tournaments shown are sample data.';

  @override
  String get yourName => 'Your name';

  @override
  String get nameRequired => 'Enter your name';

  @override
  String get tabHome => 'Home';

  @override
  String get tabVenues => 'Venues';

  @override
  String get tabGames => 'Games';

  @override
  String get tabProfile => 'Profile';

  @override
  String greeting(String name) {
    return 'Hello, $name';
  }

  @override
  String get homeGames => 'Available games';

  @override
  String get homeCourts => 'Free courts today';

  @override
  String get homeTournaments => 'Tournaments';

  @override
  String get noGames => 'No open games yet';

  @override
  String get noCourtsToday => 'No free slots left today';

  @override
  String get searchVenues => 'Search venues';

  @override
  String get allSports => 'All sports';

  @override
  String get noVenues => 'No venues found';

  @override
  String fromPrice(String price) {
    return 'from $price';
  }

  @override
  String slotLength(int minutes) {
    return '$minutes min';
  }

  @override
  String get workingHours => 'Working hours';

  @override
  String get closed => 'Closed';

  @override
  String get weekdays => 'Mon–Fri';

  @override
  String get saturday => 'Sat';

  @override
  String get sunday => 'Sun';

  @override
  String get amenities => 'Amenities';

  @override
  String get amenityParking => 'Parking';

  @override
  String get amenityShowers => 'Showers';

  @override
  String get amenityLighting => 'Lighting';

  @override
  String get amenityCafe => 'Café';

  @override
  String get amenityRental => 'Equipment rental';

  @override
  String get courts => 'Courts';

  @override
  String get indoor => 'Indoor';

  @override
  String get outdoor => 'Outdoor';

  @override
  String get book => 'Book';

  @override
  String get phone => 'Phone';

  @override
  String get address => 'Address';

  @override
  String get about => 'About the venue';

  @override
  String get bookingTitle => 'Choose a time';

  @override
  String get closedThatDay => 'The court is closed on this day';

  @override
  String get selectHint => 'Pick one slot or several in a row';

  @override
  String slotsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count slots',
      one: '$count slot',
    );
    return '$_temp0';
  }

  @override
  String get total => 'Total';

  @override
  String get summaryTitle => 'Booking summary';

  @override
  String heldFor(String time) {
    return 'Slots are held for you: $time';
  }

  @override
  String get holdExpiredMsg =>
      'The hold has expired. Please choose the time again.';

  @override
  String get paymentMethod => 'Payment method';

  @override
  String get payAtVenue => 'Pay at venue';

  @override
  String get payAtVenueHint => 'Cash or card at the venue';

  @override
  String get playersCount => 'Number of players';

  @override
  String get noteLabel => 'Note (optional)';

  @override
  String get confirmBooking => 'Confirm booking';

  @override
  String get bookingConfirmed => 'Booking confirmed';

  @override
  String get dateLabel => 'Date';

  @override
  String get timeLabel => 'Time';

  @override
  String get courtLabel => 'Court';

  @override
  String get errSlotTaken =>
      'Someone has just taken this time. Choose another one.';

  @override
  String get errNotContiguous => 'Slots must be next to each other';

  @override
  String errTooManyBookings(int count) {
    return 'You already have $count upcoming bookings';
  }

  @override
  String errTooFarAhead(int days) {
    return 'Booking opens $days days in advance';
  }

  @override
  String get errInPast => 'This time has already passed';

  @override
  String get myBookings => 'My bookings';

  @override
  String get noBookings => 'You have no bookings yet';

  @override
  String get statusConfirmed => 'Confirmed';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get cancelBooking => 'Cancel booking';

  @override
  String get cancelConfirmTitle => 'Cancel this booking?';

  @override
  String get cancelFreeMsg => 'Cancellation is free.';

  @override
  String cancelLateMsg(int hours) {
    return 'Less than $hours hours are left before the start. This counts as a late cancellation and lowers your reliability.';
  }

  @override
  String get keepBooking => 'Keep booking';

  @override
  String get bookingCancelled => 'Booking cancelled';

  @override
  String get lateCancellation => 'Late cancellation';

  @override
  String spotsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count spots left',
      one: '$count spot left',
      zero: 'Full',
    );
    return '$_temp0';
  }

  @override
  String levelRange(int min, int max) {
    return 'Level $min–$max';
  }

  @override
  String perPlayer(String price) {
    return '≈ $price per player';
  }

  @override
  String get host => 'Host';

  @override
  String get players => 'Players';

  @override
  String get joinGame => 'Join';

  @override
  String get leaveGame => 'Leave game';

  @override
  String get errGameFull => 'This game is already full';

  @override
  String get errLevel => 'Your level is outside the range for this game';

  @override
  String get you => 'You';

  @override
  String get entryFee => 'Entry fee';

  @override
  String filledOf(int filled, int total) {
    return '$filled of $total filled';
  }

  @override
  String get language => 'Language';

  @override
  String get city => 'City';

  @override
  String get signOut => 'Sign out';

  @override
  String get currencyUzs => 'UZS';

  @override
  String get currencyKzt => '₸';
}
