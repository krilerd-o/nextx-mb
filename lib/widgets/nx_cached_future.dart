import 'package:flutter/material.dart';

import '../services/api_client.dart';
import 'nx_skeleton.dart';
import '../core/i18n.dart';

/// Stale-while-revalidate loader — keeps last data while refreshing.
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
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? skeleton;
  final Widget? empty;
  final bool Function(T data)? isEmpty;
  final int revision;
  final VoidCallback? onRetry;
  final bool refresh;

  @override
  State<NxCachedFuture<T>> createState() => NxCachedFutureState<T>();
}

class NxCachedFutureState<T> extends State<NxCachedFuture<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant NxCachedFuture<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _fetch();
    }
  }

  Future<void> reload() => _fetch();

  Future<void> _fetch() async {
    final had = _data != null;
    if (!had) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }
    try {
      final next = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = next;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
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
        ? RefreshIndicator(
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
    if (_error == null) return refreshable;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            tr(formatApiError(_error!)),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        Expanded(child: refreshable),
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
