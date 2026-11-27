import '../../core/localized_text.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/tournaments.dart';

/// Fictional sample content used until the backend is connected.

const kSampleSports = <Sport>[
  Sport(
    id: 'football',
    name: LocalizedText(uz: 'Futbol', ru: 'Футбол', kk: 'Футбол', en: 'Football'),
    iconKey: 'football',
    defaultPlayers: 10,
  ),
  Sport(
    id: 'padel',
    name: LocalizedText(uz: 'Padel', ru: 'Падел', kk: 'Падел', en: 'Padel'),
    iconKey: 'padel',
    competitiveRating: true,
    defaultPlayers: 4,
  ),
  Sport(
    id: 'tennis',
    name: LocalizedText(uz: 'Tennis', ru: 'Теннис', kk: 'Теннис', en: 'Tennis'),
    iconKey: 'tennis',
    competitiveRating: true,
    defaultPlayers: 2,
  ),
  Sport(
    id: 'basketball',
    name: LocalizedText(uz: 'Basketbol', ru: 'Баскетбол', kk: 'Баскетбол', en: 'Basketball'),
    iconKey: 'basketball',
    defaultPlayers: 10,
  ),
  Sport(
    id: 'volleyball',
    name: LocalizedText(uz: 'Voleybol', ru: 'Волейбол', kk: 'Волейбол', en: 'Volleyball'),
    iconKey: 'volleyball',
    defaultPlayers: 12,
  ),
  Sport(
    id: 'running',
    name: LocalizedText(uz: 'Yugurish', ru: 'Бег', kk: 'Жүгіру', en: 'Running'),
    iconKey: 'running',
    bookable: false,
    defaultPlayers: 4,
  ),
  Sport(
    id: 'gym',
    name: LocalizedText(uz: 'Sport zali', ru: 'Тренажёрный зал', kk: 'Жаттығу залы', en: 'Gym'),
    iconKey: 'gym',
    bookable: false,
    defaultPlayers: 2,
  ),
];

const _weekdays = {1, 2, 3, 4, 5};
const _weekend = {6, 7};

List<PriceRule> _rules({required int evening, int? weekend}) => [
  PriceRule(weekdays: _weekdays, fromMinute: 18 * 60, toMinute: 24 * 60, price: evening),
  if (weekend != null) PriceRule(weekdays: _weekend, fromMinute: 0, toMinute: 24 * 60, price: weekend),
];

