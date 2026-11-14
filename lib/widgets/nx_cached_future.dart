import 'package:flutter/material.dart';

import '../core/nx_swr_cache.dart';
import '../services/api_client.dart';
import 'nx_refresh_bar.dart';
import 'nx_skeleton.dart';
import '../core/i18n.dart';
import 'nx_refresh.dart';

/// Stale-while-revalidate loader — keeps last data while refreshing.
///
/// With [cacheKey] the last answer is also kept in [NxSwrCache]: opening the
/// screen again shows it at once (no skeleton) and refreshes in the
/// background with a thin progress line.
class NxCachedFuture<T> extends StatefulWidget {
  const NxCachedFuture({
    super.key,
    required this.load,
    required this.builder,
    this.skeleton,
    this.empty,
    this.isEmpty,
    this.revision = 0,
    this.onRetry,
    this.refresh = true,
    this.cacheKey,
    this.persist = false,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? skeleton;
  final Widget? empty;
  final bool Function(T data)? isEmpty;
  final int revision;
  final VoidCallback? onRetry;
  final bool refresh;

  /// [NxSwrCache] key of this answer (see [NxSwrCache.key]); null = no app-wide cache.
  final String? cacheKey;

  /// Also keep the answer on disk (JSON values; a few hot lists only).
  final bool persist;

  @override
  State<NxCachedFuture<T>> createState() => NxCachedFutureState<T>();
}

class NxCachedFutureState<T> extends State<NxCachedFuture<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  /// Showing cached data while the fresh answer loads.
  bool _refreshing = false;

  /// The data on screen came from the app-wide cache (tests).
  @visibleForTesting
  bool debugFromCache = false;

  @override
  void initState() {
    super.initState();
    final key = widget.cacheKey;
    if (key != null) {
      final hit = NxSwrCache.instance.peek<T>(key);
      if (hit != null) {
        _data = hit;
        _loading = false;
        debugFromCache = true;
      }
    }
    _fetch();
  }

  @override
  void didUpdateWidget(covariant NxCachedFuture<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey && widget.cacheKey != null) {
      final hit = NxSwrCache.instance.peek<T>(widget.cacheKey!);
      if (hit != null) _data = hit;
      _fetch();
    } else if (oldWidget.revision != widget.revision) {
      _fetch();
    }
  }

  Future<void> reload() => _fetch();

  Future<void> _fetch() async {
    final had = _data != null;
    final key = widget.cacheKey;
    void apply() {
      if (!had) {
        _loading = true;
        _error = null;
      } else {
        _error = null;
        _refreshing = true;
      }
    }

    setState(apply);
    try {
      final next = await widget.load();
      if (!mounted) return;
      if (key != null) NxSwrCache.instance.put<T>(key, next, persist: widget.persist);
      setState(() {
        _data = next;
        _loading = false;
        _refreshing = false;
        _error = null;
        debugFromCache = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_loading && data == null) {
      return widget.skeleton ?? const NxSkeletonList();
    }
    if (_error != null && data == null) {
      return NxErrorRetry(error: _error!, onRetry: widget.onRetry ?? _fetch);
    }
    if (data == null) {
      return widget.empty ?? const SizedBox.shrink();
    }
    final empty = widget.isEmpty?.call(data) ?? false;
    final child = empty
        ? (widget.empty ?? Center(child: Text(tr('ไม่มีข้อมูล'))))
        : widget.builder(context, data);
    final refreshable = widget.refresh
        ? NxRefresh(
            color: Theme.of(context).colorScheme.primary,
            notificationPredicate: (n) => n.depth <= 2,
            onRefresh: _fetch,
            child: empty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: 280, child: child),
                    ],
                  )
                : child,
          )
        : child;
    final body = widget.cacheKey == null ? refreshable : NxRefreshOverlay(refreshing: _refreshing, child: refreshable);
    if (_error == null) return body;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            tr(formatApiError(_error!)),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

class NxErrorRetry extends StatelessWidget {
  const NxErrorRetry({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(formatApiError(error)),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: Text(tr('ลองใหม่'))),
          ],
        ),
      ),
    );
  }
}
