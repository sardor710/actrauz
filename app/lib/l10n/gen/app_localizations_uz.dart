// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Uzbek (`uz`).
class AppLocalizationsUz extends AppLocalizations {
  AppLocalizationsUz([String locale = 'uz']) : super(locale);

  @override
  String get appName => 'Actra';

  @override
  String get continueLabel => 'Davom etish';

  @override
  String get cancel => 'Bekor qilish';

  @override
  String get seeAll => 'Hammasi';

  @override
  String get today => 'Bugun';

  @override
  String get tomorrow => 'Ertaga';

  @override
  String get comingSoon => 'Tez orada';

  @override
  String get errGeneric => 'Xatolik yuz berdi. Qayta urinib koʻring.';

  @override
  String get chooseLanguage => 'Tilni tanlang';

  @override
  String get chooseCity => 'Shaharni tanlang';

  @override
  String get chooseCityHint =>
      'Shaharni istalgan vaqtda profilda oʻzgartirish mumkin';

  @override
  String get detectingCity => 'Shahringiz aniqlanmoqda…';

  @override
  String cityDetected(String city) {
    return 'Aniqlandi: $city';
  }

  @override
  String get signInTitle => 'Kirish';

  @override
  String get signInTelegram => 'Telegram orqali davom etish';

  @override
  String get demoNotice =>
      'Demo rejim: Telegram orqali kirish keyingi versiyada ulanadi. Davom etish uchun ismingizni kiriting. Koʻrsatilgan maydonlar, oʻyinlar va turnirlar namunaviy maʼlumotlar.';

  @override
  String get yourName => 'Ismingiz';

  @override
  String get nameRequired => 'Ismingizni kiriting';

  @override
  String get telegramHint =>
      'Telegram ochiladi. U yerda «Start» tugmasini bosing va telefon raqamingizni yuboring — u Actra akkauntingiz boʻladi.';

  @override
  String get telegramWaiting =>
      'Telegram kutilmoqda. Actra botiga telefon raqamingizni yuboring va shu yerga qayting.';

  @override
  String get telegramOpenAgain => 'Telegramni qayta ochish';

  @override
  String get telegramExpired =>
      'Kirish havolasi eskirdi. Qaytadan urinib koʻring.';

  @override
  String get signInFailed =>
      'Kirib boʻlmadi. Internet aloqasini tekshirib, qaytadan urinib koʻring.';

  @override
  String get acceptTerms =>
      'Foydalanish shartlari va Maxfiylik siyosatini qabul qilaman';

  @override
  String get termsRequired => 'Davom etish uchun shartlarni qabul qiling';

  @override
  String get tabHome => 'Asosiy';

  @override
  String get tabVenues => 'Maydonlar';

  @override
  String get tabGames => 'Oʻyinlar';

  @override
  String get tabProfile => 'Profil';

  @override
  String greeting(String name) {
    return 'Salom, $name';
  }

  @override
  String get homeGames => 'Mavjud oʻyinlar';

  @override
  String get homeCourts => 'Bugun boʻsh kortlar';

  @override
  String get homeTournaments => 'Turnirlar';

  @override
  String get noGames => 'Hozircha ochiq oʻyinlar yoʻq';

  @override
  String get noCourtsToday => 'Bugun boʻsh vaqt qolmadi';

  @override
  String get searchVenues => 'Maydon qidirish';

  @override
  String get allSports => 'Barcha sport turlari';

  @override
  String get noVenues => 'Maydonlar topilmadi';

  @override
  String fromPrice(String price) {
    return '$price dan';
  }

  @override
  String slotLength(int minutes) {
    return '$minutes daqiqa';
  }

  @override
  String get workingHours => 'Ish vaqti';

  @override
  String get closed => 'Yopiq';

  @override
  String get weekdays => 'Du–Ju';

  @override
  String get saturday => 'Sha';

  @override
  String get sunday => 'Yak';

  @override
  String get amenities => 'Qulayliklar';

  @override
  String get amenityParking => 'Avtoturargoh';

  @override
  String get amenityShowers => 'Dush';

  @override
  String get amenityLighting => 'Yoritish';

  @override
  String get amenityCafe => 'Kafe';

  @override
  String get amenityRental => 'Jihozlar ijarasi';

  @override
  String get courts => 'Kortlar';

  @override
  String get indoor => 'Yopiq kort';

  @override
  String get outdoor => 'Ochiq kort';

  @override
  String get book => 'Band qilish';

  @override
  String get phone => 'Telefon';

  @override
  String get address => 'Manzil';

  @override
  String get about => 'Maydon haqida';

  @override
  String get bookingTitle => 'Vaqtni tanlang';

  @override
  String get closedThatDay => 'Bu kuni kort ishlamaydi';

  @override
  String get selectHint => 'Bitta yoki ketma-ket bir nechta vaqtni tanlang';

