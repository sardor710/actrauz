import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/auth/auth_repository.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// Account deletion from the profile (both app stores require it in the app).
/// Says what happens and asks first; once deleted the player is signed out
/// as with "Sign out" (language and city kept) and lands on the sign-in step.
/// An admin account is refused with the reason; any other failure keeps the
/// player signed in.
Future<void> confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
  final l = context.l;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.deleteAccountTitle),
      content: Text(l.deleteAccountBody),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.deleteAccountConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final session = ref.read(sessionProvider.notifier);
  try {
    // On success the router leaves the profile for onboarding.
    await session.deleteAccount();
  } on AdminAccountException {
    if (context.mounted) showMessage(context, l.deleteAccountAdmin);
  } catch (_) {
    if (context.mounted) showMessage(context, l.errUnavailable);
  }
}
