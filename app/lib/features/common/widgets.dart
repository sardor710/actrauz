import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/sample/sample_media.dart';
import 'formatters.dart';

/// Remembers, across builds, whether an async value's previous data belongs
/// to something else (AsyncBody's rule).
///
/// A refresh of the same data (`ref.invalidate` / `ref.refresh`, Riverpod's
/// `isRefreshing`) keeps the data, also when it fails. A reload because a
/// dependency changed (another city, another player: `isReloading`) makes the
/// previous value stale until fresh data arrives: Riverpod keeps the previous
/// value on an error after either, so the reload has to be remembered.
class StaleTracker {
  /// A reload was seen and no fresh data has arrived since.
  bool stale = false;

  /// Notes [value]'s state; true while its previous data is not to be shown.
  bool update<T>(AsyncValue<T> value) {
    if (value.isReloading) {
      stale = true;
    } else if (value is AsyncData<T> && !value.isLoading) {
      stale = false;
    }
    return stale;
  }
}

/// Loading, error and data states for one async value.
///
/// A refresh of the same data keeps the data on screen while it loads and
/// when it fails. A reload because a dependency changed never shows the
/// previous value, which belongs to something else: it shows the spinner and
/// then the new data or the error, as a first load does ([StaleTracker]).
class AsyncBody<T> extends StatefulWidget {
  const AsyncBody({super.key, required this.value, required this.builder, this.onRetry, this.errorText, this.canRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  /// When set, the error state offers "Try again", which calls it.
  final VoidCallback? onRetry;

  /// The error's text; "Something went wrong" without it.
  final String Function(Object error)? errorText;

  /// Whether "Try again" is offered for this error (default: always, with
  /// [onRetry]); e.g. not for something that does not exist.
  final bool Function(Object error)? canRetry;

  @override
  State<AsyncBody<T>> createState() => _AsyncBodyState<T>();
}

class _AsyncBodyState<T> extends State<AsyncBody<T>> {
  final _tracker = StaleTracker();

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final stale = _tracker.update(value);

    const loading = Padding(
      padding: EdgeInsets.all(32),
      child: Center(child: CircularProgressIndicator()),
    );
    Widget error() {
      final failure = value.error;
      final text = failure == null ? null : widget.errorText?.call(failure);
      final state = EmptyState(icon: Icons.error_outline, text: text ?? context.l.errGeneric);
      final retry = widget.onRetry;
      if (retry == null || (failure != null && !(widget.canRetry?.call(failure) ?? true))) return state;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          state,
          OutlinedButton(key: const ValueKey('async-retry'), onPressed: retry, child: Text(context.l.tryAgain)),
        ],
      );
    }

    if (stale) return value.isLoading ? loading : error();
    return value.when(
      skipLoadingOnReload: false,
      skipLoadingOnRefresh: true,
      skipError: true,
      data: widget.builder,
      loading: () => loading,
      error: (_, _) => error(),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
          child: Icon(icon, size: 34, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 14),
        Text(text, textAlign: TextAlign.center, style: AppText.muted.copyWith(fontSize: 15)),
      ],
    ),
  );
}

/// White rounded card with an uppercase title, the main block of every tab.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.onSeeAll,
    this.contentPadding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final String title;
  final Widget child;
  final VoidCallback? onSeeAll;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, onSeeAll == null ? 18 : 8, 6, onSeeAll == null ? 14 : 4),
            child: Row(
              children: [
                Expanded(child: Text(title.toUpperCase(), style: AppText.sectionTitle)),
                if (onSeeAll != null)
                  TextButton(
                    onPressed: onSeeAll,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Text(context.l.seeAll), const Icon(Icons.chevron_right, size: 18)],
                    ),
                  ),
              ],
            ),
          ),
          Padding(padding: contentPadding, child: child),
        ],
      ),
    ),
  );
}

/// A bundled photo with rounded corners. Shows a tinted block if the file is
/// missing, so a venue without a photo never leaves a hole.
class PhotoBox extends StatelessWidget {
  const PhotoBox({
    super.key,
    required this.asset,
    this.width,
    this.height,
    this.radius = 16,
    this.darken = 0,
    this.child,
  });

  final String asset;
  final double? width;
  final double? height;
  final double radius;

  /// 0–1: black overlay strength, for text placed on top of the photo.
  final double darken;
  final Widget? child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            asset,
            fit: BoxFit.cover,
            cacheWidth: 900,
            errorBuilder: (context, error, stack) => const ColoredBox(
              key: ValueKey('photo-fallback'),
              color: AppColors.primarySoft,
              child: Icon(Icons.image_outlined, color: AppColors.primaryDark),
            ),
          ),
          if (darken > 0)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: darken),
                    Colors.black.withValues(alpha: darken * 0.35),
                  ],
                ),
              ),
            ),
          if (child != null) child!,
        ],
      ),
    ),
  );
}

