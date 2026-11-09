import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/entity_modules.dart';
import '../../core/html_display.dart';
import '../../core/i18n.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_page_route.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_search_debounce.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../crm/entity_detail_screen.dart';
import 'search_modules.dart';

/// One result row, from any source.
class SearchHit {
  const SearchHit({required this.section, required this.title, this.subtitle, required this.icon, this.open, this.color});
  final String section; // key of [SearchSection]
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? color;
  final void Function(BuildContext context)? open;
}

/// Groups shown as filter chips and result sections, in this order.
class SearchSection {
  const SearchSection(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;

  static const all = [
    SearchSection('menu', 'เมนูและคำสั่ง', NxI.squaresFour),
    SearchSection('people', 'คนในทีม', NxI.users),
    SearchSection('customer', 'ลูกค้า', NxI.userCircle),
    SearchSection('sales', 'งานขาย', NxI.handshake),
    SearchSection('service', 'งานบริการ', NxI.wrench),
    SearchSection('activity', 'กิจกรรม', NxI.calendarBlank),
    SearchSection('task', 'งาน Workspace', NxI.kanban),
    SearchSection('chat', 'แชท', NxI.chatCircle),
    SearchSection('mail', 'อีเมล', NxI.envelope),
  ];
}

String searchSectionOf(String module) => switch (module) {
      'lead' || 'contact' || 'account' => 'customer',
      'deal' || 'quotation' || 'product' => 'sales',
      'activity' => 'activity',
      _ => 'service',
    };

/// Menus and quick commands, matched on the device (instant).
class _Command {
  const _Command(this.label, this.icon, this.route, this.words, {this.menu});
  final String label;
  final IconData icon;
  final String route;
  final List<String> words;
  final String? menu; // menu key the user needs
}

const _commands = [
  _Command('ลงเวลาเข้า / ออก', NxI.clock, AppRoutes.attendance, ['ลงเวลา', 'เช็คอิน', 'เข้างาน', 'ออกงาน', 'clock', 'attendance'], menu: MenuAccess.attendance),
  _Command('ขอลา', NxI.calendarCheck, AppRoutes.leaveRequest, ['ลา', 'ลาป่วย', 'ลากิจ', 'พักร้อน', 'leave'], menu: MenuAccess.leave),
  _Command('รายการลาของฉัน', NxI.calendarCheck, AppRoutes.leaveList, ['ลา', 'leave'], menu: MenuAccess.leave),
  _Command('ปฏิทินกิจกรรม', NxI.calendarBlank, AppRoutes.calendar, ['ปฏิทิน', 'นัด', 'กิจกรรม', 'calendar'], menu: MenuAccess.calendar),
  _Command('รออนุมัติ', NxI.checkCircle, AppRoutes.approvals, ['อนุมัติ', 'approve'], menu: MenuAccess.pendingApprovals),
  _Command('แชท', NxI.chatCircle, AppRoutes.chatHome, ['แชท', 'ข้อความ', 'chat'], menu: MenuAccess.chat),
  _Command('อีเมล', NxI.envelope, AppRoutes.mail, ['เมล', 'อีเมล', 'mail'], menu: MenuAccess.mailbox),
  _Command('ไฟล์', NxI.folder, AppRoutes.files, ['ไฟล์', 'เอกสาร', 'file'], menu: MenuAccess.files),
  _Command('Workspace', NxI.kanban, AppRoutes.workspaceHome, ['งาน', 'บอร์ด', 'workspace', 'task'], menu: MenuAccess.workspace),
  _Command('งานช่าง / งานบริการของฉัน', NxI.wrench, AppRoutes.jobs, ['งานช่าง', 'job', 'บริการ'], menu: MenuAccess.job),
  _Command('ผู้ช่วย AI', NxI.robot, AppRoutes.aiChat, ['ai', 'ผู้ช่วย', 'ถาม'], menu: MenuAccess.ai),
  _Command('แจ้งเตือน', NxI.bell, AppRoutes.notifications, ['แจ้งเตือน', 'notification']),
  _Command('โปรไฟล์', NxI.user, AppRoutes.profile, ['โปรไฟล์', 'รหัสผ่าน', 'profile', 'password']),
  _Command('การตั้งค่า', NxI.gear, AppRoutes.settings, ['ตั้งค่า', 'ธีม', 'ภาษา', 'สี', 'setting']),
];

/// "ค้นหาทุกอย่าง": type once, results stream in by group as each source
/// answers. Built for big data: waits for a short pause in typing, cancels
/// the previous query's requests, asks each source for only a few rows, and
/// remembers recent answers.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  static const perSource = 4;
  static const minChars = 2;
  static final Map<String, Map<String, List<SearchHit>>> _cache = {};

