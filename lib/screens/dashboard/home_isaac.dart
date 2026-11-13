import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai_assistant.dart';
import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/thai_time.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../ai/assistant/ai_assistant_controller.dart' show aiErrorText;
import 'home_boxes.dart' show HomeCardShadow, homeCardFill, kHomeCardRadius;

// ─────────────────────────── data ───────────────────────────

/// One thing ISAAC is told about the day. With a [route] it gets a short
/// reference (`r1`, `r2` …) in the prompt, so a bullet about it can open it.
@immutable
class IsaacFact {
  const IsaacFact(this.text, {this.route});
  final String text;
  final String? route;
}

/// One bullet of the summary; [route] opens the record it is about.
@immutable
class IsaacBriefItem {
  const IsaacBriefItem(this.text, {this.route});
  final String text;
  final String? route;

  Map<String, dynamic> toJson() => {'t': text, if (route != null) 'r': route};

  static IsaacBriefItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = '${j['t'] ?? ''}'.trim();
    if (t.isEmpty) return null;
    final r = j['r'];
    return IsaacBriefItem(t, route: r is String && r.startsWith('/') ? r : null);
  }

  @override
  bool operator ==(Object other) => other is IsaacBriefItem && other.text == text && other.route == route;

  @override
  int get hashCode => Object.hash(text, route);

  @override
  String toString() => 'IsaacBriefItem($text${route == null ? '' : ' → $route'})';
}

/// ISAAC's summary of one day (Thai calendar day).
@immutable
class IsaacBrief {
  const IsaacBrief({required this.day, required this.at, required this.items});
  final String day;
  final DateTime at;
  final List<IsaacBriefItem> items;

  Map<String, dynamic> toJson() => {
        'day': day,
        'at': at.toIso8601String(),
        'items': [for (final i in items) i.toJson()],
      };

  static IsaacBrief? fromJson(Object? j) {
    if (j is! Map) return null;
    final day = '${j['day'] ?? ''}';
    final at = DateTime.tryParse('${j['at'] ?? ''}');
    final items = [
      for (final r in (j['items'] is List ? j['items'] as List : const []))
        ?IsaacBriefItem.fromJson(r),
    ];
    if (day.isEmpty || at == null || items.isEmpty) return null;
    return IsaacBrief(day: day, at: at, items: items);
  }
}

/// `yyyy-mm-dd` of [d] (the Thai wall-clock day the summary belongs to).
String isaacDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The day's summary, kept per server + user + business ([AppConfig.businessScope])
/// in memory and on the device: reopening Home shows it without asking ISAAC again;
/// a new day (or the refresh button) asks again.
class IsaacBriefCache {
  IsaacBriefCache._();

  static final Map<String, IsaacBrief> _mem = {};
  static final Set<String> _expanded = {};

  static String prefsKey(String scope) => 'nx_isaac_brief_v1_$scope';

  /// Today's summary already in memory (no I/O), else null.
  static IsaacBrief? peek(String scope, {DateTime? now}) {
    final b = _mem[scope];
    if (b == null || b.day != isaacDayKey(now ?? thaiNow())) return null;
    return b;
  }

  /// Today's summary from memory or the device, else null.
  static Future<IsaacBrief?> read(String scope, {DateTime? now}) async {
    final day = isaacDayKey(now ?? thaiNow());
    final m = peek(scope, now: now);
    if (m != null) return m;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(prefsKey(scope));
      if (raw == null) return null;
      final b = IsaacBrief.fromJson(jsonDecode(raw));
      if (b == null || b.day != day) return null;
      _mem[scope] = b;
      return b;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String scope, IsaacBrief b) async {
    _mem[scope] = b;
    try {
      await (await SharedPreferences.getInstance()).setString(prefsKey(scope), jsonEncode(b.toJson()));
    } catch (_) {}
  }

  /// Whether the card was left open (this app run), so coming back to Home keeps it.
  static bool wasExpanded(String scope) => _expanded.contains(scope);
  static void setExpanded(String scope, bool open) => open ? _expanded.add(scope) : _expanded.remove(scope);

  @visibleForTesting
  static void clearMemory() {
    _mem.clear();
    _expanded.clear();
  }
}

// ─────────────────────────── prompt + parsing ───────────────────────────

/// Reference id of fact [i] (only facts with a route get one).
String _ref(int i) => 'r${i + 1}';

