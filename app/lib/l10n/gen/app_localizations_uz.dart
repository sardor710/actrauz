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
  String get currencyUzs => 'soʻm';

  @override
  String get currencyKzt => '₸';
}