  /// Cached results belong to one business + package.
  String _scoped(String q) {
    final c = context.read<AppConfig>();
    return '${c.businessScope}|p${c.session.packageCode ?? ''}|${q.toLowerCase()}';
  }

  late final _controller = TextEditingController(text: widget.initialQuery ?? '');
  final _focus = FocusNode();
  final _debounce = NxSearchDebounce();
  CancelToken? _cancel;
  int _gen = 0;
  String _query = '';
  String _filter = 'all';
  final Map<String, List<SearchHit>> _hits = {};
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    if ((widget.initialQuery ?? '').isNotEmpty) _schedule(widget.initialQuery!, now: true);
  }

  @override
  void dispose() {
    _debounce.dispose();
    _cancel?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _schedule(String text, {bool now = false}) {
    _debounce.cancel();
    final q = text.trim();
    if (q == _query && !now) return;
    if (q.length < minChars && !_isCode(q)) {
      _cancel?.cancel();
      setState(() {
        _query = q;
        _hits.clear();
        _pending = 0;
      });
      if (q.isNotEmpty) _searchLocal(q, ++_gen);
      return;
    }
    if (now) {
      _run(q);
    } else {
      _debounce.schedule(() => _run(q));
    }
  }

  bool _isCode(String q) => RegExp(r'^\d{3,}$').hasMatch(q);

  Future<void> _run(String q) async {
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    final gen = ++_gen;
    final config = context.read<AppConfig>();
    final session = config.session;
    setState(() {
      _query = q;
      _hits.clear();
    });
    _searchLocal(q, gen);
    final cached = _cache[_scoped(q)];
    if (cached != null) {
      setState(() => _hits.addAll(cached));
      return;
    }
    final api = config.apiClient;
    final jobs = <Future<void>>[];
    void add(String section, Future<List<SearchHit>> Function() fetch) {
      jobs.add(() async {
        try {
          final hits = await fetch().timeout(const Duration(seconds: 8));
          if (gen != _gen || !mounted) return;
          setState(() => (_hits[section] ??= []).addAll(hits));
        } catch (_) {
          // A slow / failing source never blocks the others.
        } finally {
          if (gen == _gen && mounted) setState(() => _pending--);
        }
      }());
    }

    _pending = 0;
    for (final m in globalSearchModulesFor(session)) {
      _pending++;
      add(searchSectionOf(m), () => _entity(api, m, q, cancel));
    }
    if (MenuAccess.allow(session, MenuAccess.workspace)) {
      _pending++;
      add('task', () async {
        final rows = await api.getWorkspaceItems(q: q, limit: perSource, cancel: cancel);
        return [
          for (final r in rows.take(perSource))
            SearchHit(
              section: 'task',
              title: r['title']?.toString() ?? '—',
              subtitle: [
                if ((r['board_code'] ?? '').toString().isNotEmpty) '${r['board_code']}-${r['item_no'] ?? ''}',
                r['status_label_th']?.toString() ?? r['status_name']?.toString() ?? '',
              ].where((e) => e.isNotEmpty).join(' · '),
              icon: NxI.kanban,
              open: r['board_id'] == null ? null : (c) => c.push(AppRoutes.task('${r['board_id']}', '${r['id']}')),
            ),
        ];
      });
    }
    if (MenuAccess.allow(session, MenuAccess.chat)) {
      _pending++;
      add('chat', () async {
        final rows = await api.searchChat(q, limit: perSource, cancel: cancel);
        return [
          for (final m in rows.take(perSource))
            SearchHit(
              section: 'chat',
              title: stripHtmlPreview(m['body']?.toString() ?? m['content']?.toString() ?? '', maxLen: 90),
              subtitle: [m['sender_name']?.toString() ?? '', thaiDate(m['created_at'], year: uiYear)].where((e) => e.isNotEmpty).join(' · '),
              icon: NxI.chatCircle,
              open: m['room_id'] == null ? null : (c) => c.push(AppRoutes.chatRoom('${m['room_id']}')),
            ),
        ];
      });
    }
    if (MenuAccess.allow(session, MenuAccess.mailbox)) {
      _pending++;
      add('mail', () async {
        final rows = await api.searchMail(q, cancel: cancel);
        return [
          for (final m in rows.take(perSource))
            SearchHit(
              section: 'mail',
              title: m['subject']?.toString().trim().isNotEmpty == true ? m['subject'].toString() : tr('(ไม่มีหัวเรื่อง)'),
              subtitle: [m['from_name'] ?? m['sender_name'] ?? m['from'] ?? '', thaiDate(m['date'] ?? m['created_at'], year: uiYear)]
                  .map((e) => '$e')
                  .where((e) => e.isNotEmpty && e != 'null')
                  .join(' · '),
              icon: NxI.envelope,
              open: (c) => c.push(AppRoutes.mail),
            ),
        ];
      });
    }
    setState(() {});
    await Future.wait(jobs);
    if (gen == _gen && mounted) {
      _cache[_scoped(q)] = {for (final e in _hits.entries) if (e.key != 'menu' && e.key != 'people') e.key: [...e.value]};
      if (_cache.length > 30) _cache.remove(_cache.keys.first);
      config.addSearchHistory(q);
    }
  }

  Future<List<SearchHit>> _entity(ApiClient api, String module, String q, CancelToken cancel) async {
    final page = await api.getEntityList(module, limit: perSource, q: q, cancel: cancel, extra: const {'omit_long_text': '1'});
    final section = searchSectionOf(module);
    return [
      for (final row in page.items)
        SearchHit(
          section: section,
          title: entityTitle(row, module: module),
          subtitle: [EntityModules.titleOf(module), entitySubtitle(row, module: module) ?? ''].where((e) => e.isNotEmpty).join(' · '),
          icon: _moduleIcon(module),
          open: (c) {
            final id = strId(row['id']);
            if (module == 'activity') {
              c.push(AppRoutes.activity(id));
              return;
            }
            final loc = EntityModules.isFsm(module) ? AppRoutes.fsmRecord(module, id) : AppRoutes.crmRecord(module, id);
            if (GoRouter.maybeOf(c) != null) {
              c.push(loc);
            } else {
              nxPush<void>(c, EntityDetailScreen(module: module, row: row));
            }
          },
        ),
    ];
  }

  static IconData _moduleIcon(String m) => switch (m) {
        'lead' => NxI.userPlus,
        'contact' => NxI.userCircle,
        'account' => NxI.buildings,
        'deal' => NxI.handshake,
        'quotation' => NxI.receipt,
        'product' => NxI.package,
        'activity' => NxI.calendarBlank,
        _ => NxI.wrench,
      };

  /// Menus + people: matched on the device, so they show instantly.
  Future<void> _searchLocal(String q, int gen) async {
    final config = context.read<AppConfig>();
    final session = config.session;
    final lq = q.toLowerCase();
    final menus = [
      for (final c in _commands)
        if ((c.menu == null || MenuAccess.allow(session, c.menu!)) &&
            (c.label.toLowerCase().contains(lq) || c.words.any((w) => w.toLowerCase().contains(lq) || lq.contains(w.toLowerCase()))))
          SearchHit(section: 'menu', title: c.label, icon: c.icon, open: (ctx) => ctx.push(c.route)),
    ];
    setState(() {
      if (menus.isEmpty) {
        _hits.remove('menu');
      } else {
        _hits['menu'] = menus.take(4).toList();
      }
    });
    try {
      final users = await config.apiClient.getUsersCached();
      if (gen != _gen || !mounted) return;
      final people = <SearchHit>[];
      for (final u in users) {
        final name = [u['first_name'], u['last_name']].where((e) => e != null && '$e'.trim().isNotEmpty).join(' ');
        final hay = [name, u['email1'], u['user_name'], u['phone_mobile']].map((e) => '${e ?? ''}'.toLowerCase()).join(' ');
        if (hay.contains(lq)) {
          people.add(SearchHit(
            section: 'people',
            title: name.isEmpty ? '${u['email1'] ?? u['user_name'] ?? ''}' : name,
            subtitle: [u['email1'], u['phone_mobile']].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
            icon: NxI.user,
          ));
          if (people.length >= perSource) break;
        }
      }
      if (people.isNotEmpty) setState(() => _hits['people'] = people);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final canPop = Navigator.of(context).canPop();
    final sections = [for (final s in SearchSection.all) if ((_hits[s.key] ?? const []).isNotEmpty) s];
    final total = sections.fold<int>(0, (n, s) => n + _hits[s.key]!.length);
    final shown = _filter == 'all' ? sections : sections.where((s) => s.key == _filter).toList();

    final field = TextField(
      key: const ValueKey('search-all-field'),
      controller: _controller,
      focusNode: _focus,
      autofocus: canPop,
      textInputAction: TextInputAction.search,
      onChanged: (v) {
        setState(() {});
        _schedule(v);
      },
      onSubmitted: (v) => _schedule(v, now: true),
      decoration: InputDecoration(
        hintText: tr('ค้นหาลูกค้า เอกสาร งาน แชท อีเมล เมนู…'),
        prefixIcon: const Icon(NxI.magnifyingGlass, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: [
                NxSearchCountdown(debounce: _debounce),
                IconButton(
                  icon: const Icon(NxI.x, size: 18),
                  onPressed: () {
                    _controller.clear();
                    _schedule('');
                    _focus.requestFocus();
                  },
                ),
              ]),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      ),
    );

    Widget hitTile(SearchHit h) => InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: h.open == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  h.open!(context);
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: (h.color ?? cs.primary).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                child: Icon(h.icon, size: 19, color: h.color ?? cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Highlight(text: h.title, query: _query, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  if ((h.subtitle ?? '').isNotEmpty)
                    _Highlight(text: h.subtitle!, query: _query, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              if (h.open != null) Icon(NxI.caretRight, size: 16, color: cs.outline),
            ]),
          ),
        );

    final body = <Widget>[
      if (_query.isEmpty) ..._emptyState(context, config),
      if (_query.isNotEmpty) ...[
        // Group chips: tap to show only that kind.
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${tr('ทั้งหมด')}${total > 0 ? ' $total' : ''}'),
                selected: _filter == 'all',
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = 'all'),
              ),
            ),
            for (final s in sections)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  avatar: Icon(s.icon, size: 16),
                  label: Text('${tr(s.label)} ${_hits[s.key]!.length}'),
                  selected: _filter == s.key,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = _filter == s.key ? 'all' : s.key),
                ),
              ),
          ]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _pending > 0
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(tr('กำลังค้นหาอีก $_pending แหล่ง…'), key: const ValueKey('search-pending'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                )
              : const SizedBox(width: double.infinity),
        ),
        for (final s in shown) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 16, 6, 4),
            child: Row(children: [
              Icon(s.icon, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(tr(s.label), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
            ]),
          ),
          for (final h in _hits[s.key]!) hitTile(h),
        ],
        if (_pending == 0 && sections.isEmpty && (_query.length >= minChars || _isCode(_query)))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(children: [
              Icon(NxI.magnifyingGlass, size: 40, color: cs.outline),
              const SizedBox(height: 8),
              Text(tr('ไม่พบ "$_query"'), key: const ValueKey('search-empty'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(tr('ลองคำสั้นลง ส่วนหนึ่งของชื่อ เบอร์โทร หรือเลขเอกสาร'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
      ],
      const SizedBox(height: 40),
    ];

    return NxScrollScaffold(
      header: canPop ? const NxAppHeader(title: 'ค้นหา') : const NxAppHeader.hub(),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: field),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            children: body,
          ),
        ),
      ]),
    );
  }

  /// Before typing: how to search, and recent searches.
  List<Widget> _emptyState(BuildContext context, AppConfig config) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    void use(String q) {
      _controller.text = q;
      _controller.selection = TextSelection.collapsed(offset: q.length);
      _schedule(q, now: true);
    }

    return [
      if (config.searchHistory.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 0, 0),
          child: Row(children: [
            Expanded(child: Text(tr('ค้นหาล่าสุด'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant))),
            TextButton(onPressed: () => config.clearSearchHistory(), child: Text(tr('ล้าง'))),
          ]),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final q in config.searchHistory.take(10))
            ActionChip(avatar: const Icon(NxI.clockCounterClockwise, size: 16), label: Text(q), onPressed: () => use(q)),
        ]),
        const SizedBox(height: 18),
      ],
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('ค้นหาอะไรได้บ้าง'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final (icon, text) in const [
            (NxI.userCircle, 'ลูกค้า ลีด ผู้ติดต่อ — ชื่อ บริษัท เบอร์โทร อีเมล'),
            (NxI.receipt, 'เอกสาร — เลขใบเสนอราคา เลขเคส เลขงาน'),
            (NxI.kanban, 'งาน Workspace และกิจกรรม — ชื่องาน หัวข้อนัด'),
            (NxI.chatCircle, 'ข้อความแชท และอีเมล'),
            (NxI.squaresFour, 'เมนูและคำสั่ง — เช่น "ลา" "ลงเวลา" "ตั้งค่า"'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(tr(text), style: theme.textTheme.bodyMedium)),
              ]),
            ),
          const SizedBox(height: 6),
          Text(tr('เคล็ดลับ: พิมพ์อย่างน้อย 2 ตัวอักษร ผลลัพธ์จะขึ้นทีละกลุ่มทันทีที่พบ'),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    ];
  }
}

/// Text with the matched part in bold + primary colour.
class _Highlight extends StatelessWidget {
  const _Highlight({required this.text, required this.query, this.style});
  final String text;
  final String query;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final i = query.isEmpty ? -1 : text.toLowerCase().indexOf(query.toLowerCase());
    if (i < 0) return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    final hl = style?.copyWith(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary);
    return Text.rich(
      TextSpan(style: style, children: [
        TextSpan(text: text.substring(0, i)),
        TextSpan(text: text.substring(i, i + query.length), style: hl),
        TextSpan(text: text.substring(i + query.length)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