final kSampleVenues = <Venue>[
  Venue(
    id: 'v1',
    cityId: 'tashkent',
    name: const LocalizedText.all('Lochin Padel Club'),
    description: const LocalizedText(
      uz: 'Ikki yopiq padel korti, panoramali oynalar va professional yoritish.',
      ru: 'Два крытых падел-корта с панорамным стеклом и профессиональным освещением.',
      en: 'Two indoor padel courts with panoramic glass and professional lighting.',
    ),
    address: const LocalizedText(
      uz: 'Bogʻishamol koʻchasi, 12',
      ru: 'улица Богишамол, 12',
      en: '12 Bogishamol Street',
    ),
    district: const LocalizedText(uz: 'Yunusobod', ru: 'Юнусабад', en: 'Yunusabad'),
    phone: '+998 71 200 00 01',
    hours: weekHours(weekdays: const DayHours.hm(7, 0, 23, 0), weekend: const DayHours.hm(7, 0, 23, 0)),
    amenities: const ['parking', 'showers', 'lighting', 'rental'],
    colorSeed: 0,
    courts: [
      Court(
        id: 'v1c1',
        venueId: 'v1',
        sportId: 'padel',
        name: const LocalizedText(uz: 'Kort 1', ru: 'Корт 1', en: 'Court 1'),
        slotMinutes: 90,
        basePrice: 180000,
        priceRules: _rules(evening: 250000, weekend: 300000),
        indoor: true,
      ),
      Court(
        id: 'v1c2',
        venueId: 'v1',
        sportId: 'padel',
        name: const LocalizedText(uz: 'Kort 2', ru: 'Корт 2', en: 'Court 2'),
        slotMinutes: 90,
        basePrice: 180000,
        priceRules: _rules(evening: 250000, weekend: 300000),
        indoor: true,
      ),
    ],
  ),
  Venue(
    id: 'v2',
    cityId: 'tashkent',
    name: const LocalizedText.all('Bunyod Football Park'),
    description: const LocalizedText(
      uz: 'Sunʼiy qoplamali ikki maydon: 5×5 va 7×7. Kechki oʻyinlar uchun yoritish bor.',
      ru: 'Два поля с искусственным покрытием: 5×5 и 7×7. Есть освещение для вечерних игр.',
      en: 'Two artificial-turf pitches: 5-a-side and 7-a-side, with floodlights for evening games.',
    ),
    address: const LocalizedText(uz: 'Qatortol koʻchasi, 48', ru: 'улица Катартал, 48', en: '48 Qatortol Street'),
    district: const LocalizedText(uz: 'Chilonzor', ru: 'Чиланзар', en: 'Chilanzar'),
    phone: '+998 71 200 00 02',
    hours: weekHours(weekdays: const DayHours.hm(8, 0, 24, 0), weekend: const DayHours.hm(9, 0, 23, 0)),
    amenities: const ['parking', 'lighting', 'cafe'],
    colorSeed: 1,
    courts: [
      Court(
        id: 'v2c1',
        venueId: 'v2',
        sportId: 'football',
        name: const LocalizedText(uz: 'Maydon 5×5', ru: 'Поле 5×5', en: 'Pitch 5×5'),
        slotMinutes: 60,
        basePrice: 250000,
        priceRules: _rules(evening: 350000),
      ),
      Court(
        id: 'v2c2',
        venueId: 'v2',
        sportId: 'football',
        name: const LocalizedText(uz: 'Maydon 7×7', ru: 'Поле 7×7', en: 'Pitch 7×7'),
        slotMinutes: 60,
        basePrice: 400000,
        priceRules: _rules(evening: 520000),
      ),
    ],
  ),
  Venue(
    id: 'v3',
    cityId: 'tashkent',
    name: const LocalizedText.all('Semurg Tennis Centre'),
    description: const LocalizedText(
      uz: 'Ochiq tennis kortlari va basketbol maydonchasi. Ertalabki mashgʻulotlar uchun qulay.',
      ru: 'Открытые теннисные корты и баскетбольная площадка. Удобно для утренних тренировок.',
      en: 'Outdoor tennis courts and a basketball court. Good for early-morning sessions.',
    ),
    address: const LocalizedText(uz: 'Buyuk Ipak Yoʻli koʻchasi, 105', ru: 'улица Буюк Ипак Йули, 105', en: '105 Buyuk Ipak Yoli Street'),
    district: const LocalizedText(uz: 'Mirzo Ulugʻbek', ru: 'Мирзо-Улугбек', en: 'Mirzo Ulugbek'),
    phone: '+998 71 200 00 03',
    hours: weekHours(weekdays: const DayHours.hm(6, 30, 22, 30), weekend: const DayHours.hm(6, 30, 22, 30)),
    amenities: const ['showers', 'rental', 'cafe'],
    colorSeed: 2,
    courts: [
      Court(
        id: 'v3c1',
        venueId: 'v3',
        sportId: 'tennis',
        name: const LocalizedText(uz: 'Kort A', ru: 'Корт A', en: 'Court A'),
        slotMinutes: 60,
        basePrice: 120000,
        priceRules: _rules(evening: 160000),
      ),
      Court(
        id: 'v3c2',
        venueId: 'v3',
        sportId: 'tennis',
        name: const LocalizedText(uz: 'Kort B', ru: 'Корт B', en: 'Court B'),
        slotMinutes: 60,
        basePrice: 120000,
        priceRules: _rules(evening: 160000),
      ),
      // Closed on Mondays although the venue is open.
      const Court(
        id: 'v3c3',
        venueId: 'v3',
        sportId: 'basketball',
        name: LocalizedText(uz: 'Basketbol maydonchasi', ru: 'Баскетбольная площадка', en: 'Basketball court'),
        slotMinutes: 60,
        basePrice: 200000,
        hoursOverride: {1: null},
      ),
    ],
  ),
  Venue(
    id: 'v4',
    cityId: 'almaty',
    name: const LocalizedText.all('Alatau Padel & Tennis'),
    description: const LocalizedText(
      uz: 'Togʻ manzarali padel va tennis kortlari.',
      ru: 'Падел и теннисные корты с видом на горы.',
      en: 'Padel and tennis courts with a mountain view.',
    ),
    address: const LocalizedText(uz: 'Timiryazev koʻchasi, 42', ru: 'улица Тимирязева, 42', en: '42 Timiryazev Street'),
    district: const LocalizedText(uz: 'Bostandiq', ru: 'Бостандыкский район', en: 'Bostandyk'),
    phone: '+7 727 200 00 04',
    hours: weekHours(weekdays: const DayHours.hm(7, 0, 23, 0), weekend: const DayHours.hm(7, 0, 23, 0)),
    amenities: const ['parking', 'showers', 'lighting', 'rental', 'cafe'],
    colorSeed: 3,
    courts: [
      Court(
        id: 'v4c1',
        venueId: 'v4',
        sportId: 'padel',
        name: const LocalizedText(uz: 'Padel korti', ru: 'Падел-корт', en: 'Padel court'),
        slotMinutes: 90,
        basePrice: 12000,
        priceRules: _rules(evening: 16000, weekend: 18000),
        indoor: true,
      ),
      Court(
        id: 'v4c2',
        venueId: 'v4',
        sportId: 'tennis',
        name: const LocalizedText(uz: 'Tennis korti', ru: 'Теннисный корт', en: 'Tennis court'),
        slotMinutes: 60,
        basePrice: 8000,
        priceRules: _rules(evening: 11000),
      ),
    ],
  ),
  Venue(
    id: 'v5',
    cityId: 'almaty',
    name: const LocalizedText.all('Zhetisu Arena'),
    description: const LocalizedText(
      uz: 'Futbol va voleybol uchun yopiq zal. Yakshanba kuni dam olish kuni.',
      ru: 'Крытый зал для футбола и волейбола. Воскресенье — выходной.',
      en: 'Indoor hall for football and volleyball. Closed on Sundays.',
    ),
    address: const LocalizedText(uz: 'Dostiq shoh koʻchasi, 210', ru: 'проспект Достык, 210', en: '210 Dostyk Avenue'),
    district: const LocalizedText(uz: 'Medeu', ru: 'Медеуский район', en: 'Medeu'),
    phone: '+7 727 200 00 05',
    hours: const {
      1: DayHours.hm(8, 0, 22, 0),
      2: DayHours.hm(8, 0, 22, 0),
      3: DayHours.hm(8, 0, 22, 0),
      4: DayHours.hm(8, 0, 22, 0),
      5: DayHours.hm(8, 0, 22, 0),
      6: DayHours.hm(9, 0, 20, 0),
      7: null,
    },
    amenities: const ['parking', 'showers'],
    colorSeed: 4,
    courts: [
      Court(
        id: 'v5c1',
        venueId: 'v5',
        sportId: 'football',
        name: const LocalizedText(uz: 'Futbol zali', ru: 'Футбольный зал', en: 'Football hall'),
        slotMinutes: 60,
        basePrice: 15000,
        priceRules: _rules(evening: 20000),
        indoor: true,
      ),
      const Court(
        id: 'v5c2',
        venueId: 'v5',
        sportId: 'volleyball',
        name: LocalizedText(uz: 'Voleybol zali', ru: 'Волейбольный зал', en: 'Volleyball hall'),
        slotMinutes: 60,
        basePrice: 9000,
        indoor: true,
      ),
    ],
  ),
  Venue(
    id: 'v6',
    cityId: 'astana',
    name: const LocalizedText.all('Esil Sport Hub'),
    description: const LocalizedText(
      uz: 'Yil boʻyi ishlaydigan yopiq majmua: futbol, basketbol va padel.',
      ru: 'Крытый комплекс, работающий круглый год: футбол, баскетбол и падел.',
      en: 'Indoor complex open all year: football, basketball and padel.',
    ),
    address: const LocalizedText(uz: 'Qabanbay botir shoh koʻchasi, 60', ru: 'проспект Кабанбай батыра, 60', en: '60 Kabanbay Batyr Avenue'),
    district: const LocalizedText(uz: 'Esil', ru: 'район Есиль', en: 'Esil'),
    phone: '+7 7172 20 00 06',
    hours: weekHours(weekdays: const DayHours.hm(8, 0, 23, 0), weekend: const DayHours.hm(8, 0, 23, 0)),
    amenities: const ['parking', 'showers', 'lighting', 'cafe'],
    colorSeed: 5,
    courts: [
      Court(
        id: 'v6c1',
        venueId: 'v6',
        sportId: 'football',
        name: const LocalizedText(uz: 'Futbol maydoni', ru: 'Футбольное поле', en: 'Football pitch'),
        slotMinutes: 60,
        basePrice: 14000,
        priceRules: _rules(evening: 19000),
        indoor: true,
      ),
      const Court(
        id: 'v6c2',
        venueId: 'v6',
        sportId: 'basketball',
        name: LocalizedText(uz: 'Basketbol zali', ru: 'Баскетбольный зал', en: 'Basketball hall'),
        slotMinutes: 60,
        basePrice: 10000,
        indoor: true,
      ),
      Court(
        id: 'v6c3',
        venueId: 'v6',
        sportId: 'padel',
        name: const LocalizedText(uz: 'Padel korti', ru: 'Падел-корт', en: 'Padel court'),
        slotMinutes: 90,
        basePrice: 13000,
        priceRules: _rules(evening: 17000),
        indoor: true,
      ),
    ],
  ),
];

