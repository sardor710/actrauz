import 'dart:async';

import 'package:actra/app.dart';
import 'package:actra/data/auth/auth_repository.dart';
import 'package:actra/features/common/widgets.dart';
import 'package:actra/l10n/gen/app_localizations.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sunday 22 Nov 2026, 10:00 in Tashkent (UTC+5).
final sundayMorning = DateTime.utc(2026, 11, 22, 5, 0);

final ru = lookupAppLocalizations(const Locale('ru'));

/// The backend's side of sign-in, scripted by each test.
class FakeAuth implements AuthRepository {
  FakeAuth({this.session = false, this.storedName, List<LoginPoll>? answers}) : answers = answers ?? [];

  bool session;
  String? storedName;

  /// What each poll returns, in order; "pending" once the list runs out.
  final List<LoginPoll> answers;
  bool failStart = false;

  final startedIn = <String>[];
  int polls = 0;
  int signOuts = 0;
  ({String fullName, String cityId, String languageCode})? savedProfile;
  final _lost = StreamController<void>.broadcast();

  void loseSession() {
    session = false;
    _lost.add(null);
  }

  @override
  bool get isDemo => false;

  @override
  bool get hasSession => session;

  @override
  Stream<void> get sessionLost => _lost.stream;

  @override
  Future<LoginChallenge> startTelegramLogin(String languageCode) async {
    if (failStart) throw Exception('offline');
    startedIn.add(languageCode);
    return LoginChallenge(
      token: 'tok${startedIn.length}',
      pollSecret: 'secret',
      botUrl: Uri.parse('https://t.me/actra_test_bot?start=tok${startedIn.length}'),
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<LoginPoll> pollTelegramLogin(LoginChallenge challenge) async {
    polls++;
    final answer = answers.isEmpty ? const LoginPending() : answers.removeAt(0);
    if (answer is LoginSignedIn) session = true;
    return answer;
  }

  @override
  Future<String?> profileName() async => storedName;

  @override
  Future<void> saveProfile({required String fullName, required String cityId, required String languageCode}) async {
    savedProfile = (fullName: fullName, cityId: cityId, languageCode: languageCode);
    storedName = fullName;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    session = false;
  }

  /// What `deleteAccount` throws, if anything.
  Object? deleteError;
  int deletes = 0;

  @override
  Future<void> deleteAccount() async {
    deletes++;
    if (deleteError case final error?) throw error;
    // Deleted, then signed out, like the real implementation.
    session = false;
  }
}

Future<List<Uri>> pumpApp(WidgetTester tester, FakeAuth auth, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  await initializeDateFormatting();

  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final opened = <Uri>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(sharedPrefs),
        clockProvider.overrideWithValue(() => sundayMorning),
        authRepositoryProvider.overrideWithValue(auth),
        urlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
      child: const ActraApp(),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Taps, then lets the started request finish. No pumpAndSettle: the waiting
/// screen animates for as long as it is shown.
Future<void> tapAndWait(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// One polling interval.
Future<void> nextPoll(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Language and city, up to the sign-in step, in Russian.
Future<void> reachSignIn(WidgetTester tester) async {
  await tap(tester, find.text('Русский'));
  await tap(tester, find.text('Ташкент'));
  expect(find.text(ru.signInTitle), findsOneWidget);
}

void main() {
  testWidgets('a new player signs in through Telegram, then gives a name and accepts the terms', (tester) async {
    final auth = FakeAuth(answers: [const LoginPending(), const LoginSignedIn()]);
    final opened = await pumpApp(tester, auth);
    await reachSignIn(tester);

    // Real sign-in: no demo notice and no name field yet.
    expect(find.text(ru.demoNotice), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text(ru.telegramHint), findsOneWidget);

    await tapAndWait(tester, find.text(ru.signInTelegram));
    expect(auth.startedIn, ['ru']);
    expect(opened, [Uri.parse('https://t.me/actra_test_bot?start=tok1')]);
    expect(find.text(ru.telegramWaiting), findsOneWidget);

    // Not shared yet: still waiting.
    await nextPoll(tester);
    expect(find.text(ru.telegramWaiting), findsOneWidget);
    expect(auth.polls, 1);

    // The contact arrives; the account is new, so the profile is asked for.
    await nextPoll(tester);
    await tester.pumpAndSettle();
    expect(find.text(ru.telegramWaiting), findsNothing);
    expect(find.text(ru.acceptTerms), findsOneWidget);

    // Neither a name nor the terms: both are asked for, nothing is saved.
    await tap(tester, find.text(ru.continueLabel));
    expect(find.text(ru.nameRequired), findsOneWidget);
    expect(find.text(ru.termsRequired), findsOneWidget);
    expect(auth.savedProfile, isNull);

    // A name without the terms is still refused.
    await tester.enterText(find.byType(TextFormField), ' Тест ');
    await tap(tester, find.text(ru.continueLabel));
    expect(find.text(ru.termsRequired), findsOneWidget);
    expect(auth.savedProfile, isNull);

    await tap(tester, find.byType(Checkbox));
    expect(find.text(ru.termsRequired), findsNothing);
    await tap(tester, find.text(ru.continueLabel));

    expect(auth.savedProfile, (fullName: 'Тест', cityId: 'tashkent', languageCode: 'ru'));
    expect(find.text('Привет, Тест'), findsOneWidget);
    for (final label in ['Главная', 'Игры', 'Площадки', 'Турниры', 'Сообщество']) {
      expect(find.text(label), findsWidgets);
    }

    // Polling stopped once signed in.
    final polls = auth.polls;
    await tester.pump(const Duration(seconds: 10));
    expect(auth.polls, polls);
  });

  testWidgets('a returning player goes straight in', (tester) async {
    final auth = FakeAuth(answers: [const LoginSignedIn(fullName: 'Алишер')]);
    await pumpApp(tester, auth);
    await reachSignIn(tester);
    await tapAndWait(tester, find.text(ru.signInTelegram));
    await nextPoll(tester);
    await tester.pumpAndSettle();

    expect(find.text('Привет, Алишер'), findsOneWidget);
    expect(auth.savedProfile, isNull);
  });

  testWidgets('an expired link says so and offers the button again', (tester) async {
    final auth = FakeAuth(answers: [const LoginExpired()]);
    final opened = await pumpApp(tester, auth);
    await reachSignIn(tester);
    await tapAndWait(tester, find.text(ru.signInTelegram));
    await nextPoll(tester);
    await tester.pumpAndSettle();

    expect(find.text(ru.telegramExpired), findsOneWidget);
    expect(find.text(ru.telegramWaiting), findsNothing);

    // Trying again starts a fresh attempt with a new link.
    await tapAndWait(tester, find.text(ru.signInTelegram));
    expect(find.text(ru.telegramExpired), findsNothing);
    expect(opened.last, Uri.parse('https://t.me/actra_test_bot?start=tok2'));
    await tapAndWait(tester, find.text(ru.cancel));
  });

  testWidgets('"Open Telegram again" reopens the same link; Cancel stops waiting', (tester) async {
    final auth = FakeAuth();
    final opened = await pumpApp(tester, auth);
    await reachSignIn(tester);
    await tapAndWait(tester, find.text(ru.signInTelegram));

    await tapAndWait(tester, find.text(ru.telegramOpenAgain));
    expect(opened.length, 2);
    expect(opened.first, opened.last);

    await tapAndWait(tester, find.text(ru.cancel));
    await tester.pumpAndSettle();
    expect(find.text(ru.signInTelegram), findsOneWidget);
    final polls = auth.polls;
    await tester.pump(const Duration(seconds: 10));
    expect(auth.polls, polls);
  });

  testWidgets('no connection: a clear message, and the button still works', (tester) async {
    final auth = FakeAuth()..failStart = true;
    final opened = await pumpApp(tester, auth);
    await reachSignIn(tester);
    await tapAndWait(tester, find.text(ru.signInTelegram));
    await tester.pumpAndSettle();

    expect(find.text(ru.signInFailed), findsOneWidget);
    expect(opened, isEmpty);
    expect(find.text(ru.signInTelegram), findsOneWidget);
  });

  testWidgets('a remembered name without a backend session is not a sign-in', (tester) async {
    final auth = FakeAuth(session: false);
    await pumpApp(tester, auth, prefs: {'lang': 'ru', 'city': 'tashkent', 'user_name': 'Тест'});
    expect(find.text('Привет, Тест'), findsNothing);
    expect(find.text('Oʻzbekcha'), findsOneWidget);
  });

  testWidgets('when the backend ends the session the app returns to sign-in', (tester) async {
    final auth = FakeAuth(session: true, storedName: 'Тест');
    await pumpApp(tester, auth, prefs: {'lang': 'ru', 'city': 'tashkent', 'user_name': 'Тест'});
    expect(find.text('Привет, Тест'), findsOneWidget);

    auth.loseSession();
    await tester.pumpAndSettle();
    expect(find.text('Привет, Тест'), findsNothing);
    expect(find.text('Oʻzbekcha'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_name'), isNull);
  });

  testWidgets('a session left over from an unfinished sign-up resumes at the profile step', (tester) async {
    final auth = FakeAuth(session: true);
    final opened = await pumpApp(tester, auth, prefs: {'lang': 'ru', 'city': 'tashkent'});
    await reachSignIn(tester);
    await tester.pumpAndSettle();

    // Already proven by Telegram: straight to name and terms, no new link.
    expect(opened, isEmpty);
    expect(find.text(ru.acceptTerms), findsOneWidget);
  });

  testWidgets('signing out also ends the backend session', (tester) async {
    final auth = FakeAuth(session: true, storedName: 'Тест');
    await pumpApp(tester, auth, prefs: {'lang': 'ru', 'city': 'tashkent', 'user_name': 'Тест'});
    // The profile opens from the avatar in the header.
    await tap(tester, find.byType(InitialAvatar).first);
    await tester.ensureVisible(find.text(ru.signOut));
    await tap(tester, find.text(ru.signOut));

    expect(auth.signOuts, 1);
    expect(find.text('Oʻzbekcha'), findsOneWidget);
  });
}
