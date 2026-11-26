import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/auth/auth_repository.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';

/// Account deletion from the profile (both app stores require it in the app).
/// Says what happens and asks first; once deleted the player is signed out
/// as with "Sign out" (language and city kept) and lands on the sign-in step.
/// An admin account is refused with the reason; any other failure keeps the
/// player signed in. While the call runs a modal progress indicator covers
/// the app, so nothing can start it twice, and the answer goes to the app's
/// root messenger, which outlives the profile screen.
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
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
  );
  unawaited(navigator.push(progress));

  String? failure;
  try {
    // On success the router leaves the profile for onboarding.
    await session.deleteAccount();
  } on AdminAccountException {
    failure = l.deleteAccountAdmin;
  } catch (_) {
    failure = l.errUnavailable;
  } finally {
    // Removed by reference: the sign-in redirect may already have taken it.
    if (progress.isActive) navigator.removeRoute(progress);
  }
  if (failure != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure), behavior: SnackBarBehavior.floating));
  }
}