/// The signed-in player in sample mode.
const kMeId = 'me';

/// Venues the signed-in demo player manages as an owner in sample mode.
const kSampleOwnedVenueIds = {'v1', 'v4', 'v6'};

/// In padel and tennis each sample player has a rating of their level plus
/// 0.5, established by 12 rated games (Dilnoza is still provisional with 4);
/// the level is the one derived from it.
const kSamplePlayers = <Player>[
  Player(
    id: 'p1',
    name: 'Aziz',
    levels: {'padel': 3, 'football': 3},
    ratings: {'padel': SportRating(rating: 3.5, ratedGames: 12)},
  ),
  Player(
    id: 'p2',
    name: 'Dilnoza',
    levels: {'padel': 2, 'tennis': 3},
    ratings: {'padel': SportRating(rating: 2.5, ratedGames: 4), 'tennis': SportRating(rating: 3.5, ratedGames: 4)},
  ),
  Player(id: 'p3', name: 'Timur', levels: {'football': 4}),
  Player(
    id: 'p4',
    name: 'Madina',
    levels: {'tennis': 4},
    ratings: {'tennis': SportRating(rating: 4.5, ratedGames: 12)},
  ),
  Player(
    id: 'p5',
    name: 'Arman',
    levels: {'padel': 3},
    ratings: {'padel': SportRating(rating: 3.5, ratedGames: 12)},
  ),
  Player(id: 'p6', name: 'Aigerim', levels: {'football': 2}),
  Player(
    id: 'p7',
    name: 'Bekzod',
    levels: {'football': 3, 'padel': 4},
    ratings: {'padel': SportRating(rating: 4.5, ratedGames: 12)},
  ),
  Player(
    id: 'p8',
    name: 'Kamila',
    levels: {'padel': 3, 'tennis': 2},
    ratings: {'padel': SportRating(rating: 3.5, ratedGames: 12), 'tennis': SportRating(rating: 2.5, ratedGames: 12)},
  ),
];

