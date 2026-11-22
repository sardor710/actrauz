import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'l10n/gen/app_localizations.dart';
import 'router.dart';
import 'state/providers.dart';

class ActraApp extends ConsumerWidget {
  const ActraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
    );
  }
}