/// 3D sport icon, falling back to a line icon for an unknown sport.
class SportBadge extends StatelessWidget {
  const SportBadge({super.key, required this.sportId, this.size = 56});

  final String sportId;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget icon() => Icon(sportIcon(sportId), size: size * 0.8, color: AppColors.primaryDark);
    if (!hasSportArt(sportId)) return SizedBox(width: size, height: size, child: icon());
    return Image.asset(
      sportIconAsset(sportId),
      width: size,
      height: size,
      errorBuilder: (context, error, stack) => icon(),
    );
  }
}

/// Small rounded label: a status, a level range, a time.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.text,
    this.icon,
    this.color = AppColors.field,
    this.onColor = AppColors.ink,
    this.large = false,
  });

  final String text;
  final IconData? icon;
  final Color color;
  final Color onColor;
  final bool large;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: large ? 14 : 10, vertical: large ? 7 : 5),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: large ? 16 : 14, color: onColor), const SizedBox(width: 4)],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: manrope(large ? 14 : 12, 700, color: onColor),
          ),
        ),
      ],
    ),
  );
}

/// Circle with a person's initial on a soft colour picked from their name.
/// A deleted account gets a plain grey circle with a person outline instead.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key, required this.name, this.size = 44, this.border = false, this.deleted = false});

  final String name;
  final double size;
  final bool border;
  final bool deleted;

  @override
  Widget build(BuildContext context) {
    if (deleted) {
      return Container(
        key: const ValueKey('deleted-avatar'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.line,
          shape: BoxShape.circle,
          border: border ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: Icon(Icons.person_outline_rounded, size: size * 0.55, color: AppColors.muted),
      );
    }
    final tint = tintFor(name);
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.background,
        shape: BoxShape.circle,
        border: border ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: Text(initial, style: manrope(size * 0.42, 800, color: tint.foreground)),
    );
  }
}

/// Overlapping avatars, the first one larger: who is already in a game.
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.names, this.deleted = const [], this.max = 3});

  final List<String> names;

  /// Per name, whether that account was deleted (missing = live).
  final List<bool> deleted;
  final int max;

  bool _isDeleted(int i) => i < deleted.length && deleted[i];

  @override
  Widget build(BuildContext context) {
    final shown = names.take(max).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    const big = 48.0;
    const small = 32.0;
    final width = big + (shown.length - 1) * (small - 8);
    return SizedBox(
      width: width,
      height: big,
      child: Stack(
        children: [
          for (var i = shown.length - 1; i >= 1; i--)
            Positioned(
              left: big - 10 + (i - 1) * (small - 8),
              bottom: 0,
              child: InitialAvatar(name: shown[i], size: small, border: true, deleted: _isDeleted(i)),
            ),
          InitialAvatar(name: shown.first, size: big, border: true, deleted: _isDeleted(0)),
        ],
      ),
    );
  }
}

/// Outlined rounded chip used in filter rows.
class FilterChipButton extends StatelessWidget {
  const FilterChipButton({
    super.key,
    this.label,
    this.icon,
    this.selected = false,
    this.dropdown = false,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final bool selected;
  final bool dropdown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.primaryDark : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? AppColors.primary : AppColors.line, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: label == null ? 12 : 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon, size: 20, color: fg),
                if (icon != null && label != null) const SizedBox(width: 6),
                if (label != null)
                  Flexible(
                    child: Text(label!, style: manrope(14, 700, color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                if (dropdown) ...[const SizedBox(width: 4), Icon(Icons.keyboard_arrow_down, size: 20, color: fg)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round white button placed on top of a photo (back, favourite).
class OverlayIconButton extends StatelessWidget {
  const OverlayIconButton({super.key, required this.icon, required this.onTap, this.color = AppColors.ink, this.label});

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: Colors.white.withValues(alpha: 0.94),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 22, color: color)),
      ),
    ),
  );
}

/// Bottom sheet with a short list of options; returns the chosen key.
Future<String?> showOptionSheet(
  BuildContext context, {
  required String title,
  required Map<String, String> options,
  String? current,
}) => showModalBottomSheet<String>(
  context: context,
  useRootNavigator: true,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(alignment: Alignment.centerLeft, child: Text(title, style: AppText.title)),
        ),
        for (final option in options.entries)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(option.value),
            trailing: option.key == current ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
            onTap: () => Navigator.of(context).pop(option.key),
          ),
        const SizedBox(height: 12),
      ],
    ),
  ),
);

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

/// Waits for a pull-to-refresh reload. A failed one keeps the page as it was
/// (see [AsyncBody]) and says so, so the pull is not silently ignored.
Future<void> pullToReload(BuildContext context, Future<Object?> reload) async {
  try {
    await reload;
  } catch (_) {
    if (context.mounted) showMessage(context, context.l.errGeneric);
  }
}