/// A sample game, placed relative to "today" when the sample backend starts.
class GameSeed {
  const GameSeed({
    required this.id,
    required this.venueId,
    required this.courtId,
    required this.daysAhead,
    required this.hour,
    required this.minute,
    required this.spots,
    required this.participantIds,
    this.minLevel = 1,
    this.maxLevel = 5,
  });

  final String id;
  final String venueId;
  final String courtId;
  final int daysAhead;
  final int hour;
  final int minute;
  final int spots;

  /// The first one is the host.
  final List<String> participantIds;
  final int minLevel;
  final int maxLevel;
}

const kGameSeeds = <GameSeed>[
  GameSeed(
    id: 'g1',
    venueId: 'v1',
    courtId: 'v1c1',
    daysAhead: 1,
    hour: 19,
    minute: 0,
    spots: 4,
    participantIds: ['p1', 'p2'],
    minLevel: 2,
    maxLevel: 4,
  ),
  GameSeed(
    id: 'g2',
    venueId: 'v2',
    courtId: 'v2c1',
    daysAhead: 1,
    hour: 20,
    minute: 0,
    spots: 10,
    participantIds: ['p3', 'p1', 'p6', 'p7', 'p5', 'p8', 'p2'],
  ),
  GameSeed(
    id: 'g3',
    venueId: 'v3',
    courtId: 'v3c1',
    daysAhead: 2,
    hour: 18,
    minute: 30,
    spots: 2,
    participantIds: ['p4'],
    minLevel: 3,
    maxLevel: 5,
  ),
  GameSeed(
    id: 'g4',
    venueId: 'v1',
    courtId: 'v1c2',
    daysAhead: 2,
    hour: 19,
    minute: 0,
    spots: 4,
    participantIds: ['p7', 'p5', 'p8', 'p1'],
    minLevel: 3,
    maxLevel: 5,
  ),
  GameSeed(
    id: 'g5',
    venueId: 'v4',
    courtId: 'v4c1',
    daysAhead: 1,
    hour: 17,
    minute: 30,
    spots: 4,
    participantIds: ['p5', 'p8', 'p2'],
    minLevel: 2,
    maxLevel: 4,
  ),
  GameSeed(
    id: 'g6',
    venueId: 'v6',
    courtId: 'v6c1',
    daysAhead: 1,
    hour: 21,
    minute: 0,
    spots: 10,
    participantIds: ['p6', 'p3', 'p1', 'p7', 'p4'],
  ),
];

