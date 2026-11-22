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
}
