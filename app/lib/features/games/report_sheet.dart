import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/games.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';

/// Reports [targetId] to Actra (design §6.3), about [gameId] when it comes
/// from a finished game: a reason and up to 500 characters. Says "Report
/// sent" once it went through.
Future<void> showReportSheet(BuildContext context, {required String targetId, required String name, String? gameId}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ReportSheet(targetId: targetId, name: name, gameId: gameId),
    );

class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({super.key, required this.targetId, required this.name, this.gameId});

  /// As the database allows.
  static const maxDetails = 500;

  final String targetId;

  /// The player's name as the screen shows it.
  final String name;
  final String? gameId;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  final _details = TextEditingController();
  ReportReason? _reason;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  /// A refusal shows in the sheet: a snackbar would be hidden behind it.
  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    final l = context.l;
    // The sheet closes on success; keep the screen's messenger for the answer.
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final details = _details.text.trim();
      await ref
          .read(socialRepositoryProvider)
          .reportPlayer(
            widget.targetId,
            gameId: widget.gameId,
            reason: reason,
            details: details.isEmpty ? null : details,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.reportSent), behavior: SnackBarBehavior.floating));
    } on JoinException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = joinErrorText(l, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return SafeArea(
      child: SingleChildScrollView(
        // Above the keyboard while the details are typed.
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.reportTitle(widget.name), style: AppText.title),
            const SizedBox(height: 6),
            Text(l.reportHint, style: AppText.muted),
            const SizedBox(height: 8),
            for (final reason in ReportReason.values)
              RadioListTile<ReportReason>(
                key: ValueKey('report-reason-${reason.name}'),
                value: reason,
                groupValue: _reason,
                onChanged: (picked) => setState(() => _reason = picked),
                contentPadding: EdgeInsets.zero,
                title: Text(reportReasonText(l, reason)),
              ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('report-details'),
              controller: _details,
              maxLength: ReportSheet.maxDetails,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: l.reportDetails),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: manrope(13.5, 600, color: AppColors.error)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('report-send'),
              onPressed: _reason == null || _busy ? null : _send,
              child: Text(l.reportSend),
            ),
          ],
        ),
      ),
    );
  }
}

String reportReasonText(AppLocalizations l, ReportReason reason) => switch (reason) {
  ReportReason.language => l.reportReasonLanguage,
  ReportReason.aggression => l.reportReasonAggression,
  ReportReason.falseScore => l.reportReasonFalseScore,
  ReportReason.other => l.reportReasonOther,
};