/// A padel game that was played yesterday, placed relative to the day the
/// sample backend starts, so the score and past-games screens have something
/// to show. Sample mode only: a game in the past cannot be booked, so these
/// are not in `supabase/seed.sql`.
class FinishedGameSeed {
  const FinishedGameSeed({
    required this.id,
    required this.venueId,
    required this.courtId,
    required this.hour,
    required this.minute,
    required this.participantIds,
    this.result,
  });

  final String id;
  final String venueId;
  final String courtId;

  /// Start, yesterday in venue time; it lasts one slot of the court.
  final int hour;
  final int minute;

  /// The first one is the host.
  final List<String> participantIds;

  /// A pending score already entered, or none.
  final ResultSeed? result;
}

/// A pending score of a [FinishedGameSeed], entered [hoursAgo] hours before
/// the sample backend starts (so it is still waiting for confirmation).
class ResultSeed {
  const ResultSeed({
    required this.enteredBy,
    required this.sideA,
    required this.sideB,
    required this.sets,
    required this.hoursAgo,
  });

  final String enteredBy;
  final List<String> sideA;
  final List<String> sideB;
  final List<(int, int)> sets;
  final int hoursAgo;
}

const kFinishedGameSeeds = <FinishedGameSeed>[
  // The demo player hosted it; nobody has entered the score yet.
  FinishedGameSeed(
    id: 'gf1',
    venueId: 'v1',
    courtId: 'v1c1',
    hour: 18,
    minute: 0,
    participantIds: [kMeId, 'p1', 'p2', 'p3'],
  ),
  // Aziz hosted it and entered the score; the demo player, on the other side,
  // can confirm or dispute it.
  FinishedGameSeed(
    id: 'gf2',
    venueId: 'v1',
    courtId: 'v1c2',
    hour: 19,
    minute: 30,
    participantIds: ['p1', kMeId, 'p2', 'p3'],
    result: ResultSeed(
      enteredBy: 'p1',
      sideA: ['p1', 'p3'],
      sideB: [kMeId, 'p2'],
      sets: [(6, 3), (6, 4)],
      hoursAgo: 1,
    ),
  ),
];

const kSampleBanners = <BannerItem>[
  BannerItem(
    id: 'bn1',
    title: LocalizedText(uz: 'Onlayn band qiling, joyida toʻlang', ru: 'Бронируйте онлайн, платите на месте', en: 'Book online, pay at the venue'),
    subtitle: LocalizedText(uz: 'Boʻsh vaqtlar real vaqtda koʻrinadi', ru: 'Свободное время видно сразу', en: 'See free times instantly'),
    url: 'https://example.com/actra/how-it-works',
    colorSeed: 0,
  ),
  BannerItem(
    id: 'bn2',
    title: LocalizedText(uz: 'Sherik topilmayaptimi?', ru: 'Не с кем играть?', en: 'Nobody to play with?'),
    subtitle: LocalizedText(uz: 'Oʻz darajangizdagi oʻyinga qoʻshiling', ru: 'Присоединяйтесь к игре своего уровня', en: 'Join a game at your level'),
    url: 'https://example.com/actra/games',
    colorSeed: 3,
  ),
];