  @override
  String slotsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta vaqt',
    );
    return '$_temp0';
  }

  @override
  String get total => 'Jami';

  @override
  String get summaryTitle => 'Bron tafsilotlari';

  @override
  String heldFor(String time) {
    return 'Vaqt siz uchun ushlab turilibdi: $time';
  }

  @override
  String get holdExpiredMsg =>
      'Ushlab turish vaqti tugadi. Vaqtni qaytadan tanlang.';

  @override
  String get paymentMethod => 'Toʻlov usuli';

  @override
  String get payAtVenue => 'Joyida toʻlash';

  @override
  String get payAtVenueHint => 'Maydonda naqd pul yoki karta orqali';

  @override
  String get playersCount => 'Oʻyinchilar soni';

  @override
  String get noteLabel => 'Izoh (ixtiyoriy)';

  @override
  String get confirmBooking => 'Bronni tasdiqlash';

  @override
  String get bookingConfirmed => 'Bron tasdiqlandi';

  @override
  String get dateLabel => 'Sana';

  @override
  String get timeLabel => 'Vaqt';

  @override
  String get courtLabel => 'Kort';

  @override
  String get errSlotTaken =>
      'Bu vaqtni hozirgina boshqa oʻyinchi band qildi. Boshqa vaqtni tanlang.';

  @override
  String get errNotContiguous => 'Tanlangan vaqtlar ketma-ket boʻlishi kerak';

  @override
  String errTooManyBookings(int count) {
    return 'Sizda allaqachon $count ta kelgusi bron bor';
  }

  @override
  String errTooFarAhead(int days) {
    return 'Bron qilish $days kun oldin ochiladi';
  }

  @override
  String get errInPast => 'Bu vaqt allaqachon oʻtib ketgan';

  @override
  String get myBookings => 'Mening bronlarim';

  @override
  String get noBookings => 'Sizda hali bronlar yoʻq';

  @override
  String get statusConfirmed => 'Tasdiqlangan';

  @override
  String get statusCancelled => 'Bekor qilingan';

  @override
  String get statusCompleted => 'Yakunlangan';

  @override
  String get cancelBooking => 'Bronni bekor qilish';

  @override
  String get cancelConfirmTitle => 'Bu bron bekor qilinsinmi?';

  @override
  String get cancelFreeMsg => 'Bekor qilish bepul.';

  @override
  String cancelLateMsg(int hours) {
    return 'Boshlanishiga $hours soatdan kam vaqt qoldi. Bu kech bekor qilish hisoblanadi va ishonchlilik darajangizni pasaytiradi.';
  }

  @override
  String get keepBooking => 'Bronni qoldirish';

  @override
  String get bookingCancelled => 'Bron bekor qilindi';

  @override
  String get lateCancellation => 'Kech bekor qilingan';

  @override
  String spotsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta joy qoldi',
      zero: 'Joy qolmadi',
    );
    return '$_temp0';
  }

  @override
  String levelRange(int min, int max) {
    return 'Daraja $min–$max';
  }

  @override
  String perPlayer(String price) {
    return 'Har bir oʻyinchiga ≈ $price';
  }

  @override
  String get host => 'Tashkilotchi';

  @override
  String get players => 'Oʻyinchilar';

  @override
  String get joinGame => 'Qoʻshilish';

  @override
  String get leaveGame => 'Oʻyindan chiqish';

  @override
  String get errGameFull => 'Bu oʻyinda joy qolmagan';

  @override
  String get errLevel => 'Darajangiz bu oʻyin uchun mos emas';

  @override
  String get you => 'Siz';

  @override
  String get entryFee => 'Ishtirok badali';

  @override
  String filledOf(int filled, int total) {
    return '$total tadan $filled tasi band';
  }

  @override
  String get language => 'Til';

  @override
  String get city => 'Shahar';

  @override
  String get signOut => 'Chiqish';

  @override
  String get deleteAccount => 'Akkauntni oʻchirish';

  @override
  String get deleteAccountTitle => 'Akkauntingiz oʻchirilsinmi?';

  @override
  String get deleteAccountBody =>
      'Kelgusi bronlaringiz va turnirlardagi arizalaringiz bekor qilinadi, oʻyinlaringizdan chiqasiz. Ismingiz va telefon raqamingiz oʻchiriladi. Buni ortga qaytarib boʻlmaydi.';

  @override
  String get deleteAccountConfirm => 'Oʻchirish';

  @override
  String get deleteAccountAdmin =>
      'Administrator akkauntini oʻchirib boʻlmaydi. Avval boshqa administratordan administrator huquqingizni olib tashlashni soʻrang.';

  @override
  String get deletedPlayer => 'Oʻchirilgan oʻyinchi';

  @override
  String get currencyUzs => 'soʻm';

  @override
  String get currencyKzt => '₸';

  @override
  String get searchHint => 'Maydon va sport turlarini qidirish';

  @override
  String get gamesBySports => 'Sport turlari boʻyicha oʻyinlar';

  @override
  String get venuesNearYou => 'Yaqin atrofdagi maydonlar';

  @override
  String get tabTournaments => 'Turnirlar';

  @override
  String get tabSocial => 'Hamjamiyat';

  @override
  String get allDays => 'Barchasi';

  @override
  String get filterSport => 'Sport turi';

  @override
  String get myLevel => 'Mening darajam';

  @override
  String going(int count, int spots) {
    return '$count/$spots keladi';
  }

  @override
  String gameTitle(String host, String sport) {
    return '$host bilan $sport';
  }

  @override
  String get createGame => 'Oʻyin yaratish';

  @override
  String get gamesPromoTitle => 'Oʻyinchi yetishmayaptimi?';

  @override
  String get gamesPromoText =>
      'Oʻz darajangizdagi oʻyinga qoʻshiling yoki oʻzingiznikini toʻldiring';

  @override
  String get bookable => 'Onlayn bron';

  @override
  String get favourites => 'Sevimlilar';

  @override
  String get sortPrice => 'Avval arzonlari';

  @override
  String get priceStartingFrom => 'Boshlangʻich narx';

  @override
  String get registrationOpen => 'Roʻyxatga olish ochiq';

  @override
  String get tournamentFull => 'Joy qolmadi';

  @override
  String get noTournaments => 'Hozircha turnirlar eʼlon qilinmagan';

  @override
  String get tournamentsPromoTitle => 'Kubok uchun oʻynang';

  @override
  String get tournamentsPromoText =>
      'Har qanday daraja uchun yakkalik va juftlik bahslari';

  @override
  String get noTeams => 'Bu shaharda hozircha jamoalar yoʻq';

  @override
  String members(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count aʼzo',
    );
    return '$_temp0';
  }

  @override
  String upcomingGames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta oʻyin',
    );
    return '$_temp0';
  }

  @override
  String get playersNearYou => 'Yaqin atrofdagi oʻyinchilar';

  @override
  String level(int level) {
    return 'Daraja $level';
  }

  @override
  String get inviteTitle => 'Doʻstlaringizni chaqiring';

  @override
  String get inviteText =>
      'Doʻstlaringizni Actraga taklif qiling, oʻyinlar tezroq toʻladi.';

  @override
  String get inviteCta => 'Doʻstlarni taklif qilish';

  @override
  String get statBookings => 'Bronlar';

  @override
  String get statGames => 'Oʻyinlar';

  @override
  String get statLate => 'Kech bekor qilish';

  @override
  String get mySports => 'Mening sport turlarim';

  @override
  String get morning => 'Ertalab';

  @override
  String get afternoon => 'Kunduzi';

  @override
  String get evening => 'Kechqurun';

  @override
  String get everyDay => 'Har kuni';

  @override
  String get gamesPromoCta => 'Kort band qilish';

  @override
  String get myVenues => 'Mening maydonlarim';

  @override
  String get ownerCalendar => 'Bronlar taqvimi';

  @override
  String get noVenuesAssigned => 'Sizga hali maydon biriktirilmagan';

  @override
  String get prevWeek => 'Oldingi hafta';

  @override
  String get nextWeek => 'Keyingi hafta';

  @override
  String get slotFree => 'Boʻsh';

  @override
  String get slotBooked => 'Band';

  @override
  String get slotBlocked => 'Yopilgan';

  @override
  String get closedThatWeek => 'Bu hafta kort ishlamaydi';

  @override
  String get newBooking => 'Yangi bron';

  @override
  String get blockTime => 'Vaqtni yopish';

  @override
  String get customerName => 'Mijoz ismi';

  @override
  String get customerNameRequired => 'Mijoz ismini kiriting';

  @override
  String get customerPhone => 'Telefon raqami (ixtiyoriy)';

  @override
  String get slotsCountLabel => 'Vaqtlar soni';

  @override
  String get payCash => 'Naqd';

  @override
  String get payCard => 'Karta';

  @override
  String get payTransfer => 'Oʻtkazma';

  @override
  String get saveBooking => 'Bronni saqlash';

  @override
  String get blockReason => 'Sabab (ixtiyoriy)';

  @override
  String get blockConfirm => 'Bu vaqtni yopish';

  @override
  String get unblock => 'Vaqtni qayta ochish';

  @override
  String get customerLabel => 'Mijoz';

  @override
  String get sourceLabel => 'Manba';

  @override
  String get statusLabel => 'Holat';

  @override
  String get reasonLabel => 'Sabab';

  @override
  String get sourceApp => 'Ilova orqali bron';

  @override
  String get sourceWalkIn => 'Joyida yoki telefon orqali';

  @override
  String get sourceBlock => 'Maydon tomonidan yopilgan';

  @override
  String get markPaid => 'Toʻlandi deb belgilash';

  @override
  String get markNoShow => 'Kelmadi deb belgilash';

  @override
  String get statusPaid => 'Toʻlangan';

  @override
  String get statusNoShow => 'Kelmadi';

  @override
  String get statusUnverified => 'Tasdiqlanmagan';

  @override
  String get statusCancelledByVenue => 'Maydon bekor qilgan';

  @override
  String get markAfterStart =>
      'Toʻlov va kelmaganlikni bron boshlangandan keyin belgilash mumkin';

  @override
  String get cancelByVenueMsg =>
      'Vaqt darhol boʻshaydi. Ilova orqali bron qilgan oʻyinchi bronni maydon bekor qilganini koʻradi.';

  @override
  String get errNotAllowed => 'Siz bu maydonni boshqarmaysiz';

  @override
  String get bookingSaved => 'Bron saqlandi';

  @override
  String get ownerSettings => 'Ish vaqti va narxlar';

  @override
  String get ownerDashboard => 'Statistika';

  @override
  String get venueHours => 'Maydon ish vaqti';

  @override
  String get courtHours => 'Kort ish vaqti';

  @override
  String get sameAsVenue => 'Maydon bilan bir xil';

  @override
  String get openLabel => 'Ochiq';

  @override
  String get editLabel => 'Oʻzgartirish';

  @override
  String get saveLabel => 'Saqlash';

  @override
  String get savedMsg => 'Saqlandi';

  @override
  String get pricesTitle => 'Narxlar';

  @override
  String get hoursTitle => 'Soatlar';

  @override
  String get slotLengthLabel => 'Vaqt uzunligi';

  @override
  String get basePrice => 'Bir vaqt uchun asosiy narx';

  @override
  String get priceRules => 'Narx qoidalari';

  @override
  String get addRule => 'Qoida qoʻshish';

  @override
  String get removeRule => 'Qoidani oʻchirish';

  @override
  String get ruleFrom => 'Dan';

  @override
  String get ruleTo => 'Gacha';

  @override
  String get rulePrice => 'Bir vaqt narxi';

  @override
  String get noRules => 'Qoidalar yoʻq: barcha vaqtlar asosiy narxda';

  @override
  String rulesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta narx qoidasi',
      zero: 'Narx qoidalari yoʻq',
    );
    return '$_temp0';
  }

  @override
  String get errInvalidHours =>
      'Ochilish vaqti yopilishdan oldin boʻlishi kerak';

  @override
  String get errRulesOverlap =>
      'Ikki qoida bir xil kun va vaqtga toʻgʻri keladi';

  @override
  String get errInvalidArgument =>
      'Qiymatlarni tekshirib, qayta urinib koʻring';

  @override
  String get errPickWeekday => 'Kamida bitta kunni tanlang';

  @override
  String get errPrice => 'Narxni kiriting';

  @override
  String get period7 => 'Oxirgi 7 kun';

  @override
  String get periodMonth => 'Shu oy';

  @override
  String get allCourts => 'Barcha kortlar';

  @override
  String metricSplit(int app, int walkIn) {
    return 'Ilova $app · joyida $walkIn';
  }

  @override
  String get metricRevenue => 'Toʻlangan tushum';

  @override
  String get metricUnconfirmed => 'Tasdiqlanmagan tushum';

  @override
  String get metricDailyAvg => 'Kuniga bronlar';

  @override
  String get metricUtilisation => 'Bandlik';

  @override
  String get metricNoShows => 'Kelmaganlar';

  @override
  String get peakHours => 'Eng band soatlar';

  @override
  String get noDataPeriod => 'Bu davrda bronlar yoʻq';

  @override
  String get adminTitle => 'Admin paneli';

  @override
  String get adminOnly => 'Bu sahifa faqat Actra administratorlari uchun';

  @override
  String get adminSports => 'Sport turlari';

  @override
  String get adminBanners => 'Bannerlar';

  @override
  String get adminAudit => 'Oʻzgarishlar jurnali';

  @override
  String get adminAuditHint => 'Kim, nimani va qachon oʻzgartirgan';

  @override
  String venuesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta maydon',
    );
    return '$_temp0';
  }

  @override
  String sportsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta sport turi',
    );
    return '$_temp0';
  }

  @override
  String bannersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta banner',
    );
    return '$_temp0';
  }

  @override
  String courtsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta kort',
    );
    return '$_temp0';
  }

  @override
  String ownersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta egasi',
      zero: 'Egalari yoʻq',
    );
    return '$_temp0';
  }

  @override
  String playersN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta oʻyinchi',
    );
    return '$_temp0';
  }

  @override
  String get inactive => 'Faol emas';

  @override
  String get activeLabel => 'Faol';

  @override
  String get activeHint => 'Oʻyinchilar buni koʻradi';

  @override
  String get addVenue => 'Maydon qoʻshish';

  @override
  String get newVenue => 'Yangi maydon';

  @override
  String get venueDetails => 'Asosiy maʼlumotlar';

  @override
  String get nameLabel => 'Nomi';

  @override
  String get descriptionLabel => 'Tavsif';

  @override
  String get districtLabel => 'Tuman';

  @override
  String get nameRequiredAny => 'Kamida bitta tilda toʻldiring';

  @override
  String get saveVenueFirst =>
      'Kort va egalarni qoʻshish uchun maydonni saqlang';

  @override
  String get addCourt => 'Kort qoʻshish';

  @override
  String get newCourt => 'Yangi kort';

  @override
  String get editCourt => 'Kortni tahrirlash';

  @override
  String get noCourts => 'Hozircha kortlar yoʻq';

  @override
  String get courtActions => 'Kort amallari';

  @override
  String get duplicateLabel => 'Nusxa olish';

  @override
  String get deleteLabel => 'Oʻchirish';

  @override
  String get deleteVenue => 'Maydonni oʻchirish';

  @override
  String deleteConfirmTitle(String name) {
    return '“$name” oʻchirilsinmi?';
  }

  @override
  String get deleteConfirmMsg => 'Buni ortga qaytarib boʻlmaydi.';

  @override
  String get errHasBookings =>
      'Bronlar bor, shuning uchun oʻchirib boʻlmaydi. Oʻyinchilardan yashirish uchun faolsizlantiring.';

  @override
  String get deactivateInstead => 'Faolsizlantirish';

  @override
  String get errAlreadyExists => 'Bu ID band';

  @override
  String get errNotFound => 'Topilmadi. Yangilab, qayta urinib koʻring.';

  @override
  String get ownersTitle => 'Egalari';

  @override
  String get assignOwner => 'Egasini tayinlash';

  @override
  String get removeOwner => 'Egasini olib tashlash';

  @override
  String get noOwners => 'Egalari tayinlanmagan';

  @override
  String get searchUsers => 'Ism yoki telefon';

  @override
  String get searchUsersMin => 'Kamida 2 ta belgi kiriting';

  @override
  String get noUsersFound => 'Hech kim topilmadi';

  @override
  String get addSport => 'Sport turini qoʻshish';

  @override
  String get newSport => 'Yangi sport turi';

  @override
  String get editSport => 'Sport turini tahrirlash';

  @override
  String get sportIdLabel => 'ID';

  @override
  String get sportIdHint =>
      'Kichik lotin harflari, raqamlar va _, masalan squash. Keyin oʻzgartirib boʻlmaydi.';

  @override
  String get errSportId =>
      '2–30 ta belgi: kichik lotin harflari, raqamlar yoki _, birinchisi harf boʻlsin';

  @override
  String get iconLabel => 'Belgi';

  @override
  String get sportTypeLabel => 'Turi';

  @override
  String get placeOnly => 'Faqat joy';

  @override
  String get ratingLabel => 'Reyting';

  @override
  String get ratingSimple => 'Daraja 1–5';

  @override
  String get ratingCompetitive => 'Reyting 1.0–7.0';

  @override
  String get defaultPlayers => 'Standart oʻyinchilar soni';

  @override
  String get sortOrderLabel => 'Roʻyxatdagi oʻrni';

  @override
  String get addBanner => 'Banner qoʻshish';

  @override
  String get newBanner => 'Yangi banner';

  @override
  String get editBanner => 'Bannerni tahrirlash';

  @override
  String get bannerTitle => 'Sarlavha';

  @override
  String get bannerSubtitle => 'Qoʻshimcha matn';

  @override
  String get linkLabel => 'Havola';

  @override
  String get errUrl => 'Havola https:// bilan boshlanishi kerak';

  @override
  String get allCities => 'Barcha shaharlar';

  @override
  String get noBanners => 'Hozircha bannerlar yoʻq';

  @override
  String get auditEmpty => 'Hozircha oʻzgarishlar yoʻq';

  @override
  String get loadMore => 'Yana koʻrsatish';

  @override
  String get auditBefore => 'Oldin';

  @override
  String get auditAfter => 'Keyin';

  @override
  String get auditSystem => 'Tizim';

  @override
  String get auditCreateVenue => 'Maydon yaratildi';

  @override
  String get auditUpdateVenue => 'Maydon oʻzgartirildi';

  @override
  String get auditDeleteVenue => 'Maydon oʻchirildi';

  @override
  String get auditCreateCourt => 'Kort yaratildi';

  @override
  String get auditUpdateCourt => 'Kort oʻzgartirildi';

  @override
  String get auditDuplicateCourt => 'Kortdan nusxa olindi';

  @override
  String get auditDeleteCourt => 'Kort oʻchirildi';

  @override
  String get auditAssignOwner => 'Egasi tayinlandi';

  @override
  String get auditRemoveOwner => 'Egasi olib tashlandi';

  @override
  String get auditCreateSport => 'Sport turi yaratildi';

  @override
  String get auditUpdateSport => 'Sport turi oʻzgartirildi';

  @override
  String get auditCreateBanner => 'Banner yaratildi';

  @override
  String get auditUpdateBanner => 'Banner oʻzgartirildi';

  @override
  String get auditDeleteBanner => 'Banner oʻchirildi';

  @override
  String get auditVenueHours => 'Maydon ish vaqti oʻzgartirildi';

  @override
  String get auditCourtHours => 'Kort ish vaqti oʻzgartirildi';

  @override
  String get auditCourtPricing => 'Kort narxlari oʻzgartirildi';

  @override
  String get auditWalkIn => 'Joyida bron qoʻshildi';

  @override
  String get auditBlock => 'Vaqt bloklandi';

  @override
  String get auditMarkBooking => 'Bron belgilandi';

  @override
  String get auditOwnerAccountDeleted => 'Egasi akkauntini oʻchirdi';

  @override
  String get auditHideSample => 'Namunaviy maʼlumot yashirildi';

  @override
  String get entityVenue => 'Maydon';

  @override
  String get entityBanner => 'Banner';

  @override
  String get entityBooking => 'Bron';

  @override
  String get entityOwner => 'Maydon egasi';

  @override
  String get notificationsTitle => 'Bildirishnomalar';

  @override
  String get markAllRead => 'Hammasini oʻqilgan qilish';

  @override
  String get notificationSettings => 'Bildirishnoma sozlamalari';

  @override
  String get noNotifications => 'Hozircha bildirishnomalar yoʻq';

  @override
  String get notificationsAndPrivacy => 'Bildirishnomalar va maxfiylik';

  @override
  String get notificationsMuteHint =>
      'Nima haqida xabar olishni tanlang. Guruhni oʻchirsangiz, uning bildirishnomalari kelmaydi.';

  @override
  String get notifCategoryBookings => 'Bronlar';

  @override
  String get notifCategoryVenue => 'Mening maydonlarim';

  @override
  String get notifCategoryGames => 'Oʻyinlar';

  @override
  String get notifCategoryRequests => 'Oʻyin eʼlonlari';

  @override
  String get notifCategoryInvites => 'Takliflar';

  @override
  String get notifCategoryTournaments => 'Turnirlar';

  @override
  String get privacyTitle => 'Maxfiylik';

  @override
  String get hideFromSearch => 'Meni oʻyinchilar qidiruvidan yashirish';

  @override
  String get hideFromSearchHint =>
      'Boshqa oʻyinchilar taklif qilish uchun qidirganda sizni topa olmaydi.';

  @override
  String get notifSomeone => 'Kimdir';

  @override
  String get notifVenueFallback => 'maydon';

  @override
  String get notifCourtFallback => 'kort';

  @override
  String notifBookingConfirmed(String venue) {
    return 'Bron tasdiqlandi: $venue';
  }

  @override
  String notifBookingCancelledByVenue(String venue) {
    return 'Maydon bronni bekor qildi: $venue';
  }

  @override
  String notifBookingReminder(String venue) {
    return 'Eslatma: bron yaqinlashmoqda, $venue';
  }

  @override
  String notifVenueNewBooking(String actor, String court) {
    return 'Yangi bron: $court ($actor)';
  }

  @override
  String notifVenueBookingCancelled(String actor, String court) {
    return 'Bron bekor qilindi: $court ($actor)';
  }

  @override
  String notifGameJoined(String actor) {
    return 'Oʻyiningizga yangi oʻyinchi: $actor';
  }

  @override
  String notifGameLeft(String actor) {
    return 'Oʻyindan chiqdi: $actor';
  }

  @override
  String notifJoinRequest(String actor) {
    return 'Qatnashish soʻrovi: $actor';
  }

  @override
  String get notifJoinApproved =>
      'Siz oʻyindasiz! Tashkilotchi soʻrovingizni qabul qildi';

  @override
  String get notifJoinDeclined => 'Tashkilotchi soʻrovingizni rad etdi';

  @override
  String get notifGameFull => 'Oʻyin toʻldi';

  @override
  String get notifGameChanged =>
      'Tashkilotchi oʻyin tafsilotlarini oʻzgartirdi';

  @override
  String get notifGameCancelled => 'Oʻyin bekor qilindi';

  @override
  String get notifGameRemoved => 'Tashkilotchi sizni oʻyindan chiqardi';

  @override
  String get notifGameReminder => 'Eslatma: oʻyin tez orada boshlanadi';

  @override
  String notifGameInvite(String actor) {
    return '$actor sizni oʻyinga taklif qildi';
  }

  @override
  String notifRequestInterest(String actor) {
    return 'Eʻloningizga javob: $actor';
  }

  @override
  String get notifRequestConvertedIn =>
      'Eʻlon oʻyinga aylandi va siz oʻyindasiz';

  @override
  String get notifRequestConvertedFull =>
      'Eʻlon oʻyinga aylandi, lekin joylar siz uchun yetmadi';

  @override
  String get notifRequestExpired => 'Oʻyin eʼlonining muddati tugadi';

  @override
  String get notifUnknown => 'Yangi bildirishnoma';

  @override
  String get reliabilityNew => 'Yangi oʻyinchi';

  @override
  String get reliabilityReliable => 'Ishonchli';

  @override
  String get reliabilityLimited => 'Cheklangan';

  @override
  String get reliabilityBlocked => 'Bloklangan';

  @override
  String reliabilityScore(int score) {
    return 'Ishonchlilik bahosi: 100 dan $score';
  }

  @override
  String get reliabilityLimitedHint =>
      'Bir vaqtning oʻzida bitta kelgusi bron qilish mumkin. Tiklanish uchun oʻyinlarga keling.';

  @override
  String get reliabilityBlockedHint =>
      'Eski oʻtkazib yuborilgan oʻyinlar 90 kundan oshmaguncha bron qilib, oʻyinga qoʻshilib va eʼlon bera olmaysiz.';

  @override
  String get gameSportLabel => 'Sport turi';

  @override
  String get pickSportHint => 'Oʻyin yaratish uchun sport turini tanlang';

  @override
  String get gameBookingLabel => 'Kort broningiz';

  @override
  String get noBookingForSport =>
      'Bu sport turi uchun sizda kelgusi tasdiqlangan bron yoʻq. Avval kortni bron qiling, soʻng oʻyin yarating.';

  @override
  String get bookACourt => 'Kortni bron qilish';

  @override
  String get gamePlaceLabel => 'Qayerda';

  @override
  String get placeVenue => 'Maydon';

  @override
  String get placeMeetingPoint => 'Uchrashuv joyi';

  @override
  String get chooseVenue => 'Maydonni tanlang';

  @override
  String get meetingPointHint => 'Masalan: bogʻning asosiy darvozasi';

  @override
  String get meetingPointRequired => 'Uchrashuv joyini kiriting';

  @override
  String get venueRequired => 'Maydonni tanlang';

  @override
  String get gameWhenLabel => 'Qachon';

  @override
  String get gameStartTime => 'Boshlanishi';

  @override
  String get gameDuration => 'Davomiyligi';

  @override
  String minutesShort(int count) {
    return '$count daq';
  }

  @override
  String get distanceLabel => 'Masofa, km (ixtiyoriy)';

  @override
  String get paceLabel => 'Temp (ixtiyoriy)';

  @override
  String get paceHint => 'Masalan 6:00 daq/km';

  @override
  String distanceValue(String km) {
    return '$km km';
  }

  @override
  String paceValue(String pace) {
    return 'Temp $pace';
  }

  @override
  String get spotsLabel => 'Joylar, oʻzingiz bilan';

  @override
  String get fewerSpots => 'Kamroq joy';

  @override
  String get moreSpots => 'Koʻproq joy';

  @override
  String get levelRangeLabel => 'Daraja oraligʻi';

  @override
  String get visibilityLabel => 'Oʻyinni kim koʻradi';

  @override
  String get visibilityPublic => 'Hammaga ochiq';

  @override
  String get visibilityInviteOnly => 'Faqat taklif bilan';

  @override
  String get askToJoin => 'Qoʻshilishni soʻrash';

  @override
  String get requested => 'Soʻrov yuborildi';

  @override
  String get withdrawRequest => 'Soʻrovni qaytarib olish';

  @override
  String get invitedToGame => 'Sizni bu oʻyinga taklif qilishdi';

  @override
  String get invitedPill => 'Taklif';

  @override
  String get acceptInvite => 'Qabul qilish';

  @override
  String get declineLabel => 'Rad etish';

  @override
  String get approveLabel => 'Tasdiqlash';

  @override
  String get requestsTitle => 'Soʻrovlar';

  @override
  String get hostTools => 'Oʻyinni boshqarish';

  @override
  String get editGame => 'Oʻyinni tahrirlash';

  @override
  String get cancelGame => 'Oʻyinni bekor qilish';

  @override
  String get cancelGameTitle => 'Bu oʻyin bekor qilinsinmi?';

  @override
  String get cancelGameMsg => 'Oʻyinchilarga xabar beriladi.';

  @override
  String get alsoCancelBooking => 'Kort bronini ham bekor qilish';

  @override
  String get alsoCancelBookingHint =>
      'Kortni boshqalar uchun boʻshatadi. Kech bekor qilish qoidalari amal qiladi.';

  @override
  String get keepGame => 'Oʻyinni qoldirish';

  @override
  String get gameCancelled => 'Oʻyin bekor qilindi';

  @override
  String get gameCancelledBanner => 'Bu oʻyin bekor qilingan';

  @override
  String get removePlayer => 'Oʻyinchini chiqarish';

  @override
  String removePlayerTitle(String name) {
    return '$name oʻyindan chiqarilsinmi?';
  }

  @override
  String get removePlayerMsg => 'Oʻyinchiga xabar beriladi.';

  @override
  String get removeLabel => 'Chiqarish';

  @override
  String get createGameFromBooking => 'Shu bron boʻyicha oʻyin yaratish';

  @override
  String get errSpotsBelowPlayers =>
      'Joylar oʻyindagi oʻyinchilardan kam boʻlishi mumkin emas';

  @override
  String get errAlreadyJoined => 'Siz allaqachon bu oʻyindasiz';

  @override
  String get errNotParticipant => 'Siz bu oʻyinda emassiz';

  @override
  String get errHostCannotLeave =>
      'Tashkilotchi oʻyindan chiqa olmaydi. Oʻyinni bekor qiling.';

  @override
  String get errAlreadyRequested =>
      'Siz bu oʻyinga allaqachon soʻrov yuborgansiz';

  @override
  String get errBookingNotUsable =>
      'Shu sport turi uchun oʻzingizning, hali boshlanmagan tasdiqlangan broningizni tanlang';

  @override
  String get errGameExists => 'Bu bronda allaqachon oʻyin bor';

  @override
  String get errForbidden => 'Siz bu oʻyinda buni qila olmaysiz';

  @override
  String get errNotCancellable => 'Oʻyin boshlangan, uni bekor qilib boʻlmaydi';

  @override
  String get errScoreClosed => 'Bu oʻyin uchun endi hisob kiritib boʻlmaydi';

  @override
  String get errUnavailable =>
      'Serverga ulanib boʻlmadi. Internetni tekshiring.';

  @override
  String get gamesTabRequests => 'Eʼlonlar';

  @override
  String get homeRequests => 'Oʻyin eʼlonlari';

  @override
  String interestedOf(int count, int total) {
    return '$total tadan $count tasi tayyor';
  }

  @override
  String requestTitle(String host, String sport) {
    return '$host $sport oʻynamoqchi';
  }

  @override
  String needsPlayers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Yana $count ta oʻyinchi kerak',
    );
    return '$_temp0';
  }

  @override
  String get noRequests =>
      'Hozircha eʼlonlar yoʻq. Oʻyinchi topish uchun eʼlon joylang.';

  @override
  String get postRequest => 'Eʼlon joylash';

  @override
  String get createRequestTitle => 'Oʻyin eʼloni';

  @override
  String get requestPlayersNeeded => 'Kerakli oʻyinchilar';

  @override
  String get requestWindowLabel => 'Qachon oʻynay olasiz?';

  @override
  String get requestFrom => 'Boshlanishi';

  @override
  String get requestTo => 'Tugashi';

  @override
  String get areaLabel => 'Hudud (ixtiyoriy)';

  @override
  String get areaHint => 'Masalan, Yunusobod';

  @override
  String get venueOptional => 'Maydon (ixtiyoriy)';

  @override
  String get anyVenue => 'Istalgan maydon';

  @override
  String get postRequestCta => 'Eʼlonni joylash';

  @override
  String get imIn => 'Men bor';

  @override
  String get leaveRequest => 'Chiqish';

  @override
  String get interestedPlayers => 'Tayyor oʻyinchilar';

  @override
  String get noInterestedYet => 'Hali hech kim javob bermadi';

  @override
  String get makeItAGame => 'Oʻyinga aylantirish';

  @override
  String get convertHint =>
      'Tayyor oʻyinchilar bosgan tartibda, joy borida qoʻshiladi.';

  @override
  String get gameEndTime => 'Tugashi';

  @override
  String get cancelRequestLabel => 'Eʼlonni bekor qilish';

  @override
  String get cancelRequestTitle => 'Eʼlon bekor qilinsinmi?';

  @override
  String get cancelRequestMsg => 'Tayyor oʻyinchilar uni endi koʻrmaydi.';

  @override
  String get keepRequest => 'Eʼlon qolsin';

  @override
  String get requestCancelledMsg => 'Eʼlon bekor qilindi';

  @override
  String get removeInterestedMsg => 'Oʻyinchi roʻyxatdan chiqariladi.';

  @override
  String get requestConvertedBanner => 'Eʼlon oʻyinga aylandi';

  @override
  String get openGameCta => 'Oʻyinni ochish';

  @override
  String get requestClosedBanner => 'Eʼlon yopilgan';

  @override
  String get findPlayers => 'Oʻyinchi izlash';

  @override
  String get searchPlayersHint => 'Ism boʻyicha qidirish';

  @override
  String get noPlayersFound => 'Oʻyinchilar topilmadi';

  @override
  String gamesPlayed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta oʻyin oʻynagan',
    );
    return '$_temp0';
  }

  @override
  String get playerProfileTitle => 'Oʻyinchi profili';

  @override
  String get profileLevels => 'Darajalar';

  @override
  String get noLevelsYet => 'Darajalar hali koʻrsatilmagan';

  @override
  String get inviteToGame => 'Oʻyinga taklif qilish';

  @override
  String get chooseGameToInvite => 'Oʻyinni tanlang';

  @override
  String get noGamesToInvite =>
      'Boʻsh joyli ochiq oʻyiningiz yoʻq. Avval oʻyin yarating.';

  @override
  String inviteSent(String name) {
    return '$name taklif qilindi';
  }

  @override
  String get tournamentsMine => 'Mening turnirlarim';

  @override
  String get tournamentFilterDate => 'Sana';

  @override
  String tournamentFilterFrom(String date) {
    return '$date dan';
  }

  @override
  String get tournamentSortAz => 'A–Z';

  @override
  String get registrationClosed => 'Roʻyxatdan oʻtish yopilgan';

  @override
  String get tournamentFree => 'Bepul';

  @override
  String get tournamentCategories => 'Toifalar';

  @override
  String tournamentDeadline(String when) {
    return 'Roʻyxatdan oʻtish $when gacha';
  }

  @override
  String get tournamentClosedBanner => 'Roʻyxatdan oʻtish yakunlandi';

  @override
  String get kindSingles => 'Yakkalik';

  @override
  String get kindPairs => 'Juftliklar';

  @override
  String get genderMen => 'Erkaklar';

  @override
  String get genderWomen => 'Ayollar';

  @override
  String get genderMixed => 'Aralash';

  @override
  String get genderOpen => 'Ochiq';

  @override
  String waitlistCount(int count) {
    return 'Kutayotganlar: $count';
  }

  @override
  String get joinWaitlist => 'Kutish roʻyxatiga yozilish';

  @override
  String get registerLabel => 'Roʻyxatdan oʻtish';

  @override
  String get confirmRegistration => 'Roʻyxatdan oʻtishni tasdiqlash';

  @override
  String registerSheetTitle(String category) {
    return 'Roʻyxatdan oʻtish: $category';
  }

  @override
  String waitlistSheetTitle(String category) {
    return 'Kutish roʻyxati: $category';
  }

  @override
  String registrationFeeNote(String fee) {
    return 'Ishtirok toʻlovi $fee tashkilotchiga toʻlanadi.';
  }

  @override
  String get waitlistSheetNote =>
      'Toifa toʻlgan. Joy boʻshasa, uni egallash uchun 24 soat beriladi.';

  @override
  String get partnerTitle => 'Sherik tanlang';

  @override
  String get partnerTabPlayers => 'Oʻyinchilar';

  @override
  String get partnerTabPhone => 'Telefon raqami';

  @override
  String get partnerPhoneHint => '+998 90 123 45 67';

  @override
  String get partnerFind => 'Qidirish';

  @override
  String get partnerNotFound => 'Bu raqamli oʻyinchi topilmadi';

  @override
  String get partnerPickFirst => 'Avval sherikni tanlang';

  @override
  String get sendInvite => 'Taklif yuborish';

  @override
  String get inviteNote =>
      'Sherikda taklifni qabul qilish uchun 48 soat bor, roʻyxatdan oʻtish ertaroq tugasa, shungacha. Juftlik sherik rozi boʻlgach joy egallaydi.';

  @override
  String get statusRegistered => 'Roʻyxatga olingan';

  @override
  String get statusPendingPartner => 'Sherik kutilmoqda';

  @override
  String get statusInvited => 'Taklif';

  @override
  String get statusWaitlisted => 'Kutish roʻyxatida';

  @override
  String get statusOffered => 'Joy taklif qilindi';

  @override
  String get statusDeclined => 'Rad etilgan';

  @override
  String get statusExpired => 'Muddati tugagan';

  @override
  String get statusRemoved => 'Chiqarilgan';

  @override
  String get statusLapsed => 'Taklif muddati tugadi';

  @override
  String waitlistPlaceLabel(int place) {
    return 'Navbatdagi oʻrni: $place';
  }

  @override
  String pairedWith(String name) {
    return '$name bilan juftlikda';
  }

  @override
  String partnerInvitedYou(String name) {
    return '$name sizni juftlikka taklif qildi';
  }

  @override
  String get acceptLabel => 'Qabul qilish';

  @override
  String get claimLabel => 'Joyni egallash';

  @override
  String offerHeld(String left) {
    return 'Joy siz uchun saqlanmoqda · $left qoldi';
  }

  @override
  String durationHm(int hours, int minutes) {
    return '$hours soat $minutes daq';
  }

  @override
  String durationMin(int minutes) {
    return '$minutes daq';
  }

  @override
  String get cancelRegistration => 'Roʻyxatdan oʻtishni bekor qilish';

  @override
  String get cancelRegistrationTitle => 'Roʻyxatdan oʻtishni bekor qilasizmi?';

  @override
  String get cancelRegistrationMsg =>
      'Joy navbatdagi oʻyinchiga oʻtadi. Joy qolsa, muddat tugaguncha qayta yozilishingiz mumkin.';

  @override
  String get keepRegistration => 'Qoldirish';

  @override
  String get myTournamentsEmpty => 'Sizda hali turnirlarga arizalar yoʻq';

  @override
  String get errTournamentFull => 'Bu toifa hozirgina toʻldi';

  @override
  String get errDeadlinePassed => 'Roʻyxatdan oʻtish yopilgan';

  @override
  String get errTournamentLevel =>
      'Sizning yoki sherigingiz darajasi bu toifaga mos kelmaydi';

  @override
  String get errAlreadyRegistered => 'Siz bu toifada allaqachon qatnashasiz';

  @override
  String get errPartnerUnavailable => 'Bu sherik toifada allaqachon bor';

  @override
  String get errNotFull => 'Yana joy bor, roʻyxatdan oʻting';

  @override
  String get errWaitlistClosed => 'Bu toifada kutish roʻyxati yoʻq';

  @override
  String get errRateLimited =>
      'Raqam boʻyicha qidiruv juda koʻp. Bir soatdan keyin urinib koʻring';

  @override
  String get notifTournamentFallback => 'turnir';

  @override
  String notifTournamentRegistered(String title) {
    return 'Siz roʻyxatdan oʻtdingiz: $title';
  }

  @override
  String notifTournamentPartnerInvite(String actor, String title) {
    return '$actor sizni juftlikka taklif qildi: $title';
  }

  @override
  String notifTournamentPartnerAccepted(String actor, String title) {
    return '$actor taklifingizni qabul qildi: $title';
  }

  @override
  String notifTournamentPartnerDeclined(String actor, String title) {
    return '$actor taklifingizni rad etdi: $title';
  }

  @override
  String notifTournamentPartnerCancelled(String actor, String title) {
    return '$actor juftlik arizangizni bekor qildi: $title';
  }

  @override
  String notifTournamentPartnerExpired(String title) {
    return 'Sherik oʻz vaqtida javob bermadi: $title';
  }

  @override
  String notifTournamentSpotOffered(String title) {
    return 'Siz uchun joy boʻshadi: $title. Boshqaga ketmasidan egallang';
  }

  @override
  String notifTournamentDeadlineReminder(String title) {
    return 'Roʻyxatdan oʻtish tez orada tugaydi, sherik esa javob bermadi: $title';
  }

  @override
  String notifTournamentRemoved(String title) {
    return 'Siz turnirdan chiqarildingiz: $title';
  }

  @override
  String notifTournamentMoved(String title) {
    return 'Siz boshqa toifaga oʻtkazildingiz: $title';
  }

  @override
  String notifTournamentMovedTo(String category, String title) {
    return 'Siz $category toifasiga oʻtkazildingiz: $title';
  }

  @override
  String get adminTournaments => 'Turnirlar';

  @override
  String get adminTournamentsHint => 'Kategoriyalar va ishtirokchilar';

  @override
  String get adminDashboard => 'Boshqaruv paneli';

  @override
  String get adminDashboardHint => 'Foydalanuvchilar, daromad va faollik';

  @override
  String get addTournament => 'Turnir qoʻshish';

  @override
  String get newTournament => 'Yangi turnir';

  @override
  String get noAdminTournaments => 'Mos turnirlar yoʻq';

  @override
  String tournamentCounts(int categories, int entries) {
    return 'Kategoriyalar: $categories · arizalar: $entries';
  }

  @override
  String get tournamentDetails => 'Turnir haqida';

  @override
  String get noVenue => 'Maydonsiz';

  @override
  String get firstDayLabel => 'Birinchi kun';

  @override
  String get lastDayLabel => 'Oxirgi kun';

  @override
  String get deadlineLabel => 'Roʻyxatdan oʻtish tugaydi';

  @override
  String get coverUrlLabel => 'Muqova rasmi havolasi (https://…)';

  @override
  String get participantsLabel => 'Ishtirokchilar';

  @override
  String get addCategory => 'Kategoriya qoʻshish';

  @override
  String get newCategory => 'Yangi kategoriya';

  @override
  String get editCategory => 'Kategoriyani tahrirlash';

  @override
  String get deleteCategory => 'Kategoriyani oʻchirish';

  @override
  String get addCategoryFirst => 'Kamida bitta kategoriya qoʻshing';

  @override
  String get categoriesHint =>
      'Oʻyinchilar kategoriyaga roʻyxatdan oʻtadi. Turnirda kamida bitta kategoriya qoladi.';

  @override
  String get capLabel => 'Joylar soni';

  @override
  String get typeLabel => 'Turi';

  @override
  String get genderLabel => 'Jins';

  @override
  String get minLevelLabel => 'Eng past daraja';

  @override
  String get maxLevelLabel => 'Eng yuqori daraja';

  @override
  String get waitlistLabel => 'Kutish roʻyxati';

  @override
  String get waitlistHint =>
      'Joy boʻshaganda navbatdagiga uni egallash uchun 24 soat beriladi';

  @override
  String capBelowFilled(int filled) {
    return 'Joylar soni band boʻlgan $filled tadan kam boʻlishi mumkin emas';
  }

  @override
  String get errHasRegistrations =>
      'Bu kategoriyada arizalar bor: uni oʻchirib yoki turini oʻzgartirib boʻlmaydi';

  @override
  String get errNotMarkable =>
      'Toʻlovni faqat roʻyxatdan oʻtgan arizalarda belgilash mumkin';

  @override
  String get paidLabel => 'Toʻlangan';

  @override
  String get moveRegistration => 'Boshqa kategoriyaga oʻtkazish';

  @override
  String get removeEntry => 'Arizani olib tashlash';

  @override
  String get addPlayer => 'Oʻyinchi qoʻshish';

  @override
  String get addPlayerNote =>
      'Qoʻshilgan oʻyinchilar daraja tekshiruvidan oʻtmaydi, joylar limiti esa amal qiladi';

  @override
  String get offerNext => 'Navbatdagiga taklif qilish';

  @override
  String offerNextResult(int count) {
    return 'Yuborilgan takliflar: $count';
  }

  @override
  String get copyCsv => 'CSV nusxalash';

  @override
  String get csvCopied => 'Buferga nusxalandi';

  @override
  String get noEntriesYet => 'Hozircha arizalar yoʻq';

  @override
  String pastEntries(int count) {
    return 'Oldingi arizalar ($count)';
  }

  @override
  String get periodCustom => 'Oraliq tanlash';

  @override
  String get usersTitle => 'Foydalanuvchilar';

  @override
  String get usersTotal => 'Jami foydalanuvchilar';

  @override
  String get usersActive => '30 kunda faol';

  @override
  String get usersNewToday => 'Bugun yangi';

  @override
  String get usersNew7 => '7 kunda yangi';

  @override
  String get usersNewMonth => 'Bu oyda yangi';

  @override
  String get revenueTitle => 'Daromad';

  @override
  String get revenueCurrency => 'Valyuta';

  @override
  String get revenueVenues => 'Maydonlar';

  @override
  String get revenueTournaments => 'Turnirlar';

  @override
  String get revenueNote =>
      'Har bir valyutaning oʻz qatori bor. Turli valyutadagi summalar qoʻshilmaydi.';

  @override
  String get noRevenue => 'Bu davrda toʻlangan bronlar va badallar yoʻq';

  @override
  String get activityTitle => 'Faollik';

  @override
  String get countBookings => 'Yaratilgan bronlar';

  @override
  String get countBookingsNote => 'bekor qilinganlar bilan';

  @override
  String get countGames => 'Yaratilgan oʻyinlar';

  @override
  String get countRegistrations => 'Turnir arizalari';

  @override
  String get sportsPromptTitle => 'Sport turlaringizni tanlang';

  @override
  String get sportsPromptText =>
      'Nima oʻynashingiz va qay darajada ekanini belgilang — sizga mos oʻyinlarni koʻrsatamiz.';

  @override
  String get chooseSports => 'Sport turlarini tanlash';

  @override
  String get notNow => 'Hozir emas';

  @override
  String get noSportsYet => 'Siz hali sport turlarini tanlamadingiz';

  @override
  String get mySportsHint =>
      'Oʻzingiz oʻynaydigan sport turlarini yoqing. Padel va tennis qisqa soʻrovnomadan boshlanadi.';

  @override
  String pickLevelTitle(String sport) {
    return '$sport: darajangiz';
  }

  @override
  String get ratingProvisional => 'Dastlabki';

  @override
  String ratingWithProvisional(String rating) {
    return '$rating · dastlabki';
  }

  @override
  String ratedGames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Reytingda $count ta oʻyin',
    );
    return '$_temp0';
  }

  @override
  String get noRatingYet => 'Hali reyting yoʻq';

  @override
  String get leaderboards => 'Reyting jadvallari';

  @override
  String leaderboardTitle(String city) {
    return 'Reyting jadvali · $city';
  }

  @override
  String leaderboardEmpty(String city) {
    return '$city shahrida tasdiqlangan natijalar hali yoʻq.';
  }

  @override
  String leaderboardGames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta oʻyin',
    );
    return '$_temp0';
  }

  @override
  String get retakeQuestionnaire => 'Qayta topshirish';

  @override
  String get ratingRangeLabel => 'Reyting oraligʻi';

  @override
  String ratingRangeValue(String range) {
    return 'Reyting $range';
  }

  @override
  String questionnaireTitle(String sport) {
    return '$sport: boshlangʻich reyting';
  }

  @override
  String questionnaireStep(int n, int total) {
    return '$total tadan $n-savol';
  }

  @override
  String questionnaireResult(String rating) {
    return 'Boshlangʻich reytingingiz: $rating';
  }

  @override
  String questionnaireResultHint(int games) {
    return 'Reytingli birinchi $games ta oʻyiningizda u dastlabki boʻlib qoladi va har bir tasdiqlangan natijadan soʻng oʻzgaradi.';
  }

  @override
  String get backLabel => 'Orqaga';

  @override
  String get doneLabel => 'Tayyor';

  @override
  String get adminRatingLocked =>
      'Actra tomonidan belgilanadi. Oʻzgartirish uchun dasturchilarga murojaat qiling.';

  @override
  String get qYears => 'Qancha vaqtdan beri oʻynaysiz?';

  @override
  String get qYearsA0 => '6 oydan kam';

  @override
  String get qYearsA1 => '6–24 oy';

  @override
  String get qYearsA2 => '2–5 yil';

  @override
  String get qYearsA3 => '5 yildan ortiq';

  @override
  String get qOften => 'Qanchalik tez-tez oʻynaysiz?';

  @override
  String get qOftenA0 => 'Kamdan-kam';

  @override
  String get qOftenA1 => 'Oyiga 2–3 marta';

  @override
  String get qOftenA2 => 'Har hafta';

  @override
  String get qOftenA3 => 'Haftasiga bir necha marta';

  @override
  String get qCompeted => 'Musobaqalarda qatnashganmisiz?';

  @override
  String get qCompetedA0 => 'Hech qachon';

  @override
  String get qCompetedA1 => 'Hisobli oʻrtoqlik oʻyinlari';

  @override
  String get qCompetedA2 => 'Havaskorlar turnirlari';

  @override
  String get qCompetedA3 => 'Muntazam turnirlar yoki liga';

  @override
  String get qPadelWall => 'Orqa devordan qanday oʻynaysiz?';

  @override
  String get qPadelWallA0 => 'Undan qochaman';

  @override
  String get qPadelWallA1 => 'Sekin toʻplarni qaytaraman';

  @override
  String get qPadelWallA2 => 'Koʻp toʻplarni qaytaraman';

  @override
  String get qPadelWallA3 => 'Devordan hujum qilaman';

  @override
  String get qPadelNet => 'Toʻr oldida…';

  @override
  String get qPadelNetA0 => 'Kamdan-kam chiqaman';

  @override
  String get qPadelNetA1 => 'Oson toʻplarni havoda qaytaraman';

  @override
  String get qPadelNetA2 => 'Toʻrni ushlab, yoʻnaltirib havoda uraman';

  @override
  String get qPadelNetA3 => 'Ochkoni havodan zarba va smesh bilan yakunlayman';

  @override
  String get qTennisServe => 'Servisingiz qanday?';

  @override
  String get qTennisServeA0 => 'Shunchaki oʻyinni boshlayman';

  @override
  String get qTennisServeA1 => 'Tushadi, lekin sekin';

  @override
  String get qTennisServeA2 => 'Barqaror birinchi va ikkinchi servis';

  @override
  String get qTennisServeA3 => 'U bilan ochko yutaman';

  @override
  String get qTennisRally => 'Toʻp almashinuvida…';

  @override
  String get qTennisRallyA0 => 'Bir nechta toʻpni maydonda ushlab turaman';

  @override
  String get qTennisRallyA1 => 'Oʻrtacha tezlikda oʻynayman';

  @override
  String get qTennisRallyA2 => 'Yoʻnalish va chuqurlikni nazorat qilaman';

  @override
  String get qTennisRallyA3 => 'Tezlik va aylanishni ataylab oʻzgartiraman';

  @override
  String get notifCategoryRatings => 'Reyting';

  @override
  String get notifCategoryTeams => 'Jamoalar';

  @override
  String get notifGameFinishedScore => 'Oʻyin tugadi. Hisobni kiriting';

  @override
  String get notifGameFinishedRate => 'Oʻyin tugadi. Oʻyinni baholang';

  @override
  String get notifScoreEntered =>
      'Oʻyiningiz hisobi kiritildi. Uni tasdiqlang yoki eʼtiroz bildiring';

  @override
  String get notifScoreDisputed =>
      'Oʻyiningiz hisobiga eʼtiroz bildirildi. Uni Actra administratori koʻrib chiqadi';

  @override
  String get notifScoreResolved =>
      'Actra administratori eʼtirozli hisobni koʻrib chiqdi';

  @override
  String get notifScoreVoided => 'Oʻyiningiz hisobi bekor qilindi';

  @override
  String notifRatingUpdated(String from, String to) {
    return 'Reytingingiz oʻzgardi: $from → $to';
  }

  @override
  String get gameFinished => 'Oʻyin tugadi';

  @override
  String get scoreEnter => 'Hisobni kiritish';

  @override
  String get scoreHostEnters =>
      'Hisobni tashkilotchi kiritadi. 24 soatdan keyin buni istalgan oʻyinchi qila oladi';

  @override
  String get scoreEntryClosed => 'Hisob kiritish yopildi';

  @override
  String get scoreAwaiting => 'Tasdiqlash kutilmoqda';

  @override
  String get scoreWaitingOtherSide => 'Qarshi tomon kutilmoqda';

  @override
  String get scoreConfirm => 'Tasdiqlash';

  @override
  String get scoreDispute => 'Eʼtiroz bildirish';

  @override
  String get scoreEdit => 'Tahrirlash';

  @override
  String get scoreConfirmedLabel => 'Hisob tasdiqlandi';

  @override
  String get scoreDisputedLabel =>
      'Eʼtiroz bildirildi — Actra administratori koʻrib chiqadi';

  @override
  String get scoreVoidedLabel => 'Natija Actra tomonidan bekor qilindi';

  @override
  String get scoreDisputeTitle => 'Hisobga eʼtiroz bildirasizmi?';

  @override
  String get scoreDisputeMsg =>
      'Uni Actra administratori koʻrib chiqadi. Ungacha reytinglar oʻzgarmaydi.';

  @override
  String get scoreDisputeReason => 'Sabab (ixtiyoriy)';

  @override
  String get scoreWhoPlayed => 'Kim oʻynadi';

  @override
  String get scoreSingles => '1 ga 1';

  @override
  String get scoreDoubles => '2 ga 2';

  @override
  String get scorePartner => 'Sherigingiz';

  @override
  String get scoreOpponent => 'Raqib';

  @override
  String get scoreOpponents => 'Raqiblar';

  @override
  String get scoreYourSide => 'Sizning tomoningiz';

  @override
  String get scoreOtherSide => 'Qarshi tomon';

  @override
  String get scoreSets => 'Setlar';

  @override
  String get scoreAddSet => 'Set qoʻshish';

  @override
  String get scoreRemoveSet => 'Setni olib tashlash';

  @override
  String get scoreMoreGames => 'Koʻproq geym';

  @override
  String get scoreFewerGames => 'Kamroq geym';

  @override
  String get pastGames => 'Oʻtgan oʻyinlar';

  @override
  String get noPastGames => 'Soʻnggi 30 kunda oʻyinlar boʻlmagan';

  @override
  String get afterGameRate => 'Boshqa oʻyinchilarni baholang. Ovozlar anonim';

  @override
  String get voteUp => 'Ijobiy baho';

  @override
  String get voteDown => 'Salbiy baho';

  @override
  String get noShowAction => 'Kelmadi';

  @override
  String get reportAction => 'Shikoyat qilish';

  @override
  String reportTitle(String name) {
    return '$name ustidan shikoyat';
  }

  @override
  String get reportHint =>
      'Uni Actra administratori koʻrib chiqadi. Oʻyinchiga kim shikoyat qilgani aytilmaydi.';

  @override
  String get reportReasonLanguage => 'Haqoratli soʻzlar';

  @override
  String get reportReasonAggression => 'Tajovuzkor xatti-harakat';

  @override
  String get reportReasonFalseScore => 'Notoʻgʻri hisob';

  @override
  String get reportReasonOther => 'Boshqa';

  @override
  String get reportDetails => 'Nima boʻldi (ixtiyoriy)';

  @override
  String get reportSend => 'Yuborish';

  @override
  String get reportSent => 'Shikoyat yuborildi';

  @override
  String get errAlreadyReported =>
      'Siz bu oʻyinchi ustidan allaqachon shikoyat qilgansiz';

  @override
  String get notifNoShowRecorded =>
      'Koʻpchilik oʻyinchilar sizni oʻyinga kelmadi deb belgiladi. Ishonchliligingiz pasaydi';

  @override
  String sportsmanshipSummary(int percent, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta ovoz',
    );
    return '$percent% · $_temp0';
  }

  @override
  String get adminReview => 'Tekshiruv';

  @override
  String adminReviewOpen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ochiq: $count ta',
      zero: 'Hech narsa kutmayapti',
    );
    return '$_temp0';
  }

  @override
  String reviewScoresTab(int count) {
    return 'Hisoblar · $count';
  }

  @override
  String reviewReportsTab(int count) {
    return 'Shikoyatlar · $count';
  }

  @override
  String get reviewNoScores => 'Tekshiriladigan hisob yoʻq';

  @override
  String get reviewNoReports => 'Ochiq shikoyat yoʻq';

  @override
  String reviewDisputedBy(String name, String reason) {
    return '$name eʼtiroz bildirdi: $reason';
  }

  @override
  String reviewDisputedByNoReason(String name) {
    return '$name eʼtiroz bildirdi';
  }

  @override
  String get reviewNoShowFrozen => 'Toʻxtatilgan: kelmagan';

  @override
  String get reviewFlaggedNoShow => 'Belgilangan: kelmagan';

  @override
  String get reviewConfirm => 'Tasdiqlash';

  @override
  String get reviewCorrect => 'Tuzatish';

  @override
  String get reviewVoid => 'Bekor qilish';

  @override
  String get reviewKeep => 'Qoldirish';

  @override
  String get reviewClose => 'Yopish';

  @override
  String get reviewVoidScore => 'Hisobni bekor qilish';

  @override
  String get reviewConfirmTitle => 'Bu hisob tasdiqlansinmi?';

  @override
  String get reviewConfirmMsg =>
      'Hisob kiritilganidek hisoblanadi: reytinglar oʻzgaradi, oʻyinchilarga xabar yuboriladi.';

  @override
  String get reviewVoidTitle => 'Bu hisob bekor qilinsinmi?';

  @override
  String get reviewVoidMsg =>
      'Natija butunlay bekor qilinadi. Reyting oʻzgarishlari qaytariladi, oʻyinchilarga xabar yuboriladi.';

  @override
  String get reviewKeepTitle => 'Bu hisob qoldirilsinmi?';

  @override
  String get reviewKeepMsg => 'U oʻzgarishsiz qoladi va bu roʻyxatdan chiqadi.';

  @override
  String get reviewCorrectTitle => 'Hisobni tuzatish';

  @override
  String get reviewCorrectHint =>
      'Toʻgʻri setlarni kiriting. Reytinglar shu hisob boʻyicha oʻzgaradi, oʻyinchilarga xabar yuboriladi.';

  @override
  String get reviewCloseTitle => 'Shikoyatni yopish';

  @override
  String get reviewNote => 'Izoh (ixtiyoriy)';

  @override
  String reviewReportLine(String reporter, String target) {
    return '$reporter — $target haqida shikoyat';
  }

  @override
  String reviewScoreLine(String sets) {
    return 'Hisob: $sets';
  }

  @override
  String errTeamLimit(int max) {
    return 'Siz sardor sifatida koʻpi bilan $max ta jamoa yarata olasiz';
  }

  @override
  String get errCaptainCannotLeave =>
      'Chiqishdan oldin sardorlikni jamoadagi boshqa oʻyinchiga topshiring';

  @override
  String get errTeamNameTaken =>
      'Bu shahar va sport turida shu nomli jamoa allaqachon bor';

  @override
  String notifTeamInvite(String actor, String team) {
    return '$actor sizni «$team» jamoasiga taklif qildi';
  }

  @override
  String notifTeamJoinRequest(String actor, String team) {
    return '$actor «$team» jamoasiga qoʻshilmoqchi';
  }

  @override
  String notifTeamJoinApproved(String team) {
    return 'Endi siz «$team» jamoasidasiz';
  }

  @override
  String notifTeamJoinDeclined(String team) {
    return '«$team» jamoasiga soʻrovingiz rad etildi';
  }

  @override
  String notifTeamRemoved(String team) {
    return 'Sardor sizni «$team» jamoasidan chiqardi';
  }

  @override
  String notifTeamCaptain(String team) {
    return 'Endi siz «$team» jamoasining sardorisiz';
  }

  @override
  String notifTeamDeleted(String team) {
    return '«$team» jamoasi oʻchirildi';
  }

  @override
  String get myTeams => 'Mening jamoalarim';

  @override
  String get noMyTeams => 'Siz hali hech qaysi jamoada emassiz';

  @override
  String teamsInCity(String city) {
    return 'Jamoalar · $city';
  }

  @override
  String get noTeamsForMySports =>
      'Bu shaharda sizning sport turlaringiz boʻyicha jamoalar hali yoʻq';

  @override
  String get showAllTeams => 'Hammasini koʻrsatish';

  @override
  String get showMySportsTeams => 'Faqat mening sport turlarim';

  @override
  String get createTeam => 'Jamoa yaratish';

  @override
  String get teamOpen => 'Ochiq';

  @override
  String get teamByApproval => 'Tasdiqlash orqali';

  @override
  String get teamJoin => 'Jamoaga qoʻshilish';

  @override
  String get teamRequestJoin => 'Ariza yuborish';

  @override
  String get teamRequestSent => 'Arizangiz sardor qarorini kutmoqda';

  @override
  String get teamCancelRequest => 'Arizani qaytarib olish';

  @override
  String get teamInvited => 'Sizni bu jamoaga taklif qilishdi';

  @override
  String get teamAcceptInvite => 'Taklifni qabul qilish';

  @override
  String get teamLeave => 'Jamoadan chiqish';

  @override
  String teamLeaveConfirm(String team) {
    return '«$team» jamoasidan chiqasizmi?';
  }

  @override
  String get teamHandoverTitle => 'Yangi sardorni tanlang';

  @override
  String get teamHandoverText =>
      'Sardorlikni aʼzolardan biriga topshiring, shundan soʻng jamoadan chiqasiz.';

  @override
  String get teamHandoverEmpty =>
      'Jamoada boshqa hech kim yoʻq. Uning oʻrniga jamoani oʻchirishingiz mumkin.';

  @override
  String get teamDelete => 'Jamoani oʻchirish';

  @override
  String get teamCaptain => 'Sardor';

  @override
  String get teamMembersTitle => 'Aʼzolar';

  @override
  String get teamRequestsTitle => 'Qoʻshilish arizalari';

  @override
  String get teamMakeCaptain => 'Sardor qilish';

  @override
  String teamMakeCaptainConfirm(String name) {
    return '$name sardor boʻlsinmi?';
  }

  @override
  String get teamMakeCaptainMsg => 'Siz jamoada aʼzo sifatida qolasiz.';

  @override
  String get teamRemoveMember => 'Jamoadan chiqarish';

  @override
  String teamRemoveConfirm(String name) {
    return '$name jamoadan chiqarilsinmi?';
  }

  @override
  String get teamRemove => 'Chiqarish';

  @override
  String get teamNew => 'Yangi jamoa';

  @override
  String get teamEditTitle => 'Jamoani tahrirlash';

  @override
  String get teamChooseSport => 'Sport turini tanlang';

  @override
  String teamNameHelp(int min, int max) {
    return '$min dan $max gacha belgi';
  }

  @override
  String get teamFixedHint =>
      'Jamoa yaratilgandan soʻng sport turi va shaharni oʻzgartirib boʻlmaydi.';

  @override
  String get teamPolicyTitle => 'Kim qoʻshila oladi';

  @override
  String get teamPolicyOpenHint => 'Istalgan kishi darhol qoʻshila oladi';

  @override
  String get teamPolicyApprovalHint => 'Sardor har bir arizani tasdiqlaydi';

  @override
  String get inviteToTeam => 'Jamoaga taklif qilish';

  @override
  String get chooseTeamToInvite => 'Jamoani tanlang';

  @override
  String get noTeamsToInvite => 'Taklif qilish uchun jamoangiz yoʻq';

  @override
  String get profileTeams => 'Jamoalar';

  @override
  String reviewTeamsTab(int count) {
    return 'Jamoalar · $count';
  }

  @override
  String get reviewNoTeams => 'Jamoalar yoʻq';

  @override
  String get whoCanJoin => 'Kim qoʻshila oladi';

  @override
  String teamGameChoice(String team) {
    return 'Jamoa: $team';
  }

  @override
  String get openToEveryoneLabel => 'Joy qolsa, hammaga ochish';

  @override
  String get openNever => 'Hech qachon';

  @override
  String openHoursBefore(int hours) {
    return '$hours soat oldin';
  }

  @override
  String get teamUpcomingGamesTitle => 'Yaqin oʻyinlar';

  @override
  String get teamPostGame => 'Oʻyin eʼlon qilish';

  @override
  String get teamNoGames => 'Jamoaning yaqin oʻyinlari yoʻq';

  @override
  String teamGameOpens(String when) {
    return 'Hammaga ochiladi · $when';
  }

  @override
  String notifTeamGamePosted(String team) {
    return '«$team» jamoasi uchun yangi oʻyin';
  }

  @override
  String teamHandoverConfirm(String name) {
    return 'Sardorlikni ${name}ga topshirib, jamoadan chiqasizmi?';
  }

  @override
  String get teamHandoverLeaveFailed =>
      'Sardorlik topshirildi, lekin jamoadan chiqib boʻlmadi. Qayta urinish uchun «Jamoadan chiqish» tugmasini bosing.';

  @override
  String teamPlaysIn(String city) {
    return 'Bu jamoa $city shahrida oʻynaydi';
  }

  @override
  String get errAlreadyInTeam => 'Siz allaqachon shu jamoadasiz';

  @override
  String get errAlreadyAskedTeam =>
      'Siz bu jamoaga allaqachon soʻrov yuborgansiz';

  @override
  String get errCaptainOnly => 'Buni faqat sardor qila oladi';

  @override
  String get errWindowClosed => 'Buning vaqti oʻtib ketdi';

  @override
  String get auditScoreConfirm => 'Hisob tasdiqlandi';

  @override
  String get auditScoreCorrect => 'Hisob tuzatildi';

  @override
  String get auditScoreVoid => 'Hisob bekor qilindi';

  @override
  String get auditScoreKeep => 'Hisob kuchda qoldirildi';

  @override
  String get auditReportClosed => 'Shikoyat yopildi';

  @override
  String get auditTeamDeleted => 'Jamoa oʻchirildi';

  @override
  String get reviewCloseReport => 'Shikoyatni yopish';
}
