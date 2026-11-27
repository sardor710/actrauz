// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kazakh (`kk`).
class AppLocalizationsKk extends AppLocalizations {
  AppLocalizationsKk([String locale = 'kk']) : super(locale);

  @override
  String get appName => 'Actra';

  @override
  String get continueLabel => 'Жалғастыру';

  @override
  String get cancel => 'Бас тарту';

  @override
  String get seeAll => 'Барлығы';

  @override
  String get today => 'Бүгін';

  @override
  String get tomorrow => 'Ертең';

  @override
  String get comingSoon => 'Жақында';

  @override
  String get errGeneric => 'Бірдеңе дұрыс болмады. Қайталап көріңіз.';

  @override
  String get chooseLanguage => 'Тілді таңдаңыз';

  @override
  String get chooseCity => 'Қаланы таңдаңыз';

  @override
  String get chooseCityHint =>
      'Қаланы профильде кез келген уақытта өзгертуге болады';

  @override
  String get detectingCity => 'Қалаңыз анықталуда…';

  @override
  String cityDetected(String city) {
    return 'Анықталды: $city';
  }

  @override
  String get signInTitle => 'Кіру';

  @override
  String get signInTelegram => 'Telegram арқылы жалғастыру';

  @override
  String get demoNotice =>
      'Демо режимі: Telegram арқылы кіру келесі нұсқада қосылады. Жалғастыру үшін атыңызды енгізіңіз. Көрсетілген нысандар, ойындар мен турнирлер — үлгі деректер.';

  @override
  String get yourName => 'Атыңыз';

  @override
  String get nameRequired => 'Атыңызды енгізіңіз';

  @override
  String get telegramHint =>
      'Telegram ашылады. Онда «Start» түймесін басып, телефон нөміріңізбен бөлісіңіз — бұл сіздің Actra аккаунтыңыз болады.';

  @override
  String get telegramWaiting =>
      'Telegram-ды күтудамыз. Actra ботымен телефон нөміріңізбен бөлісіп, осында оралыңыз.';

  @override
  String get telegramOpenAgain => 'Telegram-ды қайта ашу';

  @override
  String get telegramExpired =>
      'Кіру сілтемесінің мерзімі өтті. Қайталап көріңіз.';

  @override
  String get signInFailed =>
      'Кіру мүмкін болмады. Байланысты тексеріп, қайталап көріңіз.';

  @override
  String get acceptTerms =>
      'Мен Пайдалану шарттарымен және Құпиялылық саясатымен келісемін';

  @override
  String get termsRequired => 'Жалғастыру үшін шарттармен келісіңіз';

  @override
  String get tabHome => 'Басты бет';

  @override
  String get tabVenues => 'Нысандар';

  @override
  String get tabGames => 'Ойындар';

  @override
  String get tabProfile => 'Профиль';

  @override
  String greeting(String name) {
    return 'Сәлем, $name';
  }

  @override
  String get homeGames => 'Қолжетімді ойындар';

  @override
  String get homeCourts => 'Бүгінгі бос алаңдар';

  @override
  String get homeTournaments => 'Турнирлер';

  @override
  String get noGames => 'Әзірге ашық ойындар жоқ';

  @override
  String get noCourtsToday => 'Бүгін бос уақыт қалмады';

  @override
  String get searchVenues => 'Нысандарды іздеу';

  @override
  String get allSports => 'Барлық спорт түрлері';

  @override
  String get noVenues => 'Нысандар табылмады';

  @override
  String fromPrice(String price) {
    return '$price бастап';
  }

  @override
  String slotLength(int minutes) {
    return '$minutes мин';
  }

  @override
  String get workingHours => 'Жұмыс уақыты';

  @override
  String get closed => 'Жабық';

  @override
  String get weekdays => 'Дс–Жм';

  @override
  String get saturday => 'Сб';

  @override
  String get sunday => 'Жс';

  @override
  String get amenities => 'Ыңғайлықтар';

  @override
  String get amenityParking => 'Тұрақ';

  @override
  String get amenityShowers => 'Душ';

  @override
  String get amenityLighting => 'Жарықтандыру';

  @override
  String get amenityCafe => 'Кафе';

  @override
  String get amenityRental => 'Жабдық жалға алу';

  @override
  String get courts => 'Алаңдар';

  @override
  String get indoor => 'Жабық';

  @override
  String get outdoor => 'Ашық';

  @override
  String get book => 'Брондау';

  @override
  String get phone => 'Телефон';

  @override
  String get address => 'Мекенжай';

  @override
  String get about => 'Нысан туралы';

  @override
  String get bookingTitle => 'Уақытты таңдаңыз';

  @override
  String get closedThatDay => 'Алаң бұл күні жабық';

  @override
  String get selectHint => 'Бір слотты немесе қатар тұрған бірнешеуін таңдаңыз';