/// A sample category. `taken` entries are already in it, held by players the
/// sample data does not name; the demo player and the sample players register
/// on top of them.
class CategorySeed {
  const CategorySeed({
    required this.id,
    required this.name,
    required this.kind,
    required this.cap,
    required this.taken,
    required this.fee,
    this.gender = CategoryGender.open,
    this.minLevel = 1,
    this.maxLevel = 5,
    this.waitlistEnabled = true,
  });

  final String id;
  final LocalizedText name;
  final CategoryKind kind;
  final int cap;
  final int taken;
  final int fee;
  final CategoryGender gender;
  final int minLevel;
  final int maxLevel;
  final bool waitlistEnabled;
}

/// A sample tournament, placed relative to "today". Its first category is the
/// one the seed gives the id `md5('actra:default-category:' || tournament id)`
/// (see `tool/seed_sql.dart`), so a seed run updates the category the
/// tournaments migration created instead of adding a second.
class TournamentSeed {
  const TournamentSeed({
    required this.id,
    required this.venueId,
    required this.sportId,
    required this.title,
    required this.daysAhead,
    required this.days,
    required this.categories,
    this.deadlineDaysBefore = 2,
  });

  final String id;
  final String venueId;
  final String sportId;
  final LocalizedText title;
  final int daysAhead;
  final int days;
  final List<CategorySeed> categories;

  /// Registration closes this many days before the first day, at 18:00.
  final int deadlineDaysBefore;
}

const kTournamentSeeds = <TournamentSeed>[
  TournamentSeed(
    id: 't1',
    venueId: 'v1',
    sportId: 'padel',
    title: LocalizedText(uz: 'Toshkent Padel Kubogi', ru: 'Кубок Ташкента по паделу', en: 'Tashkent Padel Cup'),
    daysAhead: 12,
    days: 2,
    categories: [
      CategorySeed(
        id: 't1c1',
        name: LocalizedText(uz: 'Ochiq juftliklar', ru: 'Открытые пары', en: 'Open pairs'),
        kind: CategoryKind.pairs,
        cap: 12,
        taken: 9,
        fee: 300000,
      ),
      CategorySeed(
        id: 't1c2',
        name: LocalizedText(uz: 'Erkaklar juftliklari', ru: 'Мужские пары', en: "Men's pairs"),
        kind: CategoryKind.pairs,
        gender: CategoryGender.men,
        minLevel: 3,
        cap: 8,
        taken: 8,
        fee: 500000,
      ),
      CategorySeed(
        id: 't1c3',
        name: LocalizedText(uz: 'Aralash juftliklar', ru: 'Смешанные пары', en: 'Mixed pairs'),
        kind: CategoryKind.pairs,
        gender: CategoryGender.mixed,
        minLevel: 2,
        maxLevel: 4,
        cap: 12,
        taken: 2,
        fee: 400000,
      ),
    ],
  ),
  TournamentSeed(
    id: 't2',
    venueId: 'v2',
    sportId: 'football',
    title: LocalizedText(uz: 'Havaskorlar ligasi 5×5', ru: 'Любительская лига 5×5', en: 'Amateur 5-a-side League'),
    daysAhead: 20,
    days: 1,
    categories: [
      CategorySeed(
        id: 't2c1',
        name: LocalizedText(uz: 'Ochiq', ru: 'Открытая', en: 'Open'),
        kind: CategoryKind.singles,
        cap: 12,
        taken: 12,
        fee: 800000,
      ),
    ],
  ),
  TournamentSeed(
    id: 't3',
    venueId: 'v4',
    sportId: 'tennis',
    title: LocalizedText(uz: 'Olmaota ochiq tennis turniri', ru: 'Открытый теннисный турнир Алматы', en: 'Almaty Open Tennis'),
    daysAhead: 15,
    days: 3,
    categories: [
      CategorySeed(
        id: 't3c1',
        name: LocalizedText(uz: 'Ochiq, yakkalik', ru: 'Открытая, одиночный', en: 'Open singles'),
        kind: CategoryKind.singles,
        cap: 16,
        taken: 5,
        fee: 15000,
      ),
      CategorySeed(
        id: 't3c2',
        name: LocalizedText(uz: 'Erkaklar, yakkalik', ru: 'Мужчины, одиночный', en: "Men's singles"),
        kind: CategoryKind.singles,
        gender: CategoryGender.men,
        minLevel: 3,
        cap: 8,
        taken: 4,
        fee: 25000,
      ),
    ],
  ),
];

