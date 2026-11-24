// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appName => 'Actra';

  @override
  String get continueLabel => 'Продолжить';

  @override
  String get cancel => 'Отмена';

  @override
  String get seeAll => 'Все';

  @override
  String get today => 'Сегодня';

  @override
  String get tomorrow => 'Завтра';

  @override
  String get comingSoon => 'Скоро';

  @override
  String get errGeneric => 'Что-то пошло не так. Попробуйте ещё раз.';

  @override
  String get chooseLanguage => 'Выберите язык';

  @override
  String get chooseCity => 'Выберите город';

  @override
  String get chooseCityHint => 'Город можно изменить в профиле в любой момент';

  @override
  String get signInTitle => 'Вход';

  @override
  String get signInTelegram => 'Продолжить через Telegram';

  @override
  String get demoNotice =>
      'Демо-режим: вход через Telegram появится в следующей версии. Введите имя, чтобы продолжить. Площадки, игры и турниры — примеры данных.';

  @override
  String get yourName => 'Ваше имя';

  @override
  String get nameRequired => 'Введите имя';

  @override
  String get telegramHint =>
      'Откроется Telegram. Нажмите там «Старт» и отправьте свой номер телефона — он станет вашим аккаунтом в Actra.';

  @override
  String get telegramWaiting =>
      'Ждём Telegram. Отправьте боту Actra свой номер телефона и вернитесь сюда.';

  @override
  String get telegramOpenAgain => 'Открыть Telegram ещё раз';

  @override
  String get telegramExpired =>
      'Ссылка для входа устарела. Попробуйте ещё раз.';

  @override
  String get signInFailed =>
      'Не удалось войти. Проверьте соединение и попробуйте ещё раз.';

  @override
  String get acceptTerms =>
      'Я принимаю Пользовательское соглашение и Политику конфиденциальности';

  @override
  String get termsRequired => 'Примите условия, чтобы продолжить';

  @override
  String get tabHome => 'Главная';

  @override
  String get tabVenues => 'Площадки';

  @override
  String get tabGames => 'Игры';

  @override
  String get tabProfile => 'Профиль';

  @override
  String greeting(String name) {
    return 'Привет, $name';
  }

  @override
  String get homeGames => 'Доступные игры';

  @override
  String get homeCourts => 'Свободные корты сегодня';

  @override
  String get homeTournaments => 'Турниры';

  @override
  String get noGames => 'Пока нет открытых игр';

  @override
  String get noCourtsToday => 'На сегодня свободного времени не осталось';

  @override
  String get searchVenues => 'Поиск площадок';

  @override
  String get allSports => 'Все виды спорта';

  @override
  String get noVenues => 'Площадки не найдены';

  @override
  String fromPrice(String price) {
    return 'от $price';
  }

  @override
  String slotLength(int minutes) {
    return '$minutes мин';
  }

  @override
  String get workingHours => 'Часы работы';

  @override
  String get closed => 'Закрыто';

  @override
  String get weekdays => 'Пн–Пт';

  @override
  String get saturday => 'Сб';

  @override
  String get sunday => 'Вс';

  @override
  String get amenities => 'Удобства';

  @override
  String get amenityParking => 'Парковка';

  @override
  String get amenityShowers => 'Душевые';

  @override
  String get amenityLighting => 'Освещение';

  @override
  String get amenityCafe => 'Кафе';

  @override
  String get amenityRental => 'Прокат инвентаря';

  @override
  String get courts => 'Корты';

  @override
  String get indoor => 'Крытый';

  @override
  String get outdoor => 'Открытый';

  @override
  String get book => 'Забронировать';

  @override
  String get phone => 'Телефон';

  @override
  String get address => 'Адрес';

  @override
  String get about => 'О площадке';

  @override
  String get bookingTitle => 'Выберите время';

  @override
  String get closedThatDay => 'В этот день корт закрыт';

  @override
  String get selectHint => 'Выберите один слот или несколько подряд';

  @override
  String slotsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count слота',
      many: '$count слотов',
      few: '$count слота',
      one: '$count слот',
    );
    return '$_temp0';
  }

  @override
  String get total => 'Итого';

  @override
  String get summaryTitle => 'Детали брони';

  @override
  String heldFor(String time) {
    return 'Время удерживается за вами: $time';
  }

  @override
  String get holdExpiredMsg =>
      'Время удержания истекло. Выберите время заново.';

  @override
  String get paymentMethod => 'Способ оплаты';

  @override
  String get payAtVenue => 'Оплата на месте';

  @override
  String get payAtVenueHint => 'Наличными или картой на площадке';

  @override
  String get playersCount => 'Количество игроков';

  @override
  String get noteLabel => 'Примечание (необязательно)';

  @override
  String get confirmBooking => 'Подтвердить бронь';

  @override
  String get bookingConfirmed => 'Бронь подтверждена';

  @override
  String get dateLabel => 'Дата';

  @override
  String get timeLabel => 'Время';

  @override
  String get courtLabel => 'Корт';

  @override
  String get errSlotTaken => 'Это время только что заняли. Выберите другое.';

  @override
  String get errNotContiguous => 'Слоты должны идти подряд';

  @override
  String errTooManyBookings(int count) {
    return 'У вас уже есть предстоящие брони: $count';
  }

  @override
  String errTooFarAhead(int days) {
    return 'Бронирование открывается за $days дн. до даты';
  }

  @override
  String get errInPast => 'Это время уже прошло';

  @override
  String get myBookings => 'Мои брони';

  @override
  String get noBookings => 'У вас пока нет броней';

  @override
  String get statusConfirmed => 'Подтверждена';

  @override
  String get statusCancelled => 'Отменена';

  @override
  String get statusCompleted => 'Завершена';

  @override
  String get cancelBooking => 'Отменить бронь';

  @override
  String get cancelConfirmTitle => 'Отменить эту бронь?';

  @override
  String get cancelFreeMsg => 'Отмена бесплатна.';

  @override
  String cancelLateMsg(int hours) {
    return 'До начала осталось меньше $hours ч. Это считается поздней отменой и снижает вашу надёжность.';
  }

  @override
  String get keepBooking => 'Оставить бронь';

  @override
  String get bookingCancelled => 'Бронь отменена';

  @override
  String get lateCancellation => 'Поздняя отмена';

  @override
  String spotsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Осталось $count места',
      many: 'Осталось $count мест',
      few: 'Осталось $count места',
      one: 'Осталось $count место',
      zero: 'Мест нет',
    );
    return '$_temp0';
  }

  @override
  String levelRange(int min, int max) {
    return 'Уровень $min–$max';
  }

  @override
  String perPlayer(String price) {
    return '≈ $price с игрока';
  }

  @override
  String get host => 'Организатор';

  @override
  String get players => 'Игроки';

  @override
  String get joinGame => 'Присоединиться';

  @override
  String get leaveGame => 'Выйти из игры';

  @override
  String get errGameFull => 'В этой игре уже нет мест';

  @override
  String get errLevel => 'Ваш уровень не подходит для этой игры';

  @override
  String get you => 'Вы';

  @override
  String get entryFee => 'Взнос';

  @override
  String filledOf(int filled, int total) {
    return 'Занято $filled из $total';
  }

  @override
  String get language => 'Язык';

  @override
  String get city => 'Город';

  @override
  String get signOut => 'Выйти';

  @override
  String get currencyUzs => 'сум';

  @override
  String get currencyKzt => '₸';

  @override
  String get searchHint => 'Поиск площадок и видов спорта';

  @override
  String get gamesBySports => 'Игры по видам спорта';

  @override
  String get venuesNearYou => 'Площадки рядом';

  @override
  String get tabTournaments => 'Турниры';

  @override
  String get tabSocial => 'Сообщество';

  @override
  String get allDays => 'Все';

  @override
  String get filterSport => 'Вид спорта';

  @override
  String get myLevel => 'Мой уровень';

  @override
  String going(int count, int spots) {
    return '$count/$spots идут';
  }

  @override
  String gameTitle(String host, String sport) {
    return '$sport с игроком $host';
  }

  @override
  String get createGame => 'Создать игру';

  @override
  String get gamesPromoTitle => 'Не хватает игроков?';

  @override
  String get gamesPromoText =>
      'Присоединяйтесь к игре своего уровня или соберите свою';

  @override
  String get bookable => 'Онлайн-бронь';

  @override
  String get favourites => 'Избранное';

  @override
  String get sortPrice => 'Сначала дешевле';

  @override
  String get priceStartingFrom => 'Цена от';

  @override
  String get registrationOpen => 'Регистрация открыта';

  @override
  String get tournamentFull => 'Мест нет';

  @override
  String get noTournaments => 'Турниры пока не объявлены';

  @override
  String get tournamentsPromoTitle => 'Сыграйте за кубок';

  @override
  String get tournamentsPromoText =>
      'Одиночные и парные разряды для любого уровня';

  @override
  String get discoverTeams => 'Команды рядом';

  @override
  String get noTeams => 'В этом городе пока нет команд';

  @override
  String members(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count участника',
      many: '$count участников',
      few: '$count участника',
      one: '$count участник',
    );
    return '$_temp0';
  }

  @override
  String upcomingGames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count игры скоро',
      many: '$count игр скоро',
      few: '$count игры скоро',
      one: '$count игра скоро',
    );
    return '$_temp0';
  }

  @override
  String get playersNearYou => 'Игроки рядом';

  @override
  String level(int level) {
    return 'Уровень $level';
  }

  @override
  String get inviteTitle => 'Позовите друзей';

  @override
  String get inviteText =>
      'Пригласите друзей в Actra, и игры будут собираться быстрее.';

  @override
  String get inviteCta => 'Пригласить друзей';

  @override
  String get statBookings => 'Брони';

  @override
  String get statGames => 'Игры';

  @override
  String get statLate => 'Поздние отмены';

  @override
  String get mySports => 'Мои виды спорта';

  @override
  String get morning => 'Утро';

  @override
  String get afternoon => 'День';

  @override
  String get evening => 'Вечер';

  @override
  String get everyDay => 'Ежедневно';

  @override
  String get gamesPromoCta => 'Забронировать корт';

  @override
  String get myVenues => 'Мои площадки';

  @override
  String get ownerCalendar => 'Календарь броней';

  @override
  String get noVenuesAssigned => 'Вам пока не назначены площадки';

  @override
  String get prevWeek => 'Предыдущая неделя';

  @override
  String get nextWeek => 'Следующая неделя';

  @override
  String get slotFree => 'Свободно';

  @override
  String get slotBooked => 'Занято';

  @override
  String get slotBlocked => 'Закрыто';

  @override
  String get closedThatWeek => 'На этой неделе корт закрыт';

  @override
  String get newBooking => 'Новая бронь';

  @override
  String get blockTime => 'Закрыть время';

  @override
  String get customerName => 'Имя клиента';

  @override
  String get customerNameRequired => 'Введите имя клиента';

  @override
  String get customerPhone => 'Номер телефона (необязательно)';

  @override
  String get slotsCountLabel => 'Количество слотов';

  @override
  String get payCash => 'Наличные';

  @override
  String get payCard => 'Карта';

  @override
  String get payTransfer => 'Перевод';

  @override
  String get saveBooking => 'Сохранить бронь';

  @override
  String get blockReason => 'Причина (необязательно)';

  @override
  String get blockConfirm => 'Закрыть это время';

  @override
  String get unblock => 'Снова открыть это время';

  @override
  String get customerLabel => 'Клиент';

  @override
  String get sourceLabel => 'Источник';

  @override
  String get statusLabel => 'Статус';

  @override
  String get reasonLabel => 'Причина';

  @override
  String get sourceApp => 'Бронь из приложения';

  @override
  String get sourceWalkIn => 'На месте или по телефону';

  @override
  String get sourceBlock => 'Закрыто площадкой';

  @override
  String get markPaid => 'Отметить оплату';

  @override
  String get markNoShow => 'Отметить неявку';

  @override
  String get statusPaid => 'Оплачено';

  @override
  String get statusNoShow => 'Неявка';

  @override
  String get statusUnverified => 'Не подтверждено';

  @override
  String get statusCancelledByVenue => 'Отменено площадкой';

  @override
  String get markAfterStart =>
      'Оплату и неявку можно отметить после начала брони';

  @override
  String get cancelByVenueMsg =>
      'Время сразу освободится. Игрок, забронировавший через приложение, увидит, что бронь отменила площадка.';

  @override
  String get errNotAllowed => 'Вы не управляете этой площадкой';

  @override
  String get bookingSaved => 'Бронь сохранена';

  @override
  String get ownerSettings => 'Часы и цены';

  @override
  String get ownerDashboard => 'Статистика';

  @override
  String get venueHours => 'Часы работы площадки';

  @override
  String get courtHours => 'Часы корта';

  @override
  String get sameAsVenue => 'Как у площадки';

  @override
  String get openLabel => 'Открыто';

  @override
  String get editLabel => 'Изменить';

  @override
  String get saveLabel => 'Сохранить';

  @override
  String get savedMsg => 'Сохранено';

  @override
  String get pricesTitle => 'Цены';

  @override
  String get hoursTitle => 'Часы';

  @override
  String get slotLengthLabel => 'Длина слота';

  @override
  String get basePrice => 'Базовая цена за слот';

  @override
  String get priceRules => 'Правила цен';

  @override
  String get addRule => 'Добавить правило';

  @override
  String get removeRule => 'Удалить правило';

  @override
  String get ruleFrom => 'С';

  @override
  String get ruleTo => 'До';

  @override
  String get rulePrice => 'Цена за слот';

  @override
  String get noRules => 'Правил нет: все слоты по базовой цене';

  @override
  String rulesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count правила цен',
      many: '$count правил цен',
      few: '$count правила цен',
      one: '$count правило цен',
      zero: 'Без правил цен',
    );
    return '$_temp0';
  }

  @override
  String get errInvalidHours => 'Открытие должно быть раньше закрытия';

  @override
  String get errRulesOverlap => 'Два правила совпадают по дню и времени';

  @override
  String get errInvalidArgument => 'Проверьте значения и попробуйте ещё раз';

  @override
  String get errPickWeekday => 'Выберите хотя бы один день';

  @override
  String get errPrice => 'Введите цену';

  @override
  String get period7 => 'Последние 7 дней';

  @override
  String get periodMonth => 'Этот месяц';

  @override
  String get allCourts => 'Все корты';

  @override
  String metricSplit(int app, int walkIn) {
    return 'Приложение $app · на месте $walkIn';
  }

  @override
  String get metricRevenue => 'Оплаченная выручка';

  @override
  String get metricUnconfirmed => 'Неподтверждённая выручка';

  @override
  String get metricDailyAvg => 'Броней в день';

  @override
  String get metricUtilisation => 'Загрузка';

  @override
  String get metricNoShows => 'Неявки';

  @override
  String get peakHours => 'Часы пик';

  @override
  String get noDataPeriod => 'За этот период броней нет';

  @override
  String get adminTitle => 'Админ-панель';

  @override
  String get adminOnly => 'Эта страница доступна только администраторам Actra';

  @override
  String get adminSports => 'Виды спорта';

  @override
  String get adminBanners => 'Баннеры';

  @override
  String get adminAudit => 'Журнал изменений';

  @override
  String get adminAuditHint => 'Кто, что и когда изменил';

  @override
  String venuesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count площадки',
      many: '$count площадок',
      few: '$count площадки',
      one: '$count площадка',
    );
    return '$_temp0';
  }

  @override
  String sportsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count вида спорта',
      many: '$count видов спорта',
      few: '$count вида спорта',
      one: '$count вид спорта',
    );
    return '$_temp0';
  }

  @override
  String bannersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count баннера',
      many: '$count баннеров',
      few: '$count баннера',
      one: '$count баннер',
    );
    return '$_temp0';
  }

  @override
  String courtsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count корта',
      many: '$count кортов',
      few: '$count корта',
      one: '$count корт',
    );
    return '$_temp0';
  }

  @override
  String ownersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count владельца',
      many: '$count владельцев',
      few: '$count владельца',
      one: '$count владелец',
      zero: 'Нет владельцев',
    );
    return '$_temp0';
  }

  @override
  String playersN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count игрока',
      many: '$count игроков',
      few: '$count игрока',
      one: '$count игрок',
    );
    return '$_temp0';
  }

  @override
  String get inactive => 'Неактивно';

  @override
  String get activeLabel => 'Активно';

  @override
  String get activeHint => 'Игроки видят это';

  @override
  String get addVenue => 'Добавить площадку';

  @override
  String get newVenue => 'Новая площадка';

  @override
  String get venueDetails => 'Основное';

  @override
  String get nameLabel => 'Название';

  @override
  String get descriptionLabel => 'Описание';

  @override
  String get districtLabel => 'Район';

  @override
  String get nameRequiredAny => 'Заполните хотя бы один язык';

  @override
  String get saveVenueFirst =>
      'Сохраните площадку, чтобы добавить корты и владельцев';

  @override
  String get addCourt => 'Добавить корт';

  @override
  String get newCourt => 'Новый корт';

  @override
  String get editCourt => 'Изменить корт';

  @override
  String get noCourts => 'Кортов пока нет';

  @override
  String get courtActions => 'Действия с кортом';

  @override
  String get duplicateLabel => 'Дублировать';

  @override
  String get deleteLabel => 'Удалить';

  @override
  String get deleteVenue => 'Удалить площадку';

  @override
  String deleteConfirmTitle(String name) {
    return 'Удалить «$name»?';
  }

  @override
  String get deleteConfirmMsg => 'Это действие нельзя отменить.';

  @override
  String get errHasBookings =>
      'Есть брони, поэтому удалить нельзя. Отключите, чтобы скрыть от игроков.';

  @override
  String get deactivateInstead => 'Отключить';

  @override
  String get errAlreadyExists => 'Этот ID уже занят';

  @override
  String get errNotFound => 'Не найдено. Обновите и попробуйте снова.';

  @override
  String get ownersTitle => 'Владельцы';

  @override
  String get assignOwner => 'Назначить владельца';

  @override
  String get removeOwner => 'Убрать владельца';

  @override
  String get noOwners => 'Владельцы не назначены';

  @override
  String get searchUsers => 'Имя или телефон';

  @override
  String get searchUsersMin => 'Введите хотя бы 2 символа';

  @override
  String get noUsersFound => 'Никого не нашли';

  @override
  String get addSport => 'Добавить вид спорта';

  @override
  String get newSport => 'Новый вид спорта';

  @override
  String get editSport => 'Изменить вид спорта';

  @override
  String get sportIdLabel => 'ID';

  @override
  String get sportIdHint =>
      'Строчные латинские буквы, цифры и _, например squash. Потом изменить нельзя.';

  @override
  String get errSportId =>
      '2–30 символов: строчные латинские буквы, цифры или _, первая — буква';

  @override
  String get iconLabel => 'Иконка';

  @override
  String get sportTypeLabel => 'Тип';

  @override
  String get placeOnly => 'Только место';

  @override
  String get ratingLabel => 'Рейтинг';

  @override
  String get ratingSimple => 'Уровень 1–5';

  @override
  String get ratingCompetitive => 'Рейтинг 1.0–7.0';

  @override
  String get defaultPlayers => 'Игроков по умолчанию';

  @override
  String get sortOrderLabel => 'Порядок в списке';

  @override
  String get addBanner => 'Добавить баннер';

  @override
  String get newBanner => 'Новый баннер';

  @override
  String get editBanner => 'Изменить баннер';

  @override
  String get bannerTitle => 'Заголовок';

  @override
  String get bannerSubtitle => 'Подзаголовок';

  @override
  String get linkLabel => 'Ссылка';

  @override
  String get errUrl => 'Ссылка должна начинаться с https://';

  @override
  String get allCities => 'Все города';

  @override
  String get noBanners => 'Баннеров пока нет';

  @override
  String get auditEmpty => 'Изменений пока нет';

  @override
  String get loadMore => 'Показать ещё';

  @override
  String get auditBefore => 'До';

  @override
  String get auditAfter => 'После';

  @override
  String get auditSystem => 'Система';

  @override
  String get auditCreateVenue => 'Площадка создана';

  @override
  String get auditUpdateVenue => 'Площадка изменена';

  @override
  String get auditDeleteVenue => 'Площадка удалена';

  @override
  String get auditCreateCourt => 'Корт создан';

  @override
  String get auditUpdateCourt => 'Корт изменён';

  @override
  String get auditDuplicateCourt => 'Корт продублирован';

  @override
  String get auditDeleteCourt => 'Корт удалён';

  @override
  String get auditAssignOwner => 'Владелец назначен';

  @override
  String get auditRemoveOwner => 'Владелец убран';

  @override
  String get auditCreateSport => 'Вид спорта создан';

  @override
  String get auditUpdateSport => 'Вид спорта изменён';

  @override
  String get auditCreateBanner => 'Баннер создан';

  @override
  String get auditUpdateBanner => 'Баннер изменён';

  @override
  String get auditDeleteBanner => 'Баннер удалён';

  @override
  String get auditVenueHours => 'Часы площадки изменены';

  @override
  String get auditCourtHours => 'Часы корта изменены';

  @override
  String get auditCourtPricing => 'Цены корта изменены';

  @override
  String get auditWalkIn => 'Добавлена бронь на месте';

  @override
  String get auditBlock => 'Время заблокировано';

  @override
  String get auditMarkBooking => 'Бронь отмечена';

  @override
  String get entityVenue => 'Площадка';

  @override
  String get entityBanner => 'Баннер';

  @override
  String get entityBooking => 'Бронь';

  @override
  String get entityOwner => 'Владелец площадки';

  @override
  String get notificationsTitle => 'Уведомления';

  @override
  String get markAllRead => 'Прочитать все';

  @override
  String get notificationSettings => 'Настройки уведомлений';

  @override
  String get noNotifications => 'Пока нет уведомлений';

  @override
  String get notificationsAndPrivacy => 'Уведомления и приватность';

  @override
  String get notificationsMuteHint =>
      'Выберите, о чём вам сообщать. Выключите группу, чтобы не получать её уведомления.';

  @override
  String get notifCategoryBookings => 'Бронирования';

  @override
  String get notifCategoryVenue => 'Мои площадки';

  @override
  String get notifCategoryGames => 'Игры';

  @override
  String get notifCategoryRequests => 'Запросы на игру';

  @override
  String get notifCategoryInvites => 'Приглашения';

  @override
  String get privacyTitle => 'Приватность';

  @override
  String get hideFromSearch => 'Скрыть меня из поиска игроков';

  @override
  String get hideFromSearchHint =>
      'Другие игроки не найдут вас, когда ищут, кого пригласить.';

  @override
  String get notifSomeone => 'Кто-то';

  @override
  String get notifVenueFallback => 'площадка';

  @override
  String get notifCourtFallback => 'корт';

  @override
  String notifBookingConfirmed(String venue) {
    return 'Бронь подтверждена: $venue';
  }

  @override
  String notifBookingCancelledByVenue(String venue) {
    return 'Площадка отменила вашу бронь: $venue';
  }

  @override
  String notifBookingReminder(String venue) {
    return 'Напоминание: скоро ваша бронь, $venue';
  }

  @override
  String notifVenueNewBooking(String actor, String court) {
    return 'Новая бронь: $court ($actor)';
  }

  @override
  String notifVenueBookingCancelled(String actor, String court) {
    return 'Бронь отменена: $court ($actor)';
  }

  @override
  String notifGameJoined(String actor) {
    return 'Новый игрок в вашей игре: $actor';
  }

  @override
  String notifGameLeft(String actor) {
    return 'Игрок вышел из вашей игры: $actor';
  }

  @override
  String notifJoinRequest(String actor) {
    return 'Запрос на участие: $actor';
  }

  @override
  String get notifJoinApproved => 'Вы в игре! Организатор принял ваш запрос';

  @override
  String get notifJoinDeclined => 'Организатор отклонил ваш запрос';

  @override
  String get notifGameFull => 'Игра заполнена';

  @override
  String get notifGameChanged => 'Организатор изменил детали игры';

  @override
  String get notifGameCancelled => 'Игра отменена';

  @override
  String get notifGameRemoved => 'Организатор исключил вас из игры';

  @override
  String get notifGameReminder => 'Напоминание: скоро ваша игра';

  @override
  String notifGameInvite(String actor) {
    return '$actor приглашает вас в игру';
  }

  @override
  String notifRequestInterest(String actor) {
    return 'Отклик на ваш запрос: $actor';
  }

  @override
  String get notifRequestConvertedIn => 'Запрос стал игрой, и вы в составе';

  @override
  String get notifRequestConvertedFull =>
      'Запрос стал игрой, но места закончились раньше';

  @override
  String get notifRequestExpired => 'Срок запроса на игру истёк';

  @override
  String get notifUnknown => 'Новое уведомление';

  @override
  String get reliabilityNew => 'Новый игрок';

  @override
  String get reliabilityReliable => 'Надёжный';

  @override
  String get reliabilityLimited => 'Ограничен';

  @override
  String get reliabilityBlocked => 'Заблокирован';

  @override
  String reliabilityScore(int score) {
    return 'Рейтинг надёжности $score из 100';
  }

  @override
  String get reliabilityLimitedHint =>
      'Одновременно можно иметь одну будущую бронь. Приходите на игры, чтобы восстановить рейтинг.';

  @override
  String get reliabilityBlockedHint =>
      'Вы не можете бронировать, вступать в игры и создавать запросы, пока старые пропуски не пройдут 90 дней.';
}