  @override
  String slotsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count слот',
      one: '$count слот',
    );
    return '$_temp0';
  }

  @override
  String get total => 'Барлығы';

  @override
  String get summaryTitle => 'Брондау қорытындысы';

  @override
  String heldFor(String time) {
    return 'Слоттар сіз үшін ұсталады: $time';
  }

  @override
  String get holdExpiredMsg => 'Ұстау уақыты аяқталды. Уақытты қайта таңдаңыз.';

  @override
  String get paymentMethod => 'Төлем тәсілі';

  @override
  String get payAtVenue => 'Нысанда төлеу';

  @override
  String get payAtVenueHint => 'Нысанда қолма-қол немесе картамен';

  @override
  String get playersCount => 'Ойыншылар саны';

  @override
  String get noteLabel => 'Ескертпе (міндетті емес)';

  @override
  String get confirmBooking => 'Брондауды растау';

  @override
  String get bookingConfirmed => 'Брондау расталды';

  @override
  String get dateLabel => 'Күні';

  @override
  String get timeLabel => 'Уақыты';

  @override
  String get courtLabel => 'Алаң';

  @override
  String get errSlotTaken =>
      'Бұл уақытты жаңа ғана біреу алды. Басқасын таңдаңыз.';

  @override
  String get errNotContiguous => 'Слоттар қатар тұруы керек';

  @override
  String errTooManyBookings(int count) {
    return 'Сізде $count алдағы брондау бар';
  }

  @override
  String errTooFarAhead(int days) {
    return 'Брондау $days күн бұрын ашылады';
  }

  @override
  String get errInPast => 'Бұл уақыт өтіп кетті';

  @override
  String get myBookings => 'Менің брондауларым';

  @override
  String get noBookings => 'Сізде әзірге брондау жоқ';

  @override
  String get statusConfirmed => 'Расталды';

  @override
  String get statusCancelled => 'Бас тартылды';

  @override
  String get statusCompleted => 'Аяқталды';

  @override
  String get cancelBooking => 'Брондаудан бас тарту';

  @override
  String get cancelConfirmTitle => 'Брондаудан бас тартасыз ба?';

  @override
  String get cancelFreeMsg => 'Бас тарту тегін.';

  @override
  String cancelLateMsg(int hours) {
    return 'Басталуына $hours сағаттан аз қалды. Бұл кеш бас тарту болып саналады және сенімділігіңізді төмендетеді.';
  }

  @override
  String get keepBooking => 'Брондауды қалдыру';

  @override
  String get bookingCancelled => 'Брондаудан бас тартылды';

  @override
  String get lateCancellation => 'Кеш бас тарту';

  @override
  String spotsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count орын қалды',
      one: '$count орын қалды',
      zero: 'Орын жоқ',
    );
    return '$_temp0';
  }

  @override
  String levelRange(int min, int max) {
    return 'Деңгей $min–$max';
  }

  @override
  String perPlayer(String price) {
    return '≈ $price бір ойыншыға';
  }

  @override
  String get host => 'Ұйымдастырушы';

  @override
  String get players => 'Ойыншылар';

  @override
  String get joinGame => 'Қосылу';

  @override
  String get leaveGame => 'Ойыннан шығу';

  @override
  String get errGameFull => 'Бұл ойында орын қалмады';

  @override
  String get errLevel =>
      'Сіздің деңгейіңіз бұл ойынның аралығына сәйкес келмейді';

  @override
  String get you => 'Сіз';

  @override
  String get entryFee => 'Қатысу жарнасы';

  @override
  String filledOf(int filled, int total) {
    return '$filled / $total толды';
  }

  @override
  String get language => 'Тіл';

  @override
  String get city => 'Қала';

  @override
  String get signOut => 'Шығу';

  @override
  String get deleteAccount => 'Аккаунтты жою';

  @override
  String get deleteAccountTitle => 'Аккаунтыңызды жоясыз ба?';

  @override
  String get deleteAccountBody =>
      'Алдағы брондауларыңыздан және турнирлерге өтінімдеріңізден бас тартылады, ал сіз ойындарыңыздан шығасыз. Атыңыз бен телефон нөміріңіз жойылады. Бұл әрекетті қайтару мүмкін емес.';

  @override
  String get deleteAccountConfirm => 'Жою';

  @override
  String get deleteAccountAdmin =>
      'Әкімші аккаунтын жоюға болмайды. Алдымен басқа әкімшіден әкімші рөлін алып тастауын сұраңыз.';

  @override
  String get deletedPlayer => 'Жойылған ойыншы';

  @override
  String get currencyUzs => 'сум';

  @override
  String get currencyKzt => '₸';

  @override
  String get searchHint => 'Нысандар мен спорт түрлерін іздеу';

  @override
  String get gamesBySports => 'Спорт түрі бойынша ойындар';

  @override
  String get venuesNearYou => 'Жақын маңдағы нысандар';

  @override
  String get tabTournaments => 'Турнирлер';

  @override
  String get tabSocial => 'Қауымдастық';

  @override
  String get allDays => 'Барлығы';

  @override
  String get filterSport => 'Спорт түрі';

  @override
  String get myLevel => 'Менің деңгейім';

  @override
  String going(int count, int spots) {
    return '$count/$spots қатысады';
  }

  @override
  String gameTitle(String host, String sport) {
    return '$host · $sport';
  }

  @override
  String get createGame => 'Ойын құру';

  @override
  String get gamesPromoTitle => 'Ойыншы жетіспей ме?';

  @override
  String get gamesPromoText =>
      'Деңгейіңізге сай ойынға қосылыңыз немесе өз алаңыңызды толтырыңыз';

  @override
  String get bookable => 'Брондауға болады';

  @override
  String get favourites => 'Таңдаулылар';

  @override
  String get sortPrice => 'Алдымен арзандары';

  @override
  String get priceStartingFrom => 'Бастапқы баға';

  @override
  String get registrationOpen => 'Тіркеу ашық';

  @override
  String get tournamentFull => 'Толды';

  @override
  String get noTournaments => 'Турнирлер әзірге жарияланған жоқ';

  @override
  String get tournamentsPromoTitle => 'Кубок үшін ойнаңыз';

  @override
  String get tournamentsPromoText =>
      'Әр деңгейге арналған жеке және жұптық турнирлер';

  @override
  String get discoverTeams => 'Командаларды табу';

  @override
  String get noTeams => 'Бұл қалада әзірге командалар жоқ';

  @override
  String members(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count қатысушы',
      one: '$count қатысушы',
    );
    return '$_temp0';
  }

  @override
  String upcomingGames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'жақында $count ойын',
      one: 'жақында $count ойын',
    );
    return '$_temp0';
  }

  @override
  String get playersNearYou => 'Жақын маңдағы ойыншылар';

  @override
  String level(int level) {
    return '$level-деңгей';
  }

  @override
  String get inviteTitle => 'Достарыңызды шақырыңыз';

  @override
  String get inviteText =>
      'Достарыңызды Actra-ға шақырып, ойындарыңызды тезірек толтырыңыз.';

  @override
  String get inviteCta => 'Достарды шақыру';

  @override
  String get statBookings => 'Брондаулар';

  @override
  String get statGames => 'Ойындар';

  @override
  String get statLate => 'Кеш бас тартулар';

  @override
  String get mySports => 'Менің спорт түрлерім';

  @override
  String get morning => 'Таңертең';

  @override
  String get afternoon => 'Күндіз';

  @override
  String get evening => 'Кешке';

  @override
  String get everyDay => 'Күн сайын';

  @override
  String get gamesPromoCta => 'Алаңды брондау';

  @override
  String get myVenues => 'Менің нысандарым';

  @override
  String get ownerCalendar => 'Брондау күнтізбесі';

  @override
  String get noVenuesAssigned => 'Сізге әзірге нысан бекітілмеген';

  @override
  String get prevWeek => 'Өткен апта';

  @override
  String get nextWeek => 'Келесі апта';

  @override
  String get slotFree => 'Бос';

  @override
  String get slotBooked => 'Брондалған';

  @override
  String get slotBlocked => 'Жабылған';

  @override
  String get closedThatWeek => 'Алаң осы аптада жабық';

  @override
  String get newBooking => 'Жаңа брондау';

  @override
  String get blockTime => 'Уақытты жабу';

  @override
  String get customerName => 'Клиент аты';

  @override
  String get customerNameRequired => 'Клиенттің атын енгізіңіз';

  @override
  String get customerPhone => 'Телефон нөмірі (міндетті емес)';

  @override
  String get slotsCountLabel => 'Слот саны';

  @override
  String get payCash => 'Қолма-қол';

  @override
  String get payCard => 'Карта';

  @override
  String get payTransfer => 'Аударым';

  @override
  String get saveBooking => 'Брондауды сақтау';

  @override
  String get blockReason => 'Себебі (міндетті емес)';

  @override
  String get blockConfirm => 'Осы уақытты жабу';

  @override
  String get unblock => 'Бұл уақытты қайта ашу';

  @override
  String get customerLabel => 'Клиент';

  @override
  String get sourceLabel => 'Дереккөз';

  @override
  String get statusLabel => 'Күйі';

  @override
  String get reasonLabel => 'Себебі';

  @override
  String get sourceApp => 'Қосымшада брондалған';

  @override
  String get sourceWalkIn => 'Келген немесе телефон арқылы';

  @override
  String get sourceBlock => 'Нысан жапқан';

  @override
  String get markPaid => 'Төленді деп белгілеу';

  @override
  String get markNoShow => 'Келмеді деп белгілеу';

  @override
  String get statusPaid => 'Төленді';

  @override
  String get statusNoShow => 'Келмеді';

  @override
  String get statusUnverified => 'Расталмаған';

  @override
  String get statusCancelledByVenue => 'Нысан бас тартты';

  @override
  String get markAfterStart =>
      'Төленді және келмеді деп брондау басталғаннан кейін белгілеуге болады';

  @override
  String get cancelByVenueMsg =>
      'Уақыт бірден босайды. Қосымшада брондаған ойыншы нысанның бас тартқанын көреді.';

  @override
  String get errNotAllowed => 'Сіз бұл нысанды басқармайсыз';

  @override
  String get bookingSaved => 'Брондау сақталды';

  @override
  String get ownerSettings => 'Уақыт пен бағалар';

  @override
  String get ownerDashboard => 'Басқару тақтасы';

  @override
  String get venueHours => 'Нысанның жұмыс уақыты';

  @override
  String get courtHours => 'Алаң уақыты';

  @override
  String get sameAsVenue => 'Нысандағыдай';

  @override
  String get openLabel => 'Ашылуы';

  @override
  String get editLabel => 'Өңдеу';

  @override
  String get saveLabel => 'Сақтау';

  @override
  String get savedMsg => 'Сақталды';

  @override
  String get pricesTitle => 'Бағалар';

  @override
  String get hoursTitle => 'Уақыт';

  @override
  String get slotLengthLabel => 'Слот ұзақтығы';

  @override
  String get basePrice => 'Слоттың негізгі бағасы';

  @override
  String get priceRules => 'Баға ережелері';

  @override
  String get addRule => 'Ереже қосу';

  @override
  String get removeRule => 'Ережені жою';

  @override
  String get ruleFrom => 'Басталуы';

  @override
  String get ruleTo => 'Аяқталуы';

  @override
  String get rulePrice => 'Слот бағасы';

  @override
  String get noRules => 'Ережелер жоқ: әр слот негізгі баға бойынша';

  @override
  String rulesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count баға ережесі',
      one: '$count баға ережесі',
      zero: 'Баға ережелері жоқ',
    );
    return '$_temp0';
  }

  @override
  String get errInvalidHours =>
      'Ашылу уақыты жабылу уақытынан ерте болуы керек';

  @override
  String get errRulesOverlap => 'Екі ереже бір күн мен уақытты қамтиды';

  @override
  String get errInvalidArgument => 'Мәндерді тексеріп, қайталап көріңіз';

  @override
  String get errPickWeekday => 'Кемінде бір күнді таңдаңыз';

  @override
  String get errPrice => 'Бағаны енгізіңіз';

  @override
  String get period7 => 'Соңғы 7 күн';

  @override
  String get periodMonth => 'Осы ай';

  @override
  String get allCourts => 'Барлық алаңдар';

  @override
  String metricSplit(int app, int walkIn) {
    return 'Қолданба $app · келгендер $walkIn';
  }

  @override
  String get metricRevenue => 'Төленген түсім';

  @override
  String get metricUnconfirmed => 'Расталмаған түсім';

  @override
  String get metricDailyAvg => 'Күніне брондау';

  @override
  String get metricUtilisation => 'Жүктеме';

  @override
  String get metricNoShows => 'Келмегендер';

  @override
  String get peakHours => 'Ең жоғары жүктеме сағаттары';

  @override
  String get noDataPeriod => 'Бұл кезеңде брондаулар жоқ';

  @override
  String get adminTitle => 'Әкімші';

  @override
  String get adminOnly => 'Бұл бетті тек Actra әкімшілері аша алады';

  @override
  String get adminSports => 'Спорт түрлері';

  @override
  String get adminBanners => 'Баннерлер';

  @override
  String get adminAudit => 'Әрекеттер журналы';

  @override
  String get adminAuditHint => 'Кім, не және қашан өзгертті';

  @override
  String venuesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count нысан',
      one: '$count нысан',
    );
    return '$_temp0';
  }

  @override
  String sportsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count спорт түрі',
      one: '$count спорт түрі',
    );
    return '$_temp0';
  }

  @override
  String bannersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count баннер',
      one: '$count баннер',
    );
    return '$_temp0';
  }

  @override
  String courtsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count алаң',
      one: '$count алаң',
    );
    return '$_temp0';
  }

  @override
  String ownersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ие',
      one: '$count ие',
      zero: 'Иелер жоқ',
    );
    return '$_temp0';
  }

  @override
  String playersN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ойыншы',
      one: '$count ойыншы',
    );
    return '$_temp0';
  }

  @override
  String get inactive => 'Белсенді емес';

  @override
  String get activeLabel => 'Белсенді';

  @override
  String get activeHint => 'Ойыншыларға көрінеді';

  @override
  String get addVenue => 'Нысан қосу';

  @override
  String get newVenue => 'Жаңа нысан';

  @override
  String get venueDetails => 'Мәліметтер';

  @override
  String get nameLabel => 'Атауы';

  @override
  String get descriptionLabel => 'Сипаттамасы';

  @override
  String get districtLabel => 'Аудан';

  @override
  String get nameRequiredAny => 'Кемінде бір тілде толтырыңыз';

  @override
  String get saveVenueFirst =>
      'Алаңдар мен иелерді қосу үшін алдымен нысанды сақтаңыз';

  @override
  String get addCourt => 'Алаң қосу';

  @override
  String get newCourt => 'Жаңа алаң';

  @override
  String get editCourt => 'Алаңды өңдеу';

  @override
  String get noCourts => 'Алаңдар әзірге жоқ';

  @override
  String get courtActions => 'Алаңмен әрекеттер';

  @override
  String get duplicateLabel => 'Көшірме жасау';

  @override
  String get deleteLabel => 'Жою';

  @override
  String get deleteVenue => 'Нысанды жою';

  @override
  String deleteConfirmTitle(String name) {
    return '“$name” жойылсын ба?';
  }

  @override
  String get deleteConfirmMsg => 'Мұны қайтару мүмкін емес.';

  @override
  String get errHasBookings =>
      'Брондаулар бар, сондықтан жою мүмкін емес. Ойыншылардан жасыру үшін белсенділіктен шығарыңыз.';

  @override
  String get deactivateInstead => 'Орнына белсенділіктен шығару';

  @override
  String get errAlreadyExists => 'Бұл ID бос емес';

  @override
  String get errNotFound => 'Табылмады. Жаңартып, қайталап көріңіз.';

  @override
  String get ownersTitle => 'Иелер';

  @override
  String get assignOwner => 'Ие тағайындау';

  @override
  String get removeOwner => 'Иені алып тастау';

  @override
  String get noOwners => 'Иелер тағайындалмаған';

  @override
  String get searchUsers => 'Аты немесе телефоны';

  @override
  String get searchUsersMin => 'Кемінде 2 таңба енгізіңіз';

  @override
  String get noUsersFound => 'Ешкім табылмады';

  @override
  String get addSport => 'Спорт түрін қосу';

  @override
  String get newSport => 'Жаңа спорт түрі';

  @override
  String get editSport => 'Спорт түрін өңдеу';

  @override
  String get sportIdLabel => 'ID';

  @override
  String get sportIdHint =>
      'Кіші латын әріптері, цифрлар және _, мысалы squash. Кейін өзгертуге болмайды.';

  @override
  String get errSportId =>
      '2–30 таңба: кіші латын әріптері, цифрлар немесе _, әріптен басталуы керек';

  @override
  String get iconLabel => 'Белгіше';

  @override
  String get sportTypeLabel => 'Түрі';

  @override
  String get placeOnly => 'Тек орын';

  @override
  String get ratingLabel => 'Рейтинг';

  @override
  String get ratingSimple => '1–5 деңгей';

  @override
  String get ratingCompetitive => 'Рейтинг 1.0–7.0';

  @override
  String get defaultPlayers => 'Ойыншылар саны (әдепкі)';

  @override
  String get sortOrderLabel => 'Тізімдегі орны';

  @override
  String get addBanner => 'Баннер қосу';

  @override
  String get newBanner => 'Жаңа баннер';

  @override
  String get editBanner => 'Баннерді өңдеу';

  @override
  String get bannerTitle => 'Тақырып';

  @override
  String get bannerSubtitle => 'Қосымша тақырып';

  @override
  String get linkLabel => 'Сілтеме';

  @override
  String get errUrl => 'Сілтеме https:// деп басталуы керек';

  @override
  String get allCities => 'Барлық қалалар';

  @override
  String get noBanners => 'Баннерлер әзірге жоқ';

  @override
  String get auditEmpty => 'Өзгерістер әзірге тіркелмеген';

  @override
  String get loadMore => 'Тағы жүктеу';

  @override
  String get auditBefore => 'Бұрын';

  @override
  String get auditAfter => 'Кейін';

  @override
  String get auditSystem => 'Жүйе';

  @override
  String get auditCreateVenue => 'Нысан құрылды';

  @override
  String get auditUpdateVenue => 'Нысан жаңартылды';

  @override
  String get auditDeleteVenue => 'Нысан жойылды';

  @override
  String get auditCreateCourt => 'Алаң құрылды';

  @override
  String get auditUpdateCourt => 'Алаң жаңартылды';

  @override
  String get auditDuplicateCourt => 'Алаңның көшірмесі жасалды';

  @override
  String get auditDeleteCourt => 'Алаң жойылды';

  @override
  String get auditAssignOwner => 'Ие тағайындалды';

  @override
  String get auditRemoveOwner => 'Ие алып тасталды';

  @override
  String get auditCreateSport => 'Спорт түрі құрылды';

  @override
  String get auditUpdateSport => 'Спорт түрі жаңартылды';

  @override
  String get auditCreateBanner => 'Баннер құрылды';

  @override
  String get auditUpdateBanner => 'Баннер жаңартылды';

  @override
  String get auditDeleteBanner => 'Баннер жойылды';

  @override
  String get auditVenueHours => 'Нысанның жұмыс уақыты өзгертілді';

  @override
  String get auditCourtHours => 'Алаң уақыты өзгертілді';

  @override
  String get auditCourtPricing => 'Алаң бағалары өзгертілді';

  @override
  String get auditWalkIn => 'Келген клиенттің брондауы қосылды';

  @override
  String get auditBlock => 'Уақыт жабылды';

  @override
  String get auditMarkBooking => 'Брондау белгіленді';

  @override
  String get auditOwnerAccountDeleted => 'Ие аккаунтын жойды';

  @override
  String get auditHideSample => 'Үлгі деректер жасырылды';

  @override
  String get entityVenue => 'Нысан';

  @override
  String get entityBanner => 'Баннер';

  @override
  String get entityBooking => 'Брондау';

  @override
  String get entityOwner => 'Нысан иесі';

  @override
  String get notificationsTitle => 'Хабарландырулар';

  @override
  String get markAllRead => 'Барлығын оқылған деп белгілеу';

  @override
  String get notificationSettings => 'Хабарландыру параметрлері';

  @override
  String get noNotifications => 'Хабарландырулар әзірге жоқ';

  @override
  String get notificationsAndPrivacy => 'Хабарландырулар және құпиялылық';

  @override
  String get notificationsMuteHint =>
      'Қандай хабарлар алатыныңызды таңдаңыз. Топты өшірсеңіз, оның хабарландырулары келмейді.';

  @override
  String get notifCategoryBookings => 'Брондаулар';

  @override
  String get notifCategoryVenue => 'Менің нысандарым';

  @override
  String get notifCategoryGames => 'Ойындар';

  @override
  String get notifCategoryRequests => 'Ойын өтінімдері';

  @override
  String get notifCategoryInvites => 'Шақырулар';

  @override
  String get notifCategoryTournaments => 'Турнирлер';

  @override
  String get privacyTitle => 'Құпиялылық';

  @override
  String get hideFromSearch => 'Мені ойыншылар іздеуінен жасыру';

  @override
  String get hideFromSearchHint =>
      'Басқа ойыншылар шақыратын адамдарды іздегенде сізді таппайды.';

  @override
  String get notifSomeone => 'Біреу';

  @override
  String get notifVenueFallback => 'нысан';

  @override
  String get notifCourtFallback => 'алаң';

  @override
  String notifBookingConfirmed(String venue) {
    return '$venue нысанындағы брондауыңыз расталды';
  }

  @override
  String notifBookingCancelledByVenue(String venue) {
    return '$venue брондауыңыздан бас тартты';
  }

  @override
  String notifBookingReminder(String venue) {
    return 'Еске салу: $venue нысанындағы брондауыңыз жақындап қалды';
  }

  @override
  String notifVenueNewBooking(String actor, String court) {
    return '$actor $court алаңын брондады';
  }

  @override
  String notifVenueBookingCancelled(String actor, String court) {
    return '$actor $court брондауынан бас тартты';
  }

  @override
  String notifGameJoined(String actor) {
    return '$actor ойыныңызға қосылды';
  }

  @override
  String notifGameLeft(String actor) {
    return '$actor ойыныңыздан шықты';
  }

  @override
  String notifJoinRequest(String actor) {
    return '$actor ойыныңызға қосылуды сұрады';
  }

  @override
  String get notifJoinApproved =>
      'Сіз ойындасыз! Ұйымдастырушы сұрауыңызды мақұлдады';

  @override
  String get notifJoinDeclined => 'Ұйымдастырушы сұрауыңызды қабылдамады';

  @override
  String get notifGameFull => 'Ойыныңыз толды';

  @override
  String get notifGameChanged => 'Ұйымдастырушы ойын мәліметтерін өзгертті';

  @override
  String get notifGameCancelled => 'Ойын болдырылмады';

  @override
  String get notifGameRemoved => 'Ұйымдастырушы сізді ойыннан шығарды';

  @override
  String get notifGameReminder => 'Еске салу: ойыныңыз жақында басталады';

  @override
  String notifGameInvite(String actor) {
    return '$actor сізді ойынға шақырды';
  }

  @override
  String notifRequestInterest(String actor) {
    return '$actor сіздің ойын өтініміңізге қатысуға дайын';
  }

  @override
  String get notifRequestConvertedIn =>
      'Ойын өтініміңіз ойынға айналды, сіз қатысасыз';

  @override
  String get notifRequestConvertedFull =>
      'Ойын өтініміңіз ойынға айналды, бірақ сізге дейін орындар толып қалды';

  @override
  String get notifRequestExpired => 'Ойын өтінімінің мерзімі аяқталды';

  @override
  String get notifUnknown => 'Жаңа хабарландыру';

  @override
  String get reliabilityNew => 'Жаңа ойыншы';

  @override
  String get reliabilityReliable => 'Сенімді';

  @override
  String get reliabilityLimited => 'Шектелген';

  @override
  String get reliabilityBlocked => 'Бұғатталған';

  @override
  String reliabilityScore(int score) {
    return 'Сенімділік көрсеткіші: 100-ден $score';
  }

  @override
  String get reliabilityLimitedHint =>
      'Бір уақытта тек бір алдағы брондауды ұстай аласыз. Қалпына келу үшін келіп ойнаңыз.';

  @override
  String get reliabilityBlockedHint =>
      'Өткізіп алған ойындарыңыздан 90 күн өткенше брондауға, ойынға қосылуға және жариялауға болмайды.';

  @override
  String get gameSportLabel => 'Спорт түрі';

  @override
  String get pickSportHint => 'Ойынды орнату үшін спорт түрін таңдаңыз';

  @override
  String get gameBookingLabel => 'Сіздің алаң брондауыңыз';

  @override
  String get noBookingForSport =>
      'Бұл спорт түрі бойынша алдағы расталған брондауыңыз жоқ. Алдымен алаңды брондап, сосын оған ойын құрыңыз.';

  @override
  String get bookACourt => 'Алаңды брондау';

  @override
  String get gamePlaceLabel => 'Қайда';

  @override
  String get placeVenue => 'Нысан';

  @override
  String get placeMeetingPoint => 'Кездесу орны';

  @override
  String get chooseVenue => 'Нысанды таңдаңыз';

  @override
  String get meetingPointHint => 'Мысалы: саябақтың басты қақпасы';

  @override
  String get meetingPointRequired => 'Кездесу орнын енгізіңіз';

  @override
  String get venueRequired => 'Нысанды таңдаңыз';

  @override
  String get gameWhenLabel => 'Қашан';

  @override
  String get gameStartTime => 'Басталуы';

  @override
  String get gameDuration => 'Ұзақтығы';

  @override
  String minutesShort(int count) {
    return '$count мин';
  }

  @override
  String get distanceLabel => 'Қашықтық, км (міндетті емес)';

  @override
  String get paceLabel => 'Қарқын (міндетті емес)';

  @override
  String get paceHint => 'Мысалы, 6:00 мин/км';

  @override
  String distanceValue(String km) {
    return '$km км';
  }

  @override
  String paceValue(String pace) {
    return 'Қарқын $pace';
  }

  @override
  String get spotsLabel => 'Орын саны, ұйымдастырушымен бірге';

  @override
  String get fewerSpots => 'Орынды азайту';

  @override
  String get moreSpots => 'Орынды көбейту';

  @override
  String get levelRangeLabel => 'Деңгей аралығы';

  @override
  String get visibilityLabel => 'Кімге көрінеді';

  @override
  String get visibilityPublic => 'Ашық';

  @override
  String get visibilityInviteOnly => 'Тек шақыру бойынша';

  @override
  String get askToJoin => 'Қосылуды сұрау';

  @override
  String get requested => 'Сұрау жіберілді';

  @override
  String get withdrawRequest => 'Сұрауды қайтарып алу';

  @override
  String get invitedToGame => 'Сіз бұл ойынға шақырылдыңыз';

  @override
  String get invitedPill => 'Шақырылды';

  @override
  String get acceptInvite => 'Қабылдау';

  @override
  String get declineLabel => 'Қабылдамау';

  @override
  String get approveLabel => 'Мақұлдау';

  @override
  String get requestsTitle => 'Сұраулар';

  @override
  String get hostTools => 'Ұйымдастырушы құралдары';

  @override
  String get editGame => 'Ойынды өңдеу';

  @override
  String get cancelGame => 'Ойынды болдырмау';

  @override
  String get cancelGameTitle => 'Ойынды болдырмайсыз ба?';

  @override
  String get cancelGameMsg => 'Ойыншыларға хабарланады.';

  @override
  String get alsoCancelBooking => 'Алаң брондауынан да бас тарту';

  @override
  String get alsoCancelBookingHint =>
      'Алаңды басқаларға босатады. Кеш бас тарту ережелері сақталады.';

  @override
  String get keepGame => 'Ойынды қалдыру';

  @override
  String get gameCancelled => 'Ойын болдырылмады';

  @override
  String get gameCancelledBanner => 'Бұл ойын болдырылмады';

  @override
  String get removePlayer => 'Ойыншыны шығару';

  @override
  String removePlayerTitle(String name) {
    return '$name шығарылсын ба?';
  }

  @override
  String get removePlayerMsg => 'Оған шығарылғаны туралы хабарланады.';

  @override
  String get removeLabel => 'Шығару';

  @override
  String get createGameFromBooking => 'Осы брондаудан ойын құру';

  @override
  String get errSpotsBelowPlayers =>
      'Орын саны ойындағы ойыншылар санынан аз болмауы керек';

  @override
  String get errAlreadyJoined => 'Сіз бұл ойындасыз';

  @override
  String get errNotParticipant => 'Сіз бұл ойында жоқсыз';

  @override
  String get errHostCannotLeave =>
      'Ұйымдастырушы шыға алмайды. Оның орнына ойынды болдырмаңыз.';

  @override
  String get errAlreadyRequested => 'Сіз бұл ойынға қосылуды сұрап қойғансыз';

  @override
  String get errBookingNotUsable =>
      'Осы спорт түрі бойынша әлі басталмаған өз расталған брондауыңызды таңдаңыз';

  @override
  String get errGameExists => 'Бұл брондауда ойын бар';

  @override
  String get errForbidden => 'Бұл ойында мұны істей алмайсыз';

  @override
  String get errNotCancellable =>
      'Ойын басталып кетті, сондықтан оны болдырмау мүмкін емес';

  @override
  String get errScoreClosed => 'Бұл ойынға енді есеп енгізу мүмкін емес';

  @override
  String get errUnavailable =>
      'Серверге қосылу мүмкін емес. Байланысты тексеріңіз.';

  @override
  String get gamesTabRequests => 'Өтінімдер';

  @override
  String get homeRequests => 'Ойын өтінімдері';

  @override
  String interestedOf(int count, int total) {
    return '$total ішінен $count қызығушылық білдірді';
  }

  @override
  String requestTitle(String host, String sport) {
    return '$host $sport ойнағысы келеді';
  }

  @override
  String needsPlayers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Тағы $count ойыншы керек',
      one: 'Тағы $count ойыншы керек',
    );
    return '$_temp0';
  }

  @override
  String get noRequests =>
      'Ойын өтінімдері әзірге жоқ. Ойыншыларды табу үшін біреуін жариялаңыз.';

  @override
  String get postRequest => 'Өтінім жариялау';

  @override
  String get createRequestTitle => 'Ойын өтінімі';

  @override
  String get requestPlayersNeeded => 'Қажетті ойыншылар';

  @override
  String get requestWindowLabel => 'Қашан ойнай аласыз?';

  @override
  String get requestFrom => 'Бастап';

  @override
  String get requestTo => 'Дейін';

  @override
  String get areaLabel => 'Аумақ (міндетті емес)';

  @override
  String get areaHint => 'Мысалы, Юнусабад';

  @override
  String get venueOptional => 'Нысан (міндетті емес)';

  @override
  String get anyVenue => 'Кез келген нысан';

  @override
  String get postRequestCta => 'Өтінімді жариялау';

  @override
  String get imIn => 'Мен қатысамын';

  @override
  String get leaveRequest => 'Шығу';

  @override
  String get interestedPlayers => 'Қызығушылар';

  @override
  String get noInterestedYet => 'Әзірге ешкім қатысатынын айтқан жоқ';

  @override
  String get makeItAGame => 'Ойынға айналдыру';

  @override
  String get convertHint =>
      'Қатысатын ойыншылар батырманы басу ретімен, орын жеткенше қосылады.';

  @override
  String get gameEndTime => 'Аяқталуы';

  @override
  String get cancelRequestLabel => 'Өтінімнен бас тарту';

  @override
  String get cancelRequestTitle => 'Өтінімнен бас тартасыз ба?';

  @override
  String get cancelRequestMsg => 'Қатысамын деген ойыншылар оны енді көрмейді.';

  @override
  String get keepRequest => 'Өтінімді қалдыру';

  @override
  String get requestCancelledMsg => 'Өтінімнен бас тартылды';

  @override
  String get removeInterestedMsg => 'Олар тізімнен алынады.';

  @override
  String get requestConvertedBanner => 'Бұл өтінім ойынға айналды';

  @override
  String get openGameCta => 'Ойынды ашу';

  @override
  String get requestClosedBanner => 'Бұл өтінім жабылған';

  @override
  String get findPlayers => 'Ойыншыларды іздеу';

  @override
  String get searchPlayersHint => 'Аты бойынша іздеу';

  @override
  String get noPlayersFound => 'Ойыншылар табылмады';

  @override
  String gamesPlayed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ойын ойналды',
      one: '$count ойын ойналды',
    );
    return '$_temp0';
  }

  @override
  String get playerProfileTitle => 'Ойыншы профилі';

  @override
  String get profileLevels => 'Деңгейлер';

  @override
  String get noLevelsYet => 'Деңгейлер әзірге қойылмаған';

  @override
  String get inviteToGame => 'Ойынға шақыру';

  @override
  String get chooseGameToInvite => 'Ойынды таңдаңыз';

  @override
  String get noGamesToInvite =>
      'Бос орны бар ашық ойыныңыз жоқ. Алдымен біреуін құрыңыз.';

  @override
  String inviteSent(String name) {
    return '$name шақырылды';
  }

  @override
  String get tournamentsMine => 'Менің турнирлерім';

  @override
  String get tournamentFilterDate => 'Күні';

  @override
  String tournamentFilterFrom(String date) {
    return '$date бастап';
  }

  @override
  String get tournamentSortAz => 'А–Я';

  @override
  String get registrationClosed => 'Тіркеу жабылды';

  @override
  String get tournamentFree => 'Тегін';

  @override
  String get tournamentCategories => 'Санаттар';

  @override
  String tournamentDeadline(String when) {
    return 'Тіркеу $when жабылады';
  }

  @override
  String get tournamentClosedBanner => 'Тіркеу жабылды';

  @override
  String get kindSingles => 'Жеке';

  @override
  String get kindPairs => 'Жұптық';

  @override
  String get genderMen => 'Ерлер';

  @override
  String get genderWomen => 'Әйелдер';

  @override
  String get genderMixed => 'Аралас';

  @override
  String get genderOpen => 'Ашық';

  @override
  String waitlistCount(int count) {
    return '$count күтуде';
  }

  @override
  String get joinWaitlist => 'Күту тізіміне тұру';

  @override
  String get registerLabel => 'Тіркелу';

  @override
  String get confirmRegistration => 'Тіркелуді растау';

  @override
  String registerSheetTitle(String category) {
    return 'Тіркелу: $category';
  }

  @override
  String waitlistSheetTitle(String category) {
    return 'Күту тізімі: $category';
  }

  @override
  String registrationFeeNote(String fee) {
    return 'Қатысу жарнасы $fee, ұйымдастырушыға төленеді.';
  }

  @override
  String get waitlistSheetNote =>
      'Санат толды. Орын босаса, оны алуға 24 сағатыңыз болады.';

  @override
  String get partnerTitle => 'Әріптес таңдаңыз';

  @override
  String get partnerTabPlayers => 'Ойыншылар';

  @override
  String get partnerTabPhone => 'Телефон нөмірі';

  @override
  String get partnerPhoneHint => '+998 90 123 45 67';

  @override
  String get partnerFind => 'Табу';

  @override
  String get partnerNotFound => 'Бұл нөмірмен ойыншы жоқ';

  @override
  String get partnerPickFirst => 'Алдымен әріптес таңдаңыз';

  @override
  String get sendInvite => 'Шақыру жіберу';

  @override
  String get inviteNote =>
      'Әріптесіңізде қабылдауға 48 сағат бар, немесе тіркеу ертерек жабылса, сол уақытқа дейін. Жұп әріптес қабылдағаннан кейін орын алады.';

  @override
  String get statusRegistered => 'Тіркелді';

  @override
  String get statusPendingPartner => 'Әріптес күтілуде';

  @override
  String get statusInvited => 'Шақыру';

  @override
  String get statusWaitlisted => 'Күту тізімінде';

  @override
  String get statusOffered => 'Орын ұсынылды';

  @override
  String get statusDeclined => 'Қабылданбады';

  @override
  String get statusExpired => 'Мерзімі өтті';

  @override
  String get statusRemoved => 'Шығарылды';

  @override
  String get statusLapsed => 'Ұсыныс аяқталды';

  @override
  String waitlistPlaceLabel(int place) {
    return 'Кезекте $place-орын';
  }

  @override
  String pairedWith(String name) {
    return '$name әріптесімен';
  }

  @override
  String partnerInvitedYou(String name) {
    return '$name сізді әріптес болуға шақырды';
  }

  @override
  String get acceptLabel => 'Қабылдау';

  @override
  String get claimLabel => 'Алу';

  @override
  String offerHeld(String left) {
    return 'Сізге ұсталды · $left қалды';
  }

  @override
  String durationHm(int hours, int minutes) {
    return '$hours сағ $minutes мин';
  }

  @override
  String durationMin(int minutes) {
    return '$minutes мин';
  }

  @override
  String get cancelRegistration => 'Тіркелуден бас тарту';

  @override
  String get cancelRegistrationTitle => 'Тіркелуден бас тартасыз ба?';

  @override
  String get cancelRegistrationMsg =>
      'Орныңыз кезектегі келесі ойыншыға беріледі. Орын болса, мерзімге дейін қайта тіркеле аласыз.';

  @override
  String get keepRegistration => 'Тіркелуді қалдыру';

  @override
  String get myTournamentsEmpty => 'Сізде әзірге турнирге қатысу жоқ';

  @override
  String get errTournamentFull => 'Бұл санат жаңа ғана толды';

  @override
  String get errDeadlinePassed => 'Тіркеу жабылды';

  @override
  String get errTournamentLevel =>
      'Сіздің немесе әріптесіңіздің деңгейі бұл санаттың аралығына сәйкес келмейді';

  @override
  String get errAlreadyRegistered => 'Сіз бұл санатқа тіркелгенсіз';

  @override
  String get errPartnerUnavailable => 'Бұл әріптес санатқа тіркеліп қойған';

  @override
  String get errNotFull => 'Орын қайта пайда болды. Тіркеліңіз';

  @override
  String get errWaitlistClosed => 'Бұл санатта күту тізімі жоқ';

  @override
  String get errRateLimited =>
      'Телефон бойынша іздеу тым көп. Бір сағаттан кейін қайталап көріңіз';

  @override
  String get notifTournamentFallback => 'турнир';

  @override
  String notifTournamentRegistered(String title) {
    return 'Сіз $title турнирінде тіркелдіңіз';
  }

  @override
  String notifTournamentPartnerInvite(String actor, String title) {
    return '$actor сізді $title турнирінде әріптес болуға шақырды';
  }

  @override
  String notifTournamentPartnerAccepted(String actor, String title) {
    return '$actor $title турниріне шақыруыңызды қабылдады';
  }

  @override
  String notifTournamentPartnerDeclined(String actor, String title) {
    return '$actor $title турниріне шақыруыңыздан бас тартты';
  }

  @override
  String notifTournamentPartnerCancelled(String actor, String title) {
    return '$actor $title турниріндегі жұп тіркелуіңізден бас тартты';
  }

  @override
  String notifTournamentPartnerExpired(String title) {
    return 'Әріптесіңіз $title турнирі бойынша уақытында жауап бермеді';
  }

  @override
  String notifTournamentSpotOffered(String title) {
    return '$title турнирінде сізге орын босады. Орын кетіп қалмай тұрып алыңыз';
  }

  @override
  String notifTournamentDeadlineReminder(String title) {
    return '$title турниріне тіркеу жақында жабылады, ал әріптесіңіз әлі жауап бермеді';
  }

  @override
  String notifTournamentRemoved(String title) {
    return 'Сіз $title турнирінен шығарылдыңыз';
  }

  @override
  String notifTournamentMoved(String title) {
    return 'Сіз $title турнирінде басқа санатқа ауыстырылдыңыз';
  }

  @override
  String notifTournamentMovedTo(String category, String title) {
    return 'Сіз $title турнирінде $category санатына ауыстырылдыңыз';
  }

  @override
  String get adminTournaments => 'Турнирлер';

  @override
  String get adminTournamentsHint => 'Санаттар мен қатысушылар';

  @override
  String get adminDashboard => 'Басқару тақтасы';

  @override
  String get adminDashboardHint => 'Пайдаланушылар, түсім және белсенділік';

  @override
  String get addTournament => 'Турнир қосу';

  @override
  String get newTournament => 'Жаңа турнир';

  @override
  String get noAdminTournaments => 'Сәйкес турнирлер жоқ';

  @override
  String tournamentCounts(int categories, int entries) {
    return '$categories санат · $entries қатысу';
  }

  @override
  String get tournamentDetails => 'Турнир мәліметтері';

  @override
  String get noVenue => 'Нысан жоқ';

  @override
  String get firstDayLabel => 'Бірінші күні';

  @override
  String get lastDayLabel => 'Соңғы күні';

  @override
  String get deadlineLabel => 'Тіркеу жабылады';

  @override
  String get coverUrlLabel => 'Мұқаба суретінің сілтемесі (https://…)';

  @override
  String get participantsLabel => 'Қатысушылар';

  @override
  String get addCategory => 'Санат қосу';

  @override
  String get newCategory => 'Жаңа санат';

  @override
  String get editCategory => 'Санатты өңдеу';

  @override
  String get deleteCategory => 'Санатты жою';

  @override
  String get addCategoryFirst => 'Кемінде бір санат қосыңыз';

  @override
  String get categoriesHint =>
      'Ойыншылар санатқа тіркеледі. Турнирде әрқашан кемінде бір санат болады.';

  @override
  String get capLabel => 'Орын саны';

  @override
  String get typeLabel => 'Түрі';

  @override
  String get genderLabel => 'Жынысы';

  @override
  String get minLevelLabel => 'Ең төменгі деңгей';

  @override
  String get maxLevelLabel => 'Ең жоғарғы деңгей';

  @override
  String get waitlistLabel => 'Күту тізімі';

  @override
  String get waitlistHint =>
      'Орын босағанда кезектегі келесі адамның оны алуға 24 сағаты болады';

  @override
  String capBelowFilled(int filled) {
    return 'Орын саны орын алып тұрған $filled қатысудан аз болмауы керек';
  }

  @override
  String get errHasRegistrations =>
      'Бұл санатта тіркелулер бар, сондықтан оны жоюға немесе басқа түрге ауыстыруға болмайды';

  @override
  String get errNotMarkable =>
      'Тек тіркелген қатысуларды ғана төленді деп белгілеуге болады';

  @override
  String get paidLabel => 'Төленді';

  @override
  String get moveRegistration => 'Басқа санатқа ауыстыру';

  @override
  String get removeEntry => 'Қатысуды жою';

  @override
  String get addPlayer => 'Ойыншы қосу';

  @override
  String get addPlayerNote =>
      'Қосылған ойыншылар деңгей тексеруінен өтпейді, бірақ орын санынан асып кете алмайды';

  @override
  String get offerNext => 'Келесіге ұсыну';

  @override
  String offerNextResult(int count) {
    return 'Жіберілген ұсыныстар: $count';
  }

  @override
  String get copyCsv => 'CSV көшіру';

  @override
  String get csvCopied => 'Алмасу буферіне көшірілді';

  @override
  String get noEntriesYet => 'Қатысулар әзірге жоқ';

  @override
  String pastEntries(int count) {
    return 'Өткен қатысулар ($count)';
  }

  @override
  String get periodCustom => 'Таңдауыңызша';

  @override
  String get usersTitle => 'Пайдаланушылар';

  @override
  String get usersTotal => 'Барлық пайдаланушылар';

  @override
  String get usersActive => '30 күндегі белсенділер';

  @override
  String get usersNewToday => 'Бүгін жаңа';

  @override
  String get usersNew7 => '7 күндегі жаңа';

  @override
  String get usersNewMonth => 'Осы айдағы жаңа';

  @override
  String get revenueTitle => 'Түсім';

  @override
  String get revenueCurrency => 'Валюта';

  @override
  String get revenueVenues => 'Нысандар';

  @override
  String get revenueTournaments => 'Турнирлер';

  @override
  String get revenueNote =>
      'Әр валютаның өз жолы бар. Әртүрлі валютадағы сомалар ешқашан қосылмайды.';

  @override
  String get noRevenue =>
      'Бұл кезеңде төленген брондаулар немесе қатысу жарналары жоқ';

  @override
  String get activityTitle => 'Белсенділік';

  @override
  String get countBookings => 'Жасалған брондаулар';

  @override
  String get countBookingsNote => 'бас тартылғандарды қоса';

  @override
  String get countGames => 'Құрылған ойындар';

  @override
  String get countRegistrations => 'Турнирге қатысулар';

  @override
  String get sportsPromptTitle => 'Спорт түрлеріңізді таңдаңыз';

  @override
  String get sportsPromptText =>
      'Немен және қай деңгейде ойнайтыныңызды көрсетіңіз — сізге сай ойындарды ұсынамыз.';

  @override
  String get chooseSports => 'Спорт түрлерін таңдау';

  @override
  String get notNow => 'Қазір емес';

  @override
  String get noSportsYet => 'Сіз әлі спорт түрлерін таңдамадыңыз';

  @override
  String get mySportsHint =>
      'Өзіңіз ойнайтын спорт түрлерін қосыңыз. Падел мен теннис қысқа сауалнамадан басталады.';

  @override
  String pickLevelTitle(String sport) {
    return '$sport: деңгейіңіз';
  }

  @override
  String get ratingProvisional => 'Алдын ала';

  @override
  String ratingWithProvisional(String rating) {
    return '$rating · алдын ала';
  }

  @override
  String ratedGames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Рейтингте $count ойын',
      one: 'Рейтингте $count ойын',
    );
    return '$_temp0';
  }

  @override
  String get noRatingYet => 'Әзірге рейтинг жоқ';

  @override
  String get retakeQuestionnaire => 'Қайта өту';

  @override
  String get ratingRangeLabel => 'Рейтинг аралығы';

  @override
  String ratingRangeValue(String range) {
    return 'Рейтинг $range';
  }

  @override
  String questionnaireTitle(String sport) {
    return '$sport: бастапқы рейтинг';
  }

  @override
  String questionnaireStep(int n, int total) {
    return '$n-сұрақ, барлығы $total';
  }

  @override
  String questionnaireResult(String rating) {
    return 'Бастапқы рейтингіңіз: $rating';
  }

  @override
  String questionnaireResultHint(int games) {
    return 'Ол алғашқы $games рейтингтік ойында алдын ала болып қалады және әр расталған нәтижеден кейін өзгереді.';
  }

  @override
  String get backLabel => 'Артқа';

  @override
  String get doneLabel => 'Дайын';

  @override
  String get adminRatingLocked =>
      'Actra белгілейді. Өзгерту үшін әзірлеушілерге хабарласыңыз.';

  @override
  String get qYears => 'Қанша уақыттан бері ойнайсыз?';

  @override
  String get qYearsA0 => '6 айдан аз';

  @override
  String get qYearsA1 => '6–24 ай';

  @override
  String get qYearsA2 => '2–5 жыл';

  @override
  String get qYearsA3 => '5 жылдан артық';

  @override
  String get qOften => 'Қаншалықты жиі ойнайсыз?';

  @override
  String get qOftenA0 => 'Сирек';

  @override
  String get qOftenA1 => 'Айына 2–3 рет';

  @override
  String get qOftenA2 => 'Апта сайын';

  @override
  String get qOftenA3 => 'Аптасына бірнеше рет';

  @override
  String get qCompeted => 'Жарыстарға қатысқансыз ба?';

  @override
  String get qCompetedA0 => 'Ешқашан';

  @override
  String get qCompetedA1 => 'Есеппен өтетін жолдастық ойындар';

  @override
  String get qCompetedA2 => 'Әуесқой турнирлер';

  @override
  String get qCompetedA3 => 'Тұрақты турнирлер немесе лига';

  @override
  String get qPadelWall => 'Артқы қабырғадан қалай ойнайсыз?';

  @override
  String get qPadelWallA0 => 'Одан қашқақтаймын';

  @override
  String get qPadelWallA1 => 'Баяу доптарды қайтарамын';

  @override
  String get qPadelWallA2 => 'Доптардың көбін қайтарамын';

  @override
  String get qPadelWallA3 => 'Қабырғадан шабуыл жасаймын';

  @override
  String get qPadelNet => 'Тор алдында…';

  @override
  String get qPadelNetA0 => 'Сирек шығамын';

  @override
  String get qPadelNetA1 => 'Жеңіл доптарды ауада қайтарамын';

  @override
  String get qPadelNetA2 => 'Торды ұстап, бағыттап ауада соғамын';

  @override
  String get qPadelNetA3 => 'Ұпайды ауадан соққы мен смэшпен аяқтаймын';

  @override
  String get qTennisServe => 'Подачаңыз қандай?';

  @override
  String get qTennisServeA0 => 'Жай ғана ойынды бастаймын';

  @override
  String get qTennisServeA1 => 'Түседі, бірақ баяу';

  @override
  String get qTennisServeA2 => 'Тұрақты бірінші және екінші подача';

  @override
  String get qTennisServeA3 => 'Онымен ұпай ұтамын';

  @override
  String get qTennisRally => 'Доп алмасуда…';

  @override
  String get qTennisRallyA0 => 'Бірнеше допты алаңда ұстаймын';

  @override
  String get qTennisRallyA1 => 'Орташа қарқынмен ойнаймын';

  @override
  String get qTennisRallyA2 => 'Бағыт пен тереңдікті бақылаймын';

  @override
  String get qTennisRallyA3 => 'Қарқын мен айналымды әдейі өзгертемін';

  @override
  String get notifCategoryRatings => 'Рейтинг';

  @override
  String get notifCategoryTeams => 'Командалар';

  @override
  String get notifGameFinishedScore => 'Ойын аяқталды. Есепті енгізіңіз';

  @override
  String get notifGameFinishedRate => 'Ойын аяқталды. Ойынды бағалаңыз';

  @override
  String get notifScoreEntered =>
      'Ойыныңыздың есебі енгізілді. Оны растаңыз немесе дау айтыңыз';

  @override
  String get notifScoreDisputed =>
      'Ойыныңыздың есебіне дау айтылды. Оны Actra әкімшісі қарайды';

  @override
  String get notifScoreResolved => 'Actra әкімшісі даулы есепті қарап шықты';

  @override
  String get notifScoreVoided => 'Ойыныңыздың есебі жойылды';

  @override
  String notifRatingUpdated(String from, String to) {
    return 'Рейтингіңіз өзгерді: $from → $to';
  }

  @override
  String get gameFinished => 'Ойын аяқталды';

  @override
  String get scoreEnter => 'Есепті енгізу';

  @override
  String get scoreHostEnters =>
      'Есепті ұйымдастырушы енгізеді. 24 сағаттан кейін мұны кез келген ойыншы жасай алады';

  @override
  String get scoreEntryClosed => 'Есеп енгізу жабылды';

  @override
  String get scoreAwaiting => 'Растауды күтуде';

  @override
  String get scoreWaitingOtherSide => 'Қарсы жақ күтілуде';

  @override
  String get scoreConfirm => 'Растау';

  @override
  String get scoreDispute => 'Дау айту';

  @override
  String get scoreEdit => 'Өзгерту';

  @override
  String get scoreConfirmedLabel => 'Есеп расталды';

  @override
  String get scoreDisputedLabel => 'Дау айтылды — Actra әкімшісі қарайды';

  @override
  String get scoreVoidedLabel => 'Нәтижені Actra болдырмады';

  @override
  String get scoreDisputeTitle => 'Есепке дау айтасыз ба?';

  @override
  String get scoreDisputeMsg =>
      'Оны Actra әкімшісі қарайды. Оған дейін рейтингтер өзгермейді.';

  @override
  String get scoreDisputeReason => 'Себебі (міндетті емес)';

  @override
  String get scoreWhoPlayed => 'Кім ойнады';

  @override
  String get scoreSingles => '1-ге 1';

  @override
  String get scoreDoubles => '2-ге 2';

  @override
  String get scorePartner => 'Серіктесіңіз';

  @override
  String get scoreOpponent => 'Қарсылас';

  @override
  String get scoreOpponents => 'Қарсыластар';

  @override
  String get scoreYourSide => 'Сіздің жағыңыз';

  @override
  String get scoreOtherSide => 'Қарсы жақ';

  @override
  String get scoreSets => 'Сеттер';

  @override
  String get scoreAddSet => 'Сет қосу';

  @override
  String get scoreRemoveSet => 'Сетті алып тастау';

  @override
  String get scoreMoreGames => 'Көбірек гейм';

  @override
  String get scoreFewerGames => 'Азырақ гейм';

  @override
  String get pastGames => 'Өткен ойындар';

  @override
  String get noPastGames => 'Соңғы 30 күнде ойындар болған жоқ';
}