/// Phone numbers of the sample players, for "find a partner by phone" in the
/// demo. Fictional.
const kSamplePlayerPhones = <String, String>{
  'p1': '+998901000001',
  'p2': '+998901000002',
  'p3': '+998901000003',
  'p4': '+77011000004',
  'p5': '+998901000005',
  'p6': '+998901000006',
  'p7': '+998901000007',
  'p8': '+77011000008',
};

/// A sample Game Request ("looking for players"), placed relative to "today".
class RequestSeed {
  const RequestSeed({
    required this.id,
    required this.cityId,
    required this.sportId,
    required this.hostId,
    required this.daysAhead,
    required this.fromHour,
    required this.toHour,
    required this.playersNeeded,
    required this.interestedIds,
    this.area,
    this.minLevel = 1,
    this.maxLevel = 5,
    this.note,
  });

  final String id;
  final String cityId;
  final String sportId;
  final String hostId;
  final int daysAhead;
  final int fromHour;
  final int toHour;
  final int playersNeeded;

  /// In the order they tapped "I'm in".
  final List<String> interestedIds;
  final String? area;
  final int minLevel;
  final int maxLevel;
  final String? note;
}

const kRequestSeeds = <RequestSeed>[
  RequestSeed(
    id: 'rq1',
    cityId: 'tashkent',
    sportId: 'padel',
    hostId: 'p1',
    daysAhead: 1,
    fromHour: 18,
    toHour: 21,
    playersNeeded: 2,
    interestedIds: ['p5'],
    area: 'Yunusobod',
    minLevel: 2,
    maxLevel: 4,
    note: 'Any evening court is fine',
  ),
  RequestSeed(
    id: 'rq2',
    cityId: 'tashkent',
    sportId: 'running',
    hostId: 'p6',
    daysAhead: 2,
    fromHour: 7,
    toHour: 9,
    playersNeeded: 4,
    interestedIds: ['p3', 'p7'],
    area: 'Bunyodkor park',
  ),
  RequestSeed(
    id: 'rq3',
    cityId: 'almaty',
    sportId: 'tennis',
    hostId: 'p4',
    daysAhead: 1,
    fromHour: 17,
    toHour: 20,
    playersNeeded: 1,
    interestedIds: [],
    area: 'Bostandyk',
    minLevel: 3,
  ),
];

/// An inbox entry the demo player starts with, placed relative to "now".
class NotificationSeed {
  const NotificationSeed({
    required this.id,
    required this.kind,
    required this.category,
    required this.payload,
    required this.hoursAgo,
    required this.read,
  });

  final String id;
  final String kind;
  final String category;
  final Map<String, Object?> payload;
  final int hoursAgo;
  final bool read;
}

const kNotificationSeeds = <NotificationSeed>[
  NotificationSeed(
    id: 'ns1',
    kind: 'booking_confirmed',
    category: 'bookings',
    payload: {
      'booking_id': 'sample',
      'sport_id': 'padel',
      'venue_name': {'uz': 'Lochin Padel Club', 'ru': 'Lochin Padel Club', 'en': 'Lochin Padel Club'},
    },
    hoursAgo: 30,
    read: true,
  ),
  // The demo player manages Lochin Padel Club.
  NotificationSeed(
    id: 'ns2',
    kind: 'venue_new_booking',
    category: 'venue',
    payload: {
      'booking_id': 'sample',
      'venue_id': 'v1',
      'sport_id': 'padel',
      'court_name': {'uz': 'Kort 1', 'ru': 'Корт 1', 'en': 'Court 1'},
      'actor_name': 'Aziz',
    },
    hoursAgo: 3,
    read: false,
  ),
];
