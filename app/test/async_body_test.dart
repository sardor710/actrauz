import 'dart:async';

import 'package:actra/core/theme.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/community.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/features/common/widgets.dart';
import 'package:actra/features/games/game_card.dart';
import 'package:actra/l10n/gen/app_localizations.dart';
import 'package:actra/router.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart';
import 'games_host_flow_test.dart' show containerOf;

const _error = 'Something went wrong. Try again.';

/// The sample backend, with Almaty's games held on [gate] and then refused
/// while [fail].
class _SlowAlmaty extends SampleBackend {
  _SlowAlmaty({required super.utcNow}) : super(meName: 'Test');

  Completer<void>? gate;
  bool fail = false;

  @override
  Future<List<Game>> games(String cityId) async {
    if (cityId == 'almaty') {
      await gate?.future;
      if (fail) throw const JoinException(JoinError.unavailable);
    }
    return super.games(cityId);
  }
}

/// One player's inbox: the [first] backend (the first player) has one
/// notice; a later one's inbox is held on [gate] and then refused.
class _Inbox extends SampleBackend {
  _Inbox({required super.utcNow, required this.first, required this.gate});

  final bool first;
  final Completer<void> gate;

  @override
  Future<List<AppNotification>> inbox({DateTime? before, String? beforeId}) async {
    if (first) {
      return [
        AppNotification(
          id: 'n1',
          kind: 'game_full',
          category: 'games',
          payload: const {},
          createdAt: DateTime.utc(2026, 11, 22),
          read: false,
        ),
      ];
    }
    await gate.future;
    throw const JoinException(JoinError.unavailable);
  }
}

/// [AsyncBody] showing [value], in a tree that keeps its state between pumps.
Future<void> _show(WidgetTester tester, AsyncValue<int> value) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: buildTheme(),
    home: Scaffold(
      body: AsyncBody<int>(value: value, builder: (n) => Text('data $n')),
    ),
  ),
);

void main() {
  testWidgets('AsyncBody: a refresh keeps the data, a reload never shows the old value', (tester) async {
    final spinner = find.byType(CircularProgressIndicator);
    final st = StackTrace.empty;

    // First load.
    await _show(tester, const AsyncLoading<int>());
    expect(spinner, findsOneWidget);
    const one = AsyncData<int>(1);
    await _show(tester, one);
    expect(find.text('data 1'), findsOneWidget);

    // A refresh (invalidate): loading, then a failure, keep the data.
    final refreshing = const AsyncLoading<int>().copyWithPrevious(one);
    expect(refreshing.isRefreshing, isTrue);
    await _show(tester, refreshing);
    expect(find.text('data 1'), findsOneWidget);
    expect(spinner, findsNothing);
    await _show(tester, AsyncError<int>('offline', st).copyWithPrevious(refreshing));
    expect(find.text('data 1'), findsOneWidget);
    expect(find.text(_error), findsNothing);

    // A reload (a dependency changed): the spinner, then the error, never the old value.
    final reloading = const AsyncLoading<int>().copyWithPrevious(one, isRefresh: false);
    expect(reloading.isReloading, isTrue);
    await _show(tester, reloading);
    expect(find.text('data 1'), findsNothing);
    expect(spinner, findsOneWidget);
    final failed = AsyncError<int>('offline', st).copyWithPrevious(reloading);
    expect(failed.hasValue, isTrue, reason: 'Riverpod keeps the old value on the error');
    await _show(tester, failed);
    expect(find.text('data 1'), findsNothing);
    expect(find.text(_error), findsOneWidget);
    // A refresh of that failure still does not bring the old value back.
    await _show(tester, const AsyncLoading<int>().copyWithPrevious(failed));
    expect(find.text('data 1'), findsNothing);
    expect(spinner, findsOneWidget);

    // New data shows, and refreshes keep it again.
    const two = AsyncData<int>(2);
    await _show(tester, two);
    expect(find.text('data 2'), findsOneWidget);
    await _show(tester, const AsyncLoading<int>().copyWithPrevious(two));
    expect(find.text('data 2'), findsOneWidget);
  });

  testWidgets("a city switch never shows the old city's games", (tester) async {
    late _SlowAlmaty backend;
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning, backend: (clock) => backend = _SlowAlmaty(utcNow: clock));
    final c = containerOf(tester);
    c.read(routerProvider).go('/games');
    await tester.pumpAndSettle();
    expect(find.byType(GameCard), findsWidgets, reason: "Tashkent's games");

    backend.gate = Completer<void>();
    backend.fail = true;
    await c.read(sessionProvider.notifier).setCity('almaty');
    await tester.pump();
    expect(find.byType(GameCard), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    backend.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(GameCard), findsNothing);
    expect(find.text(_error), findsOneWidget);

    // Tried again (pull or resume), with Almaty reachable.
    backend.fail = false;
    c.invalidate(gamesProvider);
    await tester.pumpAndSettle();
    expect(find.text(_error), findsNothing);
    final almaty = await backend.games('almaty');
    expect(find.byType(GameCard), findsNWidgets(almaty.length));
  });

  testWidgets('another account never sees the previous inbox', (tester) async {
    final gate = Completer<void>();
    var built = 0;
    // The sample backend is built again for each signed-in player.
    await pumpApp(
      tester,
      prefs: signedIn,
      utcNow: sundayMorning,
      backend: (clock) => _Inbox(utcNow: clock, first: built++ == 0, gate: gate),
    );
    final c = containerOf(tester);
    c.read(routerProvider).go('/inbox');
    await tester.pumpAndSettle();
    const notice = 'Your game is full';
    expect(find.text(notice), findsOneWidget);

    await c.read(sessionProvider.notifier).signIn('Other');
    await tester.pump();
    expect(find.text(notice), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(notice), findsNothing);
    expect(find.text(_error), findsOneWidget);
  });
}
