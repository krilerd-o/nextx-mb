import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/app_version.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_surface_card.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../widgets/nx_refresh.dart';

/// Thai label + colour for an announcement `type`.
(String, Color) whatsNewType(String? type) {
  switch ((type ?? '').toLowerCase()) {
    case 'feature':
    case 'new':
      return ('ฟีเจอร์ใหม่', const Color(0xFF6366F1));
    case 'improvement':
    case 'improve':
      return ('ปรับปรุง', const Color(0xFF0EA5E9));
    case 'fix':
    case 'bugfix':
      return ('แก้ไข', const Color(0xFF16A34A));
    case 'release':
      return ('เวอร์ชันใหม่', const Color(0xFFEC4899));
    default:
      return ('ประกาศ', const Color(0xFF64748B));
  }
}

/// Release notes from the web ("มีอะไรใหม่"); opening marks them viewed.
class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  List<Map<String, dynamic>>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AppConfig>().apiClient;
    try {
      final rows = await api.getWhatsNew();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _error = null;
      });
      api
          .markWhatsNewViewed([
            for (final r in rows)
              if (int.tryParse('${r['id']}') case final id?) id,
          ])
          .catchError((_) {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _ack(Map<String, dynamic> it) async {
    final id = int.tryParse('${it['id']}');
    if (id == null) return;
    setState(() => it['acknowledged'] = true);
    try {
      await context.read<AppConfig>().apiClient.ackWhatsNew(id);
    } catch (e) {
      if (!mounted) return;
      setState(() => it['acknowledged'] = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final items = _items;
    final rows = <Widget>[const WhatsNewAppHeader()];
    if (_error != null && items == null) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Center(
          child: TextButton(
            onPressed: _load,
            child: Text(tr('${formatApiError(_error!)}\nลองใหม่'), textAlign: TextAlign.center),
          ),
        ),
      ));
    } else if (items == null) {
      rows.add(const NxSkeletonList(padded: false));
    } else if (items.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Center(child: Text(tr('ยังไม่มีประกาศ'), style: theme.textTheme.bodyLarge)),
      ));
    }
    final list = items ?? const <Map<String, dynamic>>[];
    final body = NxRefresh(
      onRefresh: _load,
      child: Builder(
        builder: (context) => ListView.builder(
          padding: EdgeInsets.fromLTRB(16, 8 + NxScrollScaffold.topInset(context), 16, 32),
          itemCount: rows.length + list.length,
          itemBuilder: (context, i) {
            if (i < rows.length) return rows[i];
            final it = list[i - rows.length];
            final (label, color) = whatsNewType(it['type']?.toString());
            final acked = it['acknowledged'] == true;
            final version = '${it['version'] ?? ''}'.trim();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: NxSurfaceCard(
                radius: 22,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                          child: Text(tr(label), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                        if (version.isNotEmpty && version != 'null') ...[
                          const SizedBox(width: 6),
                          Text('v$version', style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            thaiDate(it['date']?.toString().split('T').first ?? '', year: uiYear),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr(trPair(it['title_th'], it['title_en'])),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    // 6 lines, then "ดูเพิ่มเติม"; short notes fit the card.
                    WhatsNewBody(
                      key: ValueKey('wn-body-${it['id'] ?? it['title_th']}'),
                      child: NxHtmlView(html: trPair(it['description_th'], it['description_en'])),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: acked
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(NxI.check, size: 14, color: cs.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(tr('รับทราบแล้ว'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                              ]),
                            )
                          : TextButton(key: ValueKey('wn-ack-${it['id']}'), onPressed: () => _ack(it), child: Text(tr('รับทราบ'))),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    return NxScrollScaffold(
      insetBody: false,
      header: const NxAppHeader(title: 'มีอะไรใหม่'),
      body: body,
    );
  }
}

/// Top of "มีอะไรใหม่": the app's launcher icon and the installed version.
class WhatsNewAppHeader extends StatelessWidget {
  const WhatsNewAppHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      key: const ValueKey('wn-app-header'),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 22),
      child: Column(children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Image.asset('assets/app_icon.png', key: const ValueKey('wn-app-icon'), width: 96, height: 96, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 14),
        Text('MOAI NEXT Mobile', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
          child: Text(
            '${tr('เวอร์ชัน')} ${AppVersion.value}',
            key: const ValueKey('wn-app-version'),
            style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w800),
          ),
        ),
      ]),
    );
  }
}

/// Folds a note to about [lines] lines with a soft fade and a
/// "ดูเพิ่มเติม / ย่อ" toggle; shorter notes simply fit.
class WhatsNewBody extends StatefulWidget {
  const WhatsNewBody({super.key, required this.child, this.lines = 6});
  final Widget child;
  final int lines;

  @override
  State<WhatsNewBody> createState() => _WhatsNewBodyState();
}

class _WhatsNewBodyState extends State<WhatsNewBody> with AutomaticKeepAliveClientMixin {
  bool _open = false;
  double? _full;

  // Keep the measured height / open state when the card scrolls off screen,
  // so coming back does not rebuild and re-measure it (no jumps).
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final line = (style.fontSize ?? 14) * (style.height ?? 1.5);
    final max = line * widget.lines;
    final tall = (_full ?? 0) > max + 4;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            // Folded from the first frame: the card never lays out at full
            // height and then shrinks (that moved the list under the finger
            // when scrolling up). Short notes are smaller than [max] anyway.
            constraints: BoxConstraints(maxHeight: _open ? double.infinity : max),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: tall && !_open ? const [Colors.black, Colors.black, Colors.transparent] : const [Colors.black, Colors.black],
                stops: tall && !_open ? const [0, 0.7, 1] : const [0, 1],
              ).createShader(r),
              child: ClipRect(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: _Measure(
                    onSize: (h) {
                      // Only the "is it long?" answer changes the layout.
                      final wasTall = (_full ?? 0) > max + 4;
                      final isTall = h > max + 4;
                      _full = h;
                      if (wasTall != isTall) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() {}) : null);
                    },
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (tall)
          TextButton(
            key: const ValueKey('wn-more'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: () => setState(() => _open = !_open),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tr(_open ? 'ย่อ' : 'ดูเพิ่มเติม'), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
              const SizedBox(width: 2),
              Icon(_open ? NxI.caretUp : NxI.caretDown, size: 16, color: cs.primary),
            ]),
          ),
      ],
    );
  }
}

/// Reports its child's laid-out height.
class _Measure extends SingleChildRenderObjectWidget {
  const _Measure({required this.onSize, super.child});
  final ValueChanged<double> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasure(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasure renderObject) => renderObject.onSize = onSize;
}

class _RenderMeasure extends RenderProxyBox {
  _RenderMeasure(this.onSize);
  ValueChanged<double> onSize;

  @override
  void performLayout() {
    super.performLayout();
    onSize(size.height);
  }
}
