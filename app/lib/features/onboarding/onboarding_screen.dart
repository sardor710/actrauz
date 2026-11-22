import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../data/auth/auth_repository.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';

/// Native language names: shown as-is so anyone can find their own.
const kLanguageNames = {'uz': 'Oʻzbekcha', 'ru': 'Русский', 'en': 'English'};

/// Language → city → sign-in.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final controller = ref.read(sessionProvider.notifier);
    final isDemo = ref.watch(authRepositoryProvider).isDemo;

    final (String title, Widget body) = switch (_step) {
      0 => (
        l.chooseLanguage,
        Column(
          children: [
            for (final code in kLanguageNames.keys)
              _ChoiceTile(
                label: kLanguageNames[code]!,
                selected: session.languageCode == code,
                onTap: () async {
                  await controller.setLanguage(code);
                  setState(() => _step = 1);
                },
              ),
          ],
        ),
      ),
      1 => (
        l.chooseCity,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final city in kCities)
              _ChoiceTile(
                label: city.name.resolve(context.lang),
                selected: session.cityId == city.id,
                onTap: () async {
                  await controller.setCity(city.id);
                  setState(() => _step = 2);
                },
              ),
            const SizedBox(height: 8),
            Text(l.chooseCityHint, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      _ => (l.signInTitle, isDemo ? const _DemoSignIn() : const _TelegramSignIn()),
    };

    return Scaffold(
      appBar: AppBar(
        leading: _step == 0 ? null : BackButton(onPressed: () => setState(() => _step--)),
        title: Text(l.appName, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                LinearProgressIndicator(value: (_step + 1) / 3, borderRadius: BorderRadius.circular(8)),
                const SizedBox(height: 28),
                Text(title, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sample mode (no backend compiled in): a name is all it takes.
class _DemoSignIn extends ConsumerStatefulWidget {
  const _DemoSignIn();

  @override
  ConsumerState<_DemoSignIn> createState() => _DemoSignInState();
}

class _DemoSignInState extends ConsumerState<_DemoSignIn> {
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    await ref.read(sessionProvider.notifier).signIn(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Notice(text: l.demoNotice),
          const SizedBox(height: 16),
          _NameField(controller: _name, onSubmitted: _signIn),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _signIn, icon: const Icon(Icons.send), label: Text(l.signInTelegram)),
        ],
      ),
    );
  }
}

enum _Stage { start, waiting, profile }

/// Real sign-in (product spec §7.1): open the Actra bot in Telegram, wait
/// until the player has shared their phone number there, then, on a first
/// sign-in, ask for a name and acceptance of the terms.
class _TelegramSignIn extends ConsumerStatefulWidget {
  const _TelegramSignIn();

  @override
  ConsumerState<_TelegramSignIn> createState() => _TelegramSignInState();
}

class _TelegramSignInState extends ConsumerState<_TelegramSignIn> {
  static const _pollEvery = Duration(seconds: 2);

  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();

  _Stage _stage = _Stage.start;
  LoginChallenge? _challenge;
  Timer? _poller;
  bool _pollInFlight = false;
  bool _busy = false;
  bool _termsAccepted = false;
  bool _termsMissing = false;
  String? _message;

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  @override
  void initState() {
    super.initState();
    // Signed in to the backend already (e.g. the app was closed before the
    // name was entered): pick up from there instead of asking Telegram again.
    if (_auth.hasSession) WidgetsBinding.instance.addPostFrameCallback((_) => _resume());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _resume() async {
    setState(() => _busy = true);
    try {
      await _finish(await _auth.profileName());
    } catch (_) {
      // Fall back to a fresh sign-in.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Signed in to the backend: enter the app, or ask for the missing name.
  Future<void> _finish(String? fullName) async {
    if (fullName != null) {
      await ref.read(sessionProvider.notifier).signIn(fullName);
    } else if (mounted) {
      setState(() => _stage = _Stage.profile);
    }
  }

  void _stopWaiting() {
    _poller?.cancel();
    _poller = null;
    _challenge = null;
  }

  Future<void> _start() async {
    final failed = context.l.signInFailed;
    final language = ref.read(sessionProvider).languageCode ?? 'ru';
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final challenge = await _auth.startTelegramLogin(language);
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _stage = _Stage.waiting;
      });
      _poller = Timer.periodic(_pollEvery, (_) => _poll());
      await ref.read(urlOpenerProvider)(challenge.botUrl);
    } catch (_) {
      if (!mounted) return;
      _stopWaiting();
      setState(() {
        _stage = _Stage.start;
        _message = failed;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll() async {
    final challenge = _challenge;
    if (challenge == null || _pollInFlight) return;
    _pollInFlight = true;
    try {
      final result = DateTime.now().isAfter(challenge.expiresAt)
          ? const LoginExpired()
          : await _auth.pollTelegramLogin(challenge);
      // Ignore an answer for an attempt the player has already left.
      if (!mounted || _challenge != challenge) return;
      switch (result) {
        case LoginPending():
          break;
        case LoginExpired():
          _stopWaiting();
          setState(() {
            _stage = _Stage.start;
            _message = context.l.telegramExpired;
          });
        case LoginSignedIn(:final fullName):
          _stopWaiting();
          await _finish(fullName);
      }
    } catch (_) {
      // One failed request is not a failed sign-in: the next poll may succeed.
    } finally {
      _pollInFlight = false;
    }
  }

  void _cancel() {
    _stopWaiting();
    setState(() => _stage = _Stage.start);
  }

  Future<void> _saveProfile() async {
    final failed = context.l.signInFailed;
    final nameOk = _form.currentState!.validate();
    setState(() => _termsMissing = !_termsAccepted);
    if (!nameOk || !_termsAccepted) return;

    final session = ref.read(sessionProvider);
    final name = _name.text.trim();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _auth.saveProfile(fullName: name, cityId: session.cityId!, languageCode: session.languageCode!);
      await ref.read(sessionProvider.notifier).signIn(name);
    } catch (_) {
      if (mounted) setState(() => _message = failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_message != null) ...[
          _Notice(text: _message!, error: true),
          const SizedBox(height: 16),
        ],
        ...switch (_stage) {
          _Stage.start => [
            Text(l.telegramHint, style: muted),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.send),
              label: Text(l.signInTelegram),
            ),
          ],
          _Stage.waiting => [
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text(l.telegramWaiting, style: muted),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => ref.read(urlOpenerProvider)(_challenge!.botUrl),
              icon: const Icon(Icons.open_in_new),
              label: Text(l.telegramOpenAgain),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _cancel, child: Text(l.cancel)),
          ],
          _Stage.profile => [
            Form(
              key: _form,
              child: _NameField(controller: _name, onSubmitted: _saveProfile),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _termsAccepted,
              onChanged: (value) => setState(() {
                _termsAccepted = value ?? false;
                if (_termsAccepted) _termsMissing = false;
              }),
              title: Text(l.acceptTerms),
              subtitle: _termsMissing ? Text(l.termsRequired, style: TextStyle(color: scheme.error)) : null,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _saveProfile, child: Text(l.continueLabel)),
          ],
        },
      ],
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(labelText: l.yourName),
      validator: (value) => (value == null || value.trim().isEmpty) ? l.nameRequired : null,
      onFieldSubmitted: (_) => onSubmitted(),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: TextStyle(color: error ? scheme.onErrorContainer : scheme.onTertiaryContainer)),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
                Icon(selected ? Icons.check_circle : Icons.chevron_right, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
