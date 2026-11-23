import 'package:flutter/material.dart';

import '../../core/localized_text.dart';
import '../../core/theme.dart';
import '../common/formatters.dart';
import '../onboarding/onboarding_screen.dart' show kLanguageNames;

/// Most characters a name, title or address may have (the backend's limit).
const kMaxTextLength = 200;

/// Most characters a description may have.
const kMaxDescriptionLength = 2000;

/// One piece of admin-entered content in all three languages: a label and
/// inputs for Oʻzbekcha, Русский and English.
///
/// Inputs have the keys `$fieldKey-uz`, `$fieldKey-ru` and `$fieldKey-en`.
/// With [required], at least one language must be filled in. Side by side
/// on a wide form, stacked on a phone; multiline inputs always stack.
class LocalizedField extends StatefulWidget {
  const LocalizedField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.initial,
    required this.onChanged,
    this.required = false,
    this.multiline = false,
  });

  final String fieldKey;
  final String label;
  final LocalizedText initial;
  final ValueChanged<LocalizedText> onChanged;
  final bool required;
  final bool multiline;

  @override
  State<LocalizedField> createState() => _LocalizedFieldState();
}

class _LocalizedFieldState extends State<LocalizedField> {
  late final _controllers = {
    'uz': TextEditingController(text: widget.initial.uz ?? ''),
    'ru': TextEditingController(text: widget.initial.ru ?? ''),
    'en': TextEditingController(text: widget.initial.en ?? ''),
  };

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  LocalizedText get _value {
    String? read(String code) {
      final text = _controllers[code]!.text.trim();
      return text.isEmpty ? null : text;
    }

    return LocalizedText(uz: read('uz'), ru: read('ru'), en: read('en'));
  }

  bool get _filled => _controllers.values.any((c) => c.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final max = widget.multiline ? kMaxDescriptionLength : kMaxTextLength;

    return FormField<LocalizedText>(
      initialValue: widget.initial,
      validator: (_) => widget.required && !_filled ? l.nameRequiredAny : null,
      builder: (field) {
        Widget input(String code) => TextField(
          key: ValueKey('${widget.fieldKey}-$code'),
          controller: _controllers[code],
          maxLength: max,
          minLines: widget.multiline ? 2 : 1,
          maxLines: widget.multiline ? 6 : 1,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: widget.multiline ? TextInputType.multiline : TextInputType.text,
          decoration: InputDecoration(
            labelText: kLanguageNames[code],
            counterText: '',
            errorText: field.hasError ? '' : null,
            errorStyle: const TextStyle(height: 0, fontSize: 0),
          ),
          onChanged: (_) {
            field.didChange(_value);
            widget.onChanged(_value);
          },
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(widget.required ? '${widget.label} *' : widget.label, style: AppText.bodyStrong),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = !widget.multiline && constraints.maxWidth >= 560;
                if (sideBySide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: input('uz')),
                      const SizedBox(width: 10),
                      Expanded(child: input('ru')),
                      const SizedBox(width: 10),
                      Expanded(child: input('en')),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [input('uz'), const SizedBox(height: 10), input('ru'), const SizedBox(height: 10), input('en')],
                );
              },
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(field.errorText!, style: manrope(13, 600, color: AppColors.error)),
              ),
          ],
        );
      },
    );
  }
}
