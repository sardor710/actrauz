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
  String get detectingCity => 'Finding your city…';

  @override
  String cityDetected(String city) {
    return 'Found: $city';
  }

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
  String get telegramHint =>
      'Telegram will open. Tap Start there and share your phone number — it becomes your Actra account.';

  @override
  String get telegramWaiting =>
      'Waiting for Telegram. Share your phone number with the Actra bot, then come back here.';

  @override
  String get telegramOpenAgain => 'Open Telegram again';

  @override
  String get telegramExpired =>
      'The sign-in link has expired. Please try again.';

  @override
  String get signInFailed =>
      'Could not sign in. Check your connection and try again.';

  @override
  String get acceptTerms => 'I accept the Terms of Use and the Privacy Policy';

  @override
  String get termsRequired => 'Accept the terms to continue';

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
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountTitle => 'Delete your account?';

  @override
  String get deleteAccountBody =>
      'Your upcoming bookings and tournament entries will be cancelled and you will leave your games. Your name and phone number will be removed. This cannot be undone.';

  @override
  String get deleteAccountConfirm => 'Delete';

  @override
  String get deleteAccountAdmin =>
      'An admin account cannot be deleted. Ask another admin to remove your admin role first.';

  @override
  String get deletedPlayer => 'Deleted player';

  @override
  String get currencyUzs => 'UZS';

  @override
  String get currencyKzt => '₸';

  @override
  String get searchHint => 'Search venues and sports';

  @override
  String get gamesBySports => 'Games by sport';

  @override
  String get venuesNearYou => 'Venues near you';

  @override
  String get tabTournaments => 'Tournaments';

  @override
  String get tabSocial => 'Social';

  @override
  String get allDays => 'All';

  @override
  String get filterSport => 'Sport';

  @override
  String get myLevel => 'My level';

  @override
  String going(int count, int spots) {
    return '$count/$spots going';
  }

  @override
  String gameTitle(String host, String sport) {
    return '$sport with $host';
  }

  @override
  String get createGame => 'Create a game';

  @override
  String get gamesPromoTitle => 'Short of players?';

  @override
  String get gamesPromoText =>
      'Join a game at your level or fill your own court';

  @override
  String get bookable => 'Bookable';

  @override
  String get favourites => 'Favourites';

  @override
  String get sortPrice => 'Cheapest first';

  @override
  String get priceStartingFrom => 'Price starting from';

  @override
  String get registrationOpen => 'Registration open';

  @override
  String get tournamentFull => 'Full';

  @override
  String get noTournaments => 'No tournaments announced yet';

  @override
  String get tournamentsPromoTitle => 'Play for the cup';

  @override
  String get tournamentsPromoText => 'Singles and pairs for every level';

  @override
  String get discoverTeams => 'Discover teams';

  @override
  String get noTeams => 'No teams in this city yet';

  @override
  String members(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '$count member',
    );
    return '$_temp0';
  }

  @override
  String upcomingGames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count games soon',
      one: '$count game soon',
    );
    return '$_temp0';
  }

  @override
  String get playersNearYou => 'Players near you';

  @override
  String level(int level) {
    return 'Level $level';
  }

  @override
  String get inviteTitle => 'Bring your friends';

  @override
  String get inviteText =>
      'Invite friends to Actra and fill your games faster.';

  @override
  String get inviteCta => 'Invite friends';

  @override
  String get statBookings => 'Bookings';

  @override
  String get statGames => 'Games';

  @override
  String get statLate => 'Late cancels';

  @override
  String get mySports => 'My sports';

  @override
  String get morning => 'Morning';

  @override
  String get afternoon => 'Afternoon';

  @override
  String get evening => 'Evening';

  @override
  String get everyDay => 'Every day';

  @override
  String get gamesPromoCta => 'Book a court';

  @override
  String get myVenues => 'My venues';

  @override
  String get ownerCalendar => 'Booking calendar';

  @override
  String get noVenuesAssigned => 'No venues are assigned to you yet';

  @override
  String get prevWeek => 'Previous week';

  @override
  String get nextWeek => 'Next week';

  @override
  String get slotFree => 'Free';

  @override
  String get slotBooked => 'Booked';

  @override
  String get slotBlocked => 'Blocked';

  @override
  String get closedThatWeek => 'The court is closed this week';

  @override
  String get newBooking => 'New booking';

  @override
  String get blockTime => 'Block time';

  @override
  String get customerName => 'Customer name';

  @override
  String get customerNameRequired => 'Enter the customer name';

  @override
  String get customerPhone => 'Phone number (optional)';

  @override
  String get slotsCountLabel => 'Number of slots';

  @override
  String get payCash => 'Cash';

  @override
  String get payCard => 'Card';

  @override
  String get payTransfer => 'Transfer';

  @override
  String get saveBooking => 'Save booking';

  @override
  String get blockReason => 'Reason (optional)';

  @override
  String get blockConfirm => 'Block this time';

  @override
  String get unblock => 'Open this time again';

  @override
  String get customerLabel => 'Customer';

  @override
  String get sourceLabel => 'Source';

  @override
  String get statusLabel => 'Status';

  @override
  String get reasonLabel => 'Reason';

  @override
  String get sourceApp => 'Booked in the app';

  @override
  String get sourceWalkIn => 'Walk-in or phone';

  @override
  String get sourceBlock => 'Blocked by the venue';

  @override
  String get markPaid => 'Mark paid';

  @override
  String get markNoShow => 'Mark no-show';

  @override
  String get statusPaid => 'Paid';

  @override
  String get statusNoShow => 'No-show';

  @override
  String get statusUnverified => 'Not confirmed';

  @override
  String get statusCancelledByVenue => 'Cancelled by the venue';

  @override
  String get markAfterStart =>
      'Paid and no-show can be marked once the booking has started';

  @override
  String get cancelByVenueMsg =>
      'The time becomes free at once. A player who booked in the app will see that the venue cancelled it.';

  @override
  String get errNotAllowed => 'You do not manage this venue';

  @override
  String get bookingSaved => 'Booking saved';

  @override
  String get ownerSettings => 'Hours and prices';

  @override
  String get ownerDashboard => 'Dashboard';

  @override
  String get venueHours => 'Venue working hours';

  @override
  String get courtHours => 'Court hours';

  @override
  String get sameAsVenue => 'Same as venue';

  @override
  String get openLabel => 'Open';

  @override
  String get editLabel => 'Edit';

  @override
  String get saveLabel => 'Save';

  @override
  String get savedMsg => 'Saved';

  @override
  String get pricesTitle => 'Prices';

  @override
  String get hoursTitle => 'Hours';

  @override
  String get slotLengthLabel => 'Slot length';

  @override
  String get basePrice => 'Base price per slot';

  @override
  String get priceRules => 'Price rules';

  @override
  String get addRule => 'Add rule';

  @override
  String get removeRule => 'Remove rule';

  @override
  String get ruleFrom => 'From';

  @override
  String get ruleTo => 'To';

  @override
  String get rulePrice => 'Price per slot';

  @override
  String get noRules => 'No rules: every slot costs the base price';

  @override
  String rulesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count price rules',
      one: '$count price rule',
      zero: 'No price rules',
    );
    return '$_temp0';
  }

  @override
  String get errInvalidHours => 'Opening must be earlier than closing';

  @override
  String get errRulesOverlap => 'Two rules cover the same day and time';

  @override
  String get errInvalidArgument => 'Check the values and try again';

  @override
  String get errPickWeekday => 'Choose at least one day';

  @override
  String get errPrice => 'Enter a price';

  @override
  String get period7 => 'Last 7 days';

  @override
  String get periodMonth => 'This month';

  @override
  String get allCourts => 'All courts';

  @override
  String metricSplit(int app, int walkIn) {
    return 'App $app · walk-in $walkIn';
  }

  @override
  String get metricRevenue => 'Paid revenue';

  @override
  String get metricUnconfirmed => 'Unconfirmed revenue';

  @override
  String get metricDailyAvg => 'Bookings per day';

  @override
  String get metricUtilisation => 'Utilisation';

  @override
  String get metricNoShows => 'No-shows';

  @override
  String get peakHours => 'Peak hours';

  @override
  String get noDataPeriod => 'No bookings in this period';

  @override
  String get adminTitle => 'Admin';

  @override
  String get adminOnly => 'Only Actra administrators can open this page';

  @override
  String get adminSports => 'Sports';

  @override
  String get adminBanners => 'Banners';

  @override
  String get adminAudit => 'Audit log';

  @override
  String get adminAuditHint => 'Who changed what, and when';

  @override
  String venuesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count venues',
      one: '$count venue',
    );
    return '$_temp0';
  }

  @override
  String sportsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sports',
      one: '$count sport',
    );
    return '$_temp0';
  }

  @override
  String bannersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count banners',
      one: '$count banner',
    );
    return '$_temp0';
  }

  @override
  String courtsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count courts',
      one: '$count court',
    );
    return '$_temp0';
  }

  @override
  String ownersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count owners',
      one: '$count owner',
      zero: 'No owners',
    );
    return '$_temp0';
  }

  @override
  String playersN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count players',
      one: '$count player',
    );
    return '$_temp0';
  }

  @override
  String get inactive => 'Inactive';

  @override
  String get activeLabel => 'Active';

  @override
  String get activeHint => 'Players can see it';

  @override
  String get addVenue => 'Add venue';

  @override
  String get newVenue => 'New venue';

  @override
  String get venueDetails => 'Details';

  @override
  String get nameLabel => 'Name';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get districtLabel => 'District';

  @override
  String get nameRequiredAny => 'Fill in at least one language';

  @override
  String get saveVenueFirst => 'Save the venue to add courts and owners';

  @override
  String get addCourt => 'Add court';

  @override
  String get newCourt => 'New court';

  @override
  String get editCourt => 'Edit court';

  @override
  String get noCourts => 'No courts yet';

  @override
  String get courtActions => 'Court actions';

  @override
  String get duplicateLabel => 'Duplicate';

  @override
  String get deleteLabel => 'Delete';

  @override
  String get deleteVenue => 'Delete venue';

  @override
  String deleteConfirmTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get deleteConfirmMsg => 'This cannot be undone.';

  @override
  String get errHasBookings =>
      'It has bookings, so it cannot be deleted. Deactivate it to hide it from players.';

  @override
  String get deactivateInstead => 'Deactivate instead';

  @override
  String get errAlreadyExists => 'This ID is already taken';

  @override
  String get errNotFound => 'Not found. Refresh and try again.';

  @override
  String get ownersTitle => 'Owners';

  @override
  String get assignOwner => 'Assign owner';

  @override
  String get removeOwner => 'Remove owner';

  @override
  String get noOwners => 'No owners assigned';

  @override
  String get searchUsers => 'Name or phone';

  @override
  String get searchUsersMin => 'Type at least 2 characters';

  @override
  String get noUsersFound => 'Nobody found';

  @override
  String get addSport => 'Add sport';

  @override
  String get newSport => 'New sport';

  @override
  String get editSport => 'Edit sport';

  @override
  String get sportIdLabel => 'ID';

  @override
  String get sportIdHint =>
      'Lowercase Latin letters, digits and _, for example squash. Cannot be changed later.';

  @override
  String get errSportId =>
      '2–30 characters: lowercase Latin letters, digits or _, starting with a letter';

  @override
  String get iconLabel => 'Icon';

  @override
  String get sportTypeLabel => 'Type';

  @override
  String get placeOnly => 'Place only';

  @override
  String get ratingLabel => 'Rating';

  @override
  String get ratingSimple => 'Level 1–5';

  @override
  String get ratingCompetitive => 'Rating 1.0–7.0';

  @override
  String get defaultPlayers => 'Default players';

  @override
  String get sortOrderLabel => 'Position in list';

  @override
  String get addBanner => 'Add banner';

  @override
  String get newBanner => 'New banner';

  @override
  String get editBanner => 'Edit banner';

  @override
  String get bannerTitle => 'Title';

  @override
  String get bannerSubtitle => 'Subtitle';

  @override
  String get linkLabel => 'Link';

  @override
  String get errUrl => 'The link must start with https://';

  @override
  String get allCities => 'All cities';

  @override
  String get noBanners => 'No banners yet';

  @override
  String get auditEmpty => 'No changes recorded yet';

  @override
  String get loadMore => 'Load more';

  @override
  String get auditBefore => 'Before';

  @override
  String get auditAfter => 'After';

  @override
  String get auditSystem => 'System';

  @override
  String get auditCreateVenue => 'Venue created';

  @override
  String get auditUpdateVenue => 'Venue updated';

  @override
  String get auditDeleteVenue => 'Venue deleted';

  @override
  String get auditCreateCourt => 'Court created';

  @override
  String get auditUpdateCourt => 'Court updated';

  @override
  String get auditDuplicateCourt => 'Court duplicated';

  @override
  String get auditDeleteCourt => 'Court deleted';

  @override
  String get auditAssignOwner => 'Owner assigned';

  @override
  String get auditRemoveOwner => 'Owner removed';

  @override
  String get auditCreateSport => 'Sport created';

  @override
  String get auditUpdateSport => 'Sport updated';

  @override
  String get auditCreateBanner => 'Banner created';

  @override
  String get auditUpdateBanner => 'Banner updated';

  @override
  String get auditDeleteBanner => 'Banner deleted';

  @override
  String get auditVenueHours => 'Venue hours changed';

  @override
  String get auditCourtHours => 'Court hours changed';

  @override
  String get auditCourtPricing => 'Court prices changed';

  @override
  String get auditWalkIn => 'Walk-in booking added';

  @override
  String get auditBlock => 'Time blocked';

  @override
  String get auditMarkBooking => 'Booking marked';

  @override
  String get auditOwnerAccountDeleted => 'Owner deleted their account';

  @override
  String get auditHideSample => 'Sample data hidden';

  @override
  String get entityVenue => 'Venue';

  @override
  String get entityBanner => 'Banner';

  @override
  String get entityBooking => 'Booking';

  @override
  String get entityOwner => 'Venue owner';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get notificationSettings => 'Notification settings';

  @override
  String get noNotifications => 'No notifications yet';

  @override
  String get notificationsAndPrivacy => 'Notifications and privacy';

  @override
  String get notificationsMuteHint =>
      'Choose what you hear about. Switch a group off to stop its notifications.';

  @override
  String get notifCategoryBookings => 'Bookings';

  @override
  String get notifCategoryVenue => 'My venues';

  @override
  String get notifCategoryGames => 'Games';

  @override
  String get notifCategoryRequests => 'Game Requests';

  @override
  String get notifCategoryInvites => 'Invitations';

  @override
  String get notifCategoryTournaments => 'Tournaments';

  @override
  String get privacyTitle => 'Privacy';

  @override
  String get hideFromSearch => 'Hide me from player search';

  @override
  String get hideFromSearchHint =>
      'Other players will not find you when they look for people to invite.';

  @override
  String get notifSomeone => 'Someone';

  @override
  String get notifVenueFallback => 'the venue';

  @override
  String get notifCourtFallback => 'a court';

  @override
  String notifBookingConfirmed(String venue) {
    return 'Your booking at $venue is confirmed';
  }

  @override
  String notifBookingCancelledByVenue(String venue) {
    return '$venue cancelled your booking';
  }

  @override
  String notifBookingReminder(String venue) {
    return 'Reminder: your booking at $venue is coming up';
  }

  @override
  String notifVenueNewBooking(String actor, String court) {
    return '$actor booked $court';
  }

  @override
  String notifVenueBookingCancelled(String actor, String court) {
    return '$actor cancelled $court';
  }

  @override
  String notifGameJoined(String actor) {
    return '$actor joined your game';
  }

  @override
  String notifGameLeft(String actor) {
    return '$actor left your game';
  }

  @override
  String notifJoinRequest(String actor) {
    return '$actor asked to join your game';
  }

  @override
  String get notifJoinApproved => 'You are in! The host approved your request';

  @override
  String get notifJoinDeclined => 'The host declined your request';

  @override
  String get notifGameFull => 'Your game is full';

  @override
  String get notifGameChanged => 'The host changed the game details';

  @override
  String get notifGameCancelled => 'The game was cancelled';

  @override
  String get notifGameRemoved => 'The host removed you from the game';

  @override
  String get notifGameReminder => 'Reminder: your game starts soon';

  @override
  String notifGameInvite(String actor) {
    return '$actor invited you to a game';
  }

  @override
  String notifRequestInterest(String actor) {
    return '$actor is in for your Game Request';
  }

  @override
  String get notifRequestConvertedIn =>
      'Your Game Request became a game, and you are in';

  @override
  String get notifRequestConvertedFull =>
      'Your Game Request became a game, but it filled up before you';

  @override
  String get notifRequestExpired => 'A Game Request expired';

  @override
  String get notifUnknown => 'New notification';

  @override
  String get reliabilityNew => 'New player';

  @override
  String get reliabilityReliable => 'Reliable';

  @override
  String get reliabilityLimited => 'Limited';

  @override
  String get reliabilityBlocked => 'Blocked';

  @override
  String reliabilityScore(int score) {
    return 'Reliability score $score of 100';
  }

  @override
  String get reliabilityLimitedHint =>
      'You can hold one upcoming booking at a time. Show up and play to recover.';

  @override
  String get reliabilityBlockedHint =>
      'You cannot book, join or post until older missed games pass 90 days.';

  @override
  String get gameSportLabel => 'Sport';

  @override
  String get pickSportHint => 'Choose a sport to set up your game';

  @override
  String get gameBookingLabel => 'Your court booking';

  @override
  String get noBookingForSport =>
      'You have no upcoming confirmed booking for this sport. Book a court first, then create a game on it.';

  @override
  String get bookACourt => 'Book a court';

  @override
  String get gamePlaceLabel => 'Where';

  @override
  String get placeVenue => 'Venue';

  @override
  String get placeMeetingPoint => 'Meeting point';

  @override
  String get chooseVenue => 'Choose a venue';

  @override
  String get meetingPointHint => 'For example: main gate of the park';

  @override
  String get meetingPointRequired => 'Enter a meeting point';

  @override
  String get venueRequired => 'Choose a venue';

  @override
  String get gameWhenLabel => 'When';

  @override
  String get gameStartTime => 'Start';

  @override
  String get gameDuration => 'Duration';

  @override
  String minutesShort(int count) {
    return '$count min';
  }

  @override
  String get distanceLabel => 'Distance, km (optional)';

  @override
  String get paceLabel => 'Pace (optional)';

  @override
  String get paceHint => 'For example 6:00 min/km';

  @override
  String distanceValue(String km) {
    return '$km km';
  }

  @override
  String paceValue(String pace) {
    return 'Pace $pace';
  }

  @override
  String get spotsLabel => 'Spots, host included';

  @override
  String get fewerSpots => 'Fewer spots';

  @override
  String get moreSpots => 'More spots';

  @override
  String get levelRangeLabel => 'Level range';

  @override
  String get visibilityLabel => 'Who can see it';

  @override
  String get visibilityPublic => 'Public';

  @override
  String get visibilityInviteOnly => 'Invite only';

  @override
  String get askToJoin => 'Ask to join';

  @override
  String get requested => 'Requested';

  @override
  String get withdrawRequest => 'Withdraw request';

  @override
  String get invitedToGame => 'You are invited to this game';

  @override
  String get invitedPill => 'Invited';

  @override
  String get acceptInvite => 'Accept';

  @override
  String get declineLabel => 'Decline';

  @override
  String get approveLabel => 'Approve';

  @override
  String get requestsTitle => 'Requests';

  @override
  String get hostTools => 'Host tools';

  @override
  String get editGame => 'Edit game';

  @override
  String get cancelGame => 'Cancel game';

  @override
  String get cancelGameTitle => 'Cancel this game?';

  @override
  String get cancelGameMsg => 'The players will be told.';

  @override
  String get alsoCancelBooking => 'Also cancel my court booking';

  @override
  String get alsoCancelBookingHint =>
      'Frees the court for others. Late cancellation rules still apply.';

  @override
  String get keepGame => 'Keep game';

  @override
  String get gameCancelled => 'Game cancelled';

  @override
  String get gameCancelledBanner => 'This game was cancelled';

  @override
  String get removePlayer => 'Remove player';

  @override
  String removePlayerTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get removePlayerMsg => 'They will be told they were removed.';

  @override
  String get removeLabel => 'Remove';

  @override
  String get createGameFromBooking => 'Create a game from this booking';

  @override
  String get errSpotsBelowPlayers =>
      'Spots cannot be fewer than the players already in the game';

  @override
  String get errAlreadyJoined => 'You are already in this game';

  @override
  String get errNotParticipant => 'You are not in this game';

  @override
  String get errHostCannotLeave =>
      'The host cannot leave. Cancel the game instead.';

  @override
  String get errAlreadyRequested => 'You have already asked to join this game';

  @override
  String get errBookingNotUsable =>
      'Choose your own confirmed booking for this sport that has not started yet';

  @override
  String get errGameExists => 'This booking already has a game';

  @override
  String get errForbidden => 'You cannot do this in this game';

  @override
  String get errNotCancellable =>
      'The game has already started, so it cannot be cancelled';

  @override
  String get errScoreClosed => 'A score can no longer be entered for this game';

  @override
  String get errUnavailable =>
      'Cannot reach the server. Check your connection.';

  @override
  String get gamesTabRequests => 'Requests';

  @override
  String get homeRequests => 'Game Requests';

  @override
  String interestedOf(int count, int total) {
    return '$count of $total interested';
  }

  @override
  String requestTitle(String host, String sport) {
    return '$host wants to play $sport';
  }

  @override
  String needsPlayers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Needs $count more players',
      one: 'Needs $count more player',
    );
    return '$_temp0';
  }

  @override
  String get noRequests => 'No Game Requests yet. Post one to find players.';

  @override
  String get postRequest => 'Post a request';

  @override
  String get createRequestTitle => 'Game Request';

  @override
  String get requestPlayersNeeded => 'Players needed';

  @override
  String get requestWindowLabel => 'When can you play?';

  @override
  String get requestFrom => 'From';

  @override
  String get requestTo => 'To';

  @override
  String get areaLabel => 'Area (optional)';

  @override
  String get areaHint => 'For example, Yunusobod';

  @override
  String get venueOptional => 'Venue (optional)';

  @override
  String get anyVenue => 'Any venue';

  @override
  String get postRequestCta => 'Post request';

  @override
  String get imIn => 'I\'m in';

  @override
  String get leaveRequest => 'Leave';

  @override
  String get interestedPlayers => 'Interested';

  @override
  String get noInterestedYet => 'Nobody has said they are in yet';

  @override
  String get makeItAGame => 'Make it a game';

  @override
  String get convertHint =>
      'The players who are in are added in the order they tapped, while spots last.';

  @override
  String get gameEndTime => 'End';

  @override
  String get cancelRequestLabel => 'Cancel request';

  @override
  String get cancelRequestTitle => 'Cancel this request?';

  @override
  String get cancelRequestMsg =>
      'The players who said they are in will no longer see it.';

  @override
  String get keepRequest => 'Keep request';

  @override
  String get requestCancelledMsg => 'Request cancelled';

  @override
  String get removeInterestedMsg => 'They will be taken off the list.';

  @override
  String get requestConvertedBanner => 'This request became a game';

  @override
  String get openGameCta => 'Open the game';

  @override
  String get requestClosedBanner => 'This request is closed';

  @override
  String get findPlayers => 'Find players';

  @override
  String get searchPlayersHint => 'Search by name';

  @override
  String get noPlayersFound => 'No players found';

  @override
  String gamesPlayed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count games played',
      one: '$count game played',
    );
    return '$_temp0';
  }

  @override
  String get playerProfileTitle => 'Player profile';

  @override
  String get profileLevels => 'Levels';

  @override
  String get noLevelsYet => 'No levels set yet';

  @override
  String get inviteToGame => 'Invite to a game';

  @override
  String get chooseGameToInvite => 'Choose a game';

  @override
  String get noGamesToInvite =>
      'You have no open game with a free spot. Create one first.';

  @override
  String inviteSent(String name) {
    return '$name was invited';
  }

  @override
  String get tournamentsMine => 'My tournaments';

  @override
  String get tournamentFilterDate => 'Date';

  @override
  String tournamentFilterFrom(String date) {
    return 'From $date';
  }

  @override
  String get tournamentSortAz => 'A–Z';

  @override
  String get registrationClosed => 'Registration closed';

  @override
  String get tournamentFree => 'Free';

  @override
  String get tournamentCategories => 'Categories';

  @override
  String tournamentDeadline(String when) {
    return 'Registration closes $when';
  }

  @override
  String get tournamentClosedBanner => 'Registration is closed';

  @override
  String get kindSingles => 'Singles';

  @override
  String get kindPairs => 'Pairs';

  @override
  String get genderMen => 'Men';

  @override
  String get genderWomen => 'Women';

  @override
  String get genderMixed => 'Mixed';

  @override
  String get genderOpen => 'Open';

  @override
  String waitlistCount(int count) {
    return '$count waiting';
  }

  @override
  String get joinWaitlist => 'Join waitlist';

  @override
  String get registerLabel => 'Register';

  @override
  String get confirmRegistration => 'Confirm registration';

  @override
  String registerSheetTitle(String category) {
    return 'Register: $category';
  }

  @override
  String waitlistSheetTitle(String category) {
    return 'Waitlist: $category';
  }

  @override
  String registrationFeeNote(String fee) {
    return 'Entry fee $fee, paid to the organiser.';
  }

  @override
  String get waitlistSheetNote =>
      'The category is full. If a spot frees up, you get 24 hours to claim it.';

  @override
  String get partnerTitle => 'Choose a partner';

  @override
  String get partnerTabPlayers => 'Players';

  @override
  String get partnerTabPhone => 'Phone number';

  @override
  String get partnerPhoneHint => '+998 90 123 45 67';

  @override
  String get partnerFind => 'Find';

  @override
  String get partnerNotFound => 'No player has this number';

  @override
  String get partnerPickFirst => 'Choose a partner first';

  @override
  String get sendInvite => 'Send invite';

  @override
  String get inviteNote =>
      'Your partner has 48 hours to accept, or until registration closes if that is sooner. The pair takes a spot once they accept.';

  @override
  String get statusRegistered => 'Registered';

  @override
  String get statusPendingPartner => 'Waiting for partner';

  @override
  String get statusInvited => 'Invitation';

  @override
  String get statusWaitlisted => 'On the waitlist';

  @override
  String get statusOffered => 'Spot offered';

  @override
  String get statusDeclined => 'Declined';

  @override
  String get statusExpired => 'Expired';

  @override
  String get statusRemoved => 'Removed';

  @override
  String get statusLapsed => 'Offer lapsed';

  @override
  String waitlistPlaceLabel(int place) {
    return 'Place $place in line';
  }

  @override
  String pairedWith(String name) {
    return 'With $name';
  }

  @override
  String partnerInvitedYou(String name) {
    return '$name invited you as a partner';
  }

  @override
  String get acceptLabel => 'Accept';

  @override
  String get claimLabel => 'Claim';

  @override
  String offerHeld(String left) {
    return 'Held for you · $left left';
  }

  @override
  String durationHm(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String durationMin(int minutes) {
    return '$minutes min';
  }

  @override
  String get cancelRegistration => 'Cancel registration';

  @override
  String get cancelRegistrationTitle => 'Cancel registration?';

  @override
  String get cancelRegistrationMsg =>
      'Your spot goes to the next player in line. You can register again before the deadline if there is room.';

  @override
  String get keepRegistration => 'Keep registration';

  @override
  String get myTournamentsEmpty => 'You have no tournament entries yet';

  @override
  String get errTournamentFull => 'This category just filled up';

  @override
  String get errDeadlinePassed => 'Registration has closed';

  @override
  String get errTournamentLevel =>
      'Your level, or that of your partner, is outside the range for this category';

  @override
  String get errAlreadyRegistered => 'You are already in this category';

  @override
  String get errPartnerUnavailable => 'This partner is already in the category';

  @override
  String get errNotFull => 'There is room again. Register instead';

  @override
  String get errWaitlistClosed => 'This category has no waitlist';

  @override
  String get errRateLimited => 'Too many phone lookups. Try again in an hour';

  @override
  String get notifTournamentFallback => 'the tournament';

  @override
  String notifTournamentRegistered(String title) {
    return 'You are registered for $title';
  }

  @override
  String notifTournamentPartnerInvite(String actor, String title) {
    return '$actor invited you to be their partner in $title';
  }

  @override
  String notifTournamentPartnerAccepted(String actor, String title) {
    return '$actor accepted your invitation for $title';
  }

  @override
  String notifTournamentPartnerDeclined(String actor, String title) {
    return '$actor declined your invitation for $title';
  }

  @override
  String notifTournamentPartnerCancelled(String actor, String title) {
    return '$actor cancelled your pair entry for $title';
  }

  @override
  String notifTournamentPartnerExpired(String title) {
    return 'Your partner did not answer in time for $title';
  }

  @override
  String notifTournamentSpotOffered(String title) {
    return 'A spot opened for you in $title. Claim it before it goes';
  }

  @override
  String notifTournamentDeadlineReminder(String title) {
    return 'Registration for $title closes soon and your partner has not answered';
  }

  @override
  String notifTournamentRemoved(String title) {
    return 'You were removed from $title';
  }

  @override
  String notifTournamentMoved(String title) {
    return 'You were moved to another category in $title';
  }

  @override
  String notifTournamentMovedTo(String category, String title) {
    return 'You were moved to $category in $title';
  }

  @override
  String get adminTournaments => 'Tournaments';

  @override
  String get adminTournamentsHint => 'Categories and participants';

  @override
  String get adminDashboard => 'Dashboard';

  @override
  String get adminDashboardHint => 'Users, revenue and activity';

  @override
  String get addTournament => 'Add tournament';

  @override
  String get newTournament => 'New tournament';

  @override
  String get noAdminTournaments => 'No tournaments match';

  @override
  String tournamentCounts(int categories, int entries) {
    return '$categories categories · $entries entries';
  }

  @override
  String get tournamentDetails => 'Tournament details';

  @override
  String get noVenue => 'No venue';

  @override
  String get firstDayLabel => 'First day';

  @override
  String get lastDayLabel => 'Last day';

  @override
  String get deadlineLabel => 'Registration closes';

  @override
  String get coverUrlLabel => 'Cover image link (https://…)';

  @override
  String get participantsLabel => 'Participants';

  @override
  String get addCategory => 'Add category';

  @override
  String get newCategory => 'New category';

  @override
  String get editCategory => 'Edit category';

  @override
  String get deleteCategory => 'Delete category';

  @override
  String get addCategoryFirst => 'Add at least one category';

  @override
  String get categoriesHint =>
      'Players register in a category. A tournament always keeps at least one.';

  @override
  String get capLabel => 'Places';

  @override
  String get typeLabel => 'Type';

  @override
  String get genderLabel => 'Gender';

  @override
  String get minLevelLabel => 'Lowest level';

  @override
  String get maxLevelLabel => 'Highest level';

  @override
  String get waitlistLabel => 'Waitlist';

  @override
  String get waitlistHint =>
      'When a spot frees up, the next in line gets 24 hours to claim it';

  @override
  String capBelowFilled(int filled) {
    return 'The places cannot be lower than the $filled entries already holding a spot';
  }

  @override
  String get errHasRegistrations =>
      'This category has registrations and cannot be deleted or changed to another type';

  @override
  String get errNotMarkable => 'Only registered entries can be marked paid';

  @override
  String get paidLabel => 'Paid';

  @override
  String get moveRegistration => 'Move to another category';

  @override
  String get removeEntry => 'Remove entry';

  @override
  String get addPlayer => 'Add player';

  @override
  String get addPlayerNote =>
      'Added players skip the level check, never the places limit';

  @override
  String get offerNext => 'Offer next';

  @override
  String offerNextResult(int count) {
    return 'Offers sent: $count';
  }

  @override
  String get copyCsv => 'Copy CSV';

  @override
  String get csvCopied => 'Copied to the clipboard';

  @override
  String get noEntriesYet => 'No entries yet';

  @override
  String pastEntries(int count) {
    return 'Past entries ($count)';
  }

  @override
  String get periodCustom => 'Custom';

  @override
  String get usersTitle => 'Users';

  @override
  String get usersTotal => 'Total users';

  @override
  String get usersActive => 'Active in 30 days';

  @override
  String get usersNewToday => 'New today';

  @override
  String get usersNew7 => 'New in 7 days';

  @override
  String get usersNewMonth => 'New this month';

  @override
  String get revenueTitle => 'Revenue';

  @override
  String get revenueCurrency => 'Currency';

  @override
  String get revenueVenues => 'Venues';

  @override
  String get revenueTournaments => 'Tournaments';

  @override
  String get revenueNote =>
      'Each currency has its own row. Amounts in different currencies are never added together.';

  @override
  String get noRevenue => 'No paid bookings or entry fees in this period';

  @override
  String get activityTitle => 'Activity';

  @override
  String get countBookings => 'Bookings created';

  @override
  String get countBookingsNote => 'including cancelled';

  @override
  String get countGames => 'Games created';

  @override
  String get countRegistrations => 'Tournament entries';

  @override
  String get sportsPromptTitle => 'Pick your sports';

  @override
  String get sportsPromptText =>
      'Tell us what you play and how well, so we can show you games that fit.';

  @override
  String get chooseSports => 'Choose sports';

  @override
  String get notNow => 'Not now';

  @override
  String get noSportsYet => 'You have not picked any sports yet';

  @override
  String get mySportsHint =>
      'Switch on the sports you play. Padel and tennis start with a short questionnaire.';

  @override
  String pickLevelTitle(String sport) {
    return 'Your level in $sport';
  }

  @override
  String get ratingProvisional => 'Provisional';

  @override
  String ratingWithProvisional(String rating) {
    return '$rating · provisional';
  }

  @override
  String ratedGames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rated games',
      one: '1 rated game',
    );
    return '$_temp0';
  }

  @override
  String get noRatingYet => 'No rating yet';

  @override
  String get retakeQuestionnaire => 'Retake';

  @override
  String get ratingRangeLabel => 'Rating range';

  @override
  String ratingRangeValue(String range) {
    return 'Rating $range';
  }

  @override
  String questionnaireTitle(String sport) {
    return '$sport: starting rating';
  }

  @override
  String questionnaireStep(int n, int total) {
    return 'Question $n of $total';
  }

  @override
  String questionnaireResult(String rating) {
    return 'Your starting rating: $rating';
  }

  @override
  String questionnaireResultHint(int games) {
    return 'It stays provisional for your first $games rated games and moves after every confirmed result.';
  }

  @override
  String get backLabel => 'Back';

  @override
  String get doneLabel => 'Done';

  @override
  String get adminRatingLocked => 'Set by Actra. Ask engineering to change it.';

  @override
  String get qYears => 'How long have you played?';

  @override
  String get qYearsA0 => 'Under 6 months';

  @override
  String get qYearsA1 => '6–24 months';

  @override
  String get qYearsA2 => '2–5 years';

  @override
  String get qYearsA3 => 'Over 5 years';

  @override
  String get qOften => 'How often do you play?';

  @override
  String get qOftenA0 => 'Rarely';

  @override
  String get qOftenA1 => '2–3 times a month';

  @override
  String get qOftenA2 => 'Weekly';

  @override
  String get qOftenA3 => 'Several times a week';

  @override
  String get qCompeted => 'Have you competed?';

  @override
  String get qCompetedA0 => 'Never';

  @override
  String get qCompetedA1 => 'Friendly matches with score';

  @override
  String get qCompetedA2 => 'Amateur tournaments';

  @override
  String get qCompetedA3 => 'Regular tournaments or league';

  @override
  String get qPadelWall => 'How do you play off the back wall?';

  @override
  String get qPadelWallA0 => 'I avoid it';

  @override
  String get qPadelWallA1 => 'I return slow balls';

  @override
  String get qPadelWallA2 => 'I return most balls';

  @override
  String get qPadelWallA3 => 'I attack off the wall';

  @override
  String get qPadelNet => 'At the net…';

  @override
  String get qPadelNetA0 => 'I rarely go';

  @override
  String get qPadelNetA1 => 'I volley easy balls';

  @override
  String get qPadelNetA2 => 'I hold the net and volley with direction';

  @override
  String get qPadelNetA3 => 'I finish points with volleys and smashes';

  @override
  String get qTennisServe => 'How is your serve?';

  @override
  String get qTennisServeA0 => 'I just start the point';

  @override
  String get qTennisServeA1 => 'It goes in, slowly';

  @override
  String get qTennisServeA2 => 'Steady first and second serve';

  @override
  String get qTennisServeA3 => 'I win points with it';

  @override
  String get qTennisRally => 'In a rally…';

  @override
  String get qTennisRallyA0 => 'I keep a few balls in';

  @override
  String get qTennisRallyA1 => 'I rally at medium pace';

  @override
  String get qTennisRallyA2 => 'I control direction and depth';

  @override
  String get qTennisRallyA3 => 'I change pace and spin on purpose';
}