/// What Home sends to ISAAC (`POST /api/ai/chat`): today's facts from the
/// Home data, with a short reference on each record so a bullet can open it.
String isaacBriefPrompt(List<IsaacFact> facts, DateTime now) {
  final b = StringBuffer()
    ..writeln('สรุปวันนี้ของฉันให้สั้นที่สุดจากข้อมูลด้านล่าง เป็นข้อๆ 3–5 ข้อ ภาษาไทย')
    ..writeln('- แต่ละข้อขึ้นต้นด้วย "- " ยาวไม่เกินหนึ่งประโยค เรียงจากสิ่งที่ควรทำก่อน')
    ..writeln('- ถ้าข้อไหนพูดถึงรายการที่มีรหัส [[r…]] ให้ใส่รหัสนั้นไว้ท้ายข้อ เช่น "- โทรติดตามลูกค้า A [[r2]]"')
    ..writeln('- ไม่ต้องมีหัวข้อ คำเกริ่น หรือคำลงท้าย และห้ามสร้างหรือแก้ไขข้อมูลใดๆ')
    ..writeln('- ถ้าไม่มีอะไรค้าง ให้แนะนำสิ่งที่ควรทำต่อสั้นๆ')
    ..writeln()
    ..writeln('วันนี้: ${isaacDayKey(now)} เวลา ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');
  for (var i = 0; i < facts.length; i++) {
    final f = facts[i];
    b.writeln(f.route == null ? '- ${f.text}' : '- ${f.text} [[${_ref(i)}]]');
  }
  if (facts.isEmpty) b.writeln('- (ยังไม่มีงานค้างหรือนัดหมายวันนี้)');
  return b.toString().trim();
}

final _refTag = RegExp(r'\[\[\s*(r\d+)\s*\]\]');
final _bulletLead = RegExp(r'^\s*(?:[-*•·–]|\d+[.)])\s+');

