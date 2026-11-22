import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
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
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  int _step = 0;

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
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final controller = ref.read(sessionProvider.notifier);

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
      _ => (
        l.signInTitle,
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(l.demoNotice, style: TextStyle(color: theme.colorScheme.onTertiaryContainer)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: l.yourName),
                validator: (value) => (value == null || value.trim().isEmpty) ? l.nameRequired : null,
                onFieldSubmitted: (_) => _signIn(),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _signIn, icon: const Icon(Icons.send), label: Text(l.signInTelegram)),
            ],
          ),
        ),
      ),
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
