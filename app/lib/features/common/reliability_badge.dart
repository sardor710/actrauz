import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/community.dart';
import '../../l10n/gen/app_localizations.dart';
import 'formatters.dart';
import 'widgets.dart';

String reliabilityLabel(AppLocalizations l, ReliabilityBadge badge) => switch (badge) {
  ReliabilityBadge.isNew => l.reliabilityNew,
  ReliabilityBadge.reliable => l.reliabilityReliable,
  ReliabilityBadge.limited => l.reliabilityLimited,
  ReliabilityBadge.blocked => l.reliabilityBlocked,
};

/// What a limited or blocked player can no longer do; null for the others.
String? reliabilityHint(AppLocalizations l, ReliabilityBadge badge) => switch (badge) {
  ReliabilityBadge.limited => l.reliabilityLimitedHint,
  ReliabilityBadge.blocked => l.reliabilityBlockedHint,
  _ => null,
};

/// The reliability label as a pill: new, reliable, limited or blocked.
class ReliabilityPill extends StatelessWidget {
  const ReliabilityPill({super.key, required this.reliability, this.large = false});

  final Reliability reliability;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final (color, onColor, icon) = switch (reliability.badge) {
      ReliabilityBadge.isNew => (AppColors.field, AppColors.ink, Icons.waving_hand_outlined),
      ReliabilityBadge.reliable => (AppColors.primarySoft, AppColors.primaryDark, Icons.verified_outlined),
      ReliabilityBadge.limited => (AppColors.amberSoft, AppColors.ink, Icons.error_outline_rounded),
      ReliabilityBadge.blocked => (AppColors.errorSoft, AppColors.error, Icons.block_rounded),
    };
    return Pill(
      text: reliabilityLabel(context.l, reliability.badge),
      icon: icon,
      color: color,
      onColor: onColor,
      large: large,
    );
  }
}