/// ISAAC's reply → bullets. Lines that start like a list item become items
/// (a reply with none: every non-empty line); `[[rN]]` resolves to the fact's
/// route; markdown bold / headings are stripped.
List<IsaacBriefItem> parseIsaacBrief(String reply, List<IsaacFact> facts) {
  final lines = reply.split('\n').map((l) => l.trimRight()).where((l) => l.trim().isNotEmpty).toList();
  final bullets = lines.where(_bulletLead.hasMatch).toList();
  final use = bullets.isNotEmpty ? bullets : lines.where((l) => !l.trimLeft().startsWith('#')).toList();
  final out = <IsaacBriefItem>[];
  for (final l in use) {
    String? route;
    for (final m in _refTag.allMatches(l)) {
      final i = int.tryParse(m.group(1)!.substring(1));
      if (i != null && i >= 1 && i <= facts.length) route ??= facts[i - 1].route;
    }
    var t = l.replaceFirst(_bulletLead, '').replaceAll(_refTag, '').replaceAll('**', '').replaceAll('__', '');
    t = t.replaceFirst(RegExp(r'^#+\s*'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) continue;
    out.add(IsaacBriefItem(t, route: route));
  }
  return out;
}

/// `POST /api/ai/chat` body for the Home summary: the same streaming chat the
/// assistant uses (auto model), no saved conversation, no tools and no CRM dump
/// — the facts come from Home.
Map<String, dynamic> isaacBriefBody(List<IsaacFact> facts, DateTime now) => {
      ...aiChatBody(
        history: [
          {'role': 'system', 'content': kAiSystemHint},
          {'role': 'user', 'content': isaacBriefPrompt(facts, now)},
        ],
        conversationId: null,
        injectContext: false,
      ),
      'enable_tools': false,
      'temperature': 0.4,
    };

/// Thai message for a failed summary (quota, AI not set up, offline …).
String isaacErrorText(Object e) {
  if (e is ApiEnvelopeException) {
    final c = e.errorCode.toUpperCase();
    if (c.contains('FEATURE_DISABLED') || c.contains('PROVIDER_DISABLED') || c.contains('NOT_CONFIGURED') || c.contains('AUTO_NO_MODEL') || c.contains('NO_KEY')) {
      return 'ยังไม่ได้ตั้งค่า AI สำหรับธุรกิจนี้ — ให้ผู้ดูแลเปิดใช้และตั้งค่าผู้ให้บริการ AI';
    }
    if (c.contains('QUOTA_EXHAUSTED') || c.contains('QUOTA_EXCEEDED')) return 'โควตา AI เดือนนี้หมดแล้ว — ติดต่อผู้ดูแลเพื่อเพิ่มแพ็กเกจ';
    if (c.contains('DAILY_EXHAUSTED')) return 'โควตา AI วันนี้หมดแล้ว — ลองใหม่พรุ่งนี้ หรือให้ผู้ดูแลเพิ่มโควตา';
    if (c.contains('RATE_LIMIT')) return 'ส่งคำขอถี่เกินไป — รอสักครู่แล้วลองใหม่';
    if (c.contains('BILLING')) return 'ผู้ให้บริการ AI ปฏิเสธการใช้งาน (การชำระเงิน) — ติดต่อผู้ดูแล';
    if (e.statusCode == 403) return 'คุณไม่มีสิทธิ์ใช้ AI Assistant';
  }
  if (e is ApiException) {
    if (e.statusCode == 0) return 'เชื่อมต่อไม่สำเร็จ — ตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
    if (e.statusCode == 401) return e.userMessage;
    return 'ไอแซคสรุปไม่สำเร็จ (${e.statusCode}) — ลองใหม่อีกครั้ง';
  }
  final t = e is ApiEnvelopeException ? aiErrorText(e) : '';
  return t.trim().isEmpty ? 'ไอแซคสรุปไม่สำเร็จ — ลองใหม่อีกครั้ง' : t;
}

// ─────────────────────────── widget ───────────────────────────

/// "ไอแซคแนะนำ" Home widget: a one-line hint; tap → opens in place and ISAAC
/// summarises the day right here (bullets that open their record, refresh,
/// "ถามต่อในไอแซค"). The day's summary is cached per business + user.
class IsaacBriefCard extends StatefulWidget {
  const IsaacBriefCard({super.key, required this.suggestion, required this.facts});

  /// One-line hint shown while closed (from the Home data, no AI call).
  final String suggestion;

  /// Today's facts, read when ISAAC is asked.
  final List<IsaacFact> Function() facts;

  @override
  State<IsaacBriefCard> createState() => _IsaacBriefCardState();
}

class _IsaacBriefCardState extends State<IsaacBriefCard> {
  late final String _scope;
  bool _expanded = false;
  IsaacBrief? _brief;
  bool _loading = false;
  String _streamed = '';
  List<IsaacFact> _asked = const [];
  String? _error;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    _scope = context.read<AppConfig>().businessScope;
    _brief = IsaacBriefCache.peek(_scope);
    _expanded = IsaacBriefCache.wasExpanded(_scope);
    if (_expanded && _brief == null) WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    final open = !_expanded;
    setState(() => _expanded = open);
    IsaacBriefCache.setExpanded(_scope, open);
    if (open) _open();
  }

  /// Opened: today's cached summary, else ask ISAAC.
  Future<void> _open() async {
    if (!mounted || _loading) return;
    if (_brief != null && _brief!.day == isaacDayKey(thaiNow())) return;
    final cached = await IsaacBriefCache.read(_scope);
    if (!mounted) return;
    if (cached != null) {
      setState(() => _brief = cached);
      return;
    }
    await _ask();
  }

  Future<void> _ask() async {
    if (_loading) return;
    final config = context.read<AppConfig>();
    final now = thaiNow();
    final facts = widget.facts();
    final cancel = _cancel = CancelToken();
    setState(() {
      _loading = true;
      _error = null;
      _streamed = '';
      _asked = facts;
    });
    try {
      Map<String, dynamic>? done;
      Object? streamError;
      await for (final ev in config.apiClient.streamAiChat(isaacBriefBody(facts, now), cancel: cancel)) {
        if (!mounted || cancel.isCancelled) return;
        switch (ev.type) {
          case 'token':
            setState(() => _streamed += ev.token);
          case 'done':
            done = ev.data;
          case 'error':
            streamError ??= ApiEnvelopeException(500, '${ev.data['error_code'] ?? 'AI_ERROR'}', '${ev.data['message'] ?? ''}');
        }
      }
      if (!mounted || cancel.isCancelled) return;
      if (streamError != null) throw streamError;
      final msg = done?['message'];
      final full = msg is Map && '${msg['content'] ?? ''}'.trim().isNotEmpty ? '${msg['content']}' : _streamed;
      final items = parseIsaacBrief(full, facts);
      if (items.isEmpty) throw const _EmptyBrief();
      final brief = IsaacBrief(day: isaacDayKey(now), at: now, items: items);
      await IsaacBriefCache.write(_scope, brief);
      if (!mounted) return;
      setState(() {
        _brief = brief;
        _loading = false;
        _streamed = '';
      });
    } catch (e) {
      if (!mounted || cancel.isCancelled) return;
      setState(() {
        _loading = false;
        _streamed = '';
        _error = e is _EmptyBrief ? 'ไอแซคยังไม่มีสรุปให้ตอนนี้ — ลองใหม่อีกครั้ง' : isaacErrorText(e);
      });
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final motion = Duration(milliseconds: reduce ? 0 : 280);

    final header = Semantics(
      button: true,
      expanded: _expanded,
      label: '${tr('ไอแซคแนะนำ')}: ${tr(widget.suggestion)}',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('home-isaac'),
        borderRadius: BorderRadius.circular(kHomeCardRadius),
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const _IsaacAvatar(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('ไอแซคแนะนำ'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      tr(_expanded ? 'สรุปวันนี้ของคุณ' : widget.suggestion),
                      key: const ValueKey('home-isaac-text'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                key: const ValueKey('home-isaac-toggle'),
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: dark ? Colors.white : const Color(0xFF0F172A), shape: BoxShape.circle),
                child: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: motion,
                  curve: Curves.easeOutCubic,
                  child: Icon(NxI.caretDown, size: 18, color: dark ? const Color(0xFF0F172A) : Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return HomeCardShadow(
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: homeCardFill(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              AnimatedSize(
                duration: motion,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _expanded ? _body(theme, cs, motion) : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeData theme, ColorScheme cs, Duration motion) {
    final Widget state;
    if (_error != null && !_loading) {
      state = _ErrorView(key: const ValueKey('home-isaac-error'), message: _error!, onRetry: _ask);
    } else if (_loading) {
      final partial = parseIsaacBrief(_streamed, _asked);
      state = partial.isEmpty
          ? const _BriefSkeleton(key: ValueKey('home-isaac-loading'))
          : _Items(key: const ValueKey('home-isaac-streaming'), items: partial);
    } else if (_brief != null) {
      state = _Items(key: const ValueKey('home-isaac-items'), items: _brief!.items);
    } else {
      state = const _BriefSkeleton(key: ValueKey('home-isaac-loading'));
    }
    final at = _brief?.at;
    return Padding(
      key: const ValueKey('home-isaac-body'),
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: AnimatedSwitcher(duration: motion, child: state),
          ),
          const SizedBox(height: 4),
          // Wraps under large text: time on one line, actions on the next.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  _loading
                      ? tr('ไอแซคกำลังสรุป…')
                      : at == null
                          ? ''
                          : tr('สรุปเมื่อ ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('home-isaac-refresh'),
                    tooltip: tr('สรุปใหม่'),
                    visualDensity: VisualDensity.compact,
                    onPressed: _loading ? null : _ask,
                    icon: Icon(NxI.arrowsClockwise, size: 18, color: _loading ? cs.onSurfaceVariant.withValues(alpha: 0.4) : cs.primary),
                  ),
                  Flexible(
                    child: TextButton(
                      key: const ValueKey('home-isaac-ask'),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      onPressed: () => context.push(AppRoutes.aiChat),
                      child: Text(tr('ถามต่อในไอแซค'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyBrief implements Exception {
  const _EmptyBrief();
}

class _IsaacAvatar extends StatelessWidget {
  const _IsaacAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)]),
      ),
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFF9A8D4), Color(0xFFA5B4FC)]).createShader(r),
        child: const Icon(NxI.sparkleFill, color: Colors.white, size: 22),
      ),
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({super.key, required this.items});
  final List<IsaacBriefItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const violet = Color(0xFF8B5CF6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          InkWell(
            key: ValueKey('home-isaac-item-$i'),
            borderRadius: BorderRadius.circular(12),
            onTap: items[i].route == null ? null : () => context.push(items[i].route!),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: violet, shape: BoxShape.circle)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      items[i].text,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ),
                  if (items[i].route != null) ...[
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(NxI.caretRight, size: 16, color: cs.primary),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BriefSkeleton extends StatelessWidget {
  const _BriefSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget line(double f) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            const NxBone(width: 7, height: 7, radius: 4),
            const SizedBox(width: 10),
            Expanded(child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: f, child: const NxBone(height: 13))),
          ]),
        );
    return Semantics(
      label: tr('ไอแซคกำลังสรุป…'),
      child: NxSkeleton(
        delay: Duration.zero,
        child: Column(children: [line(0.92), line(0.74), line(0.84)]),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(NxI.warningCircle, size: 20, color: cs.error)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(message), key: const ValueKey('home-isaac-error-text'), style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  key: const ValueKey('home-isaac-retry'),
                  onPressed: onRetry,
                  icon: const Icon(NxI.arrowClockwise, size: 16),
                  label: Text(tr('ลองใหม่')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
