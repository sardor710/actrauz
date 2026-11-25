import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/supabase/last_seen.dart';
import 'l10n/gen/app_localizations.dart';
import 'router.dart';
import 'state/providers.dart';

class ActraApp extends ConsumerStatefulWidget {
  const ActraApp({super.key});

  @override
  ConsumerState<ActraApp> createState() => _ActraAppState();
}

class _ActraAppState extends ConsumerState<ActraApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _touchLastSeen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _touchLastSeen();
  }

  /// Tells the backend the player is around (for "active users"): on start, on
  /// coming back to the app and after signing in. Only with a Supabase project;
  /// the sample backend has nobody to tell.
  void _touchLastSeen() {
    if (!ref.read(backendEnabledProvider)) return;
    touchLastSeen(ref.read(supabaseClientProvider));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((s) => s.userName), (previous, next) {
      if (previous != next && next != null) _touchLastSeen();
    });
    final languageCode = ref.watch(sessionProvider.select((s) => s.languageCode));
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      locale: languageCode == null ? null : Locale(languageCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // Until the player picks a language: the device language when it is
      // supported, otherwise Russian (product spec §3).
      localeResolutionCallback: (device, supported) {
        for (final locale in supported) {
          if (locale.languageCode == device?.languageCode) return locale;
        }
        return const Locale('ru');
      },
      // Light only for now; a dark theme is a later addition.
      theme: buildTheme(),
      themeMode: ThemeMode.light,
    );
  }
}
