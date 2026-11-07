import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import 'package:flutter/services.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_surface_card.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_split_view.dart';
import '../../core/html_display.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_create_fab.dart';
import 'mail_compose_screen.dart';
import 'external_mail_compose_screen.dart';
import '../../services/file_open.dart';
import '../../services/realtime_service.dart';

class MailHomeScreen extends StatefulWidget {
  const MailHomeScreen({super.key});

  @override
  State<MailHomeScreen> createState() => _MailHomeScreenState();
}

const _mailBoxes = <String, String>{
  'inbox': 'กล่องเข้า',
  'sent': 'ส่งแล้ว',
  'drafts': 'ฉบับร่าง',
  'trash': 'ถังขยะ',
};

/// Boxes for a connected Gmail / Outlook mailbox.
const _externalBoxes = <String, String>{
  'inbox': 'กล่องเข้า',
  'starred': 'ติดดาว',
  'sent': 'ส่งแล้ว',
  'drafts': 'ฉบับร่าง',
  'archive': 'เก็บถาวร',
  'trash': 'ถังขยะ',
};

class _MailHomeScreenState extends State<MailHomeScreen> {
  var _box = 'inbox';
  Map<String, dynamic>? _selected;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  bool _searching = false;
  String _query = '';
  StreamSubscription<RealtimeEvent>? _live;
  Timer? _debounce;

  List<MailAccount> _accounts = const [];
  MailAccount? _account;
  final List<Map<String, dynamic>> _items = [];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _syncing = false;
  Object? _error;
  int _gen = 0;

  Map<String, String> get _boxes =>
      _account == null ? _mailBoxes : _externalBoxes;

  @override
  void initState() {
    super.initState();
    // External mail → 'mail:new'; internal mail arrives as a mail notification.
    _live = RealtimeService.instance.events.where(isMailRealtimeEvent).listen((
      _,
    ) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), () {
        if (mounted && (_box == 'inbox' || _box == 'drafts') && _query.isEmpty)
          _reload(keepSelection: true);
      });
    });
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400)
        _loadMore();
    });
    _loadAccounts();
    _reload();
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final list = await context.read<AppConfig>().apiClient.getMailAccounts();
      if (mounted) setState(() => _accounts = list);
    } catch (_) {
      // Server without connections (or no permission) → internal mail only.
    }
  }

  Future<void> _reload({bool keepSelection = false}) async {
    final gen = ++_gen;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
      if (!keepSelection) _selected = null;
    });
    final api = context.read<AppConfig>().apiClient;
    try {
      if (_query.isNotEmpty && _account == null) {
        final rows = await api.searchMail(_query);
        if (!mounted || gen != _gen) return;
        setState(() {
          _items
            ..clear()
            ..addAll(rows);
          _cursor = null;
          _syncing = false;
        });
      } else {
        // Internal mail lists are capped at 200 by the server (no paging there).
        final page = await api.getMailPage(
          box: _box,
          account: _account,
          limit: _account == null ? 200 : 40,
        );
        if (!mounted || gen != _gen) return;
        var rows = page.items;
        if (_query.isNotEmpty) {
          final q = _query.toLowerCase();
          rows = rows
              .where(
                (m) =>
                    '${m['subject']} ${m['snippet']} ${m['from_display']} ${m['from_email']}'
                        .toLowerCase()
                        .contains(q),
              )
              .toList();
        }
        setState(() {
          _items
            ..clear()
            ..addAll(rows);
          _cursor = page.nextCursor;
          _syncing = page.syncing;
        });
      }
    } catch (e) {
      if (mounted && gen == _gen) setState(() => _error = e);
    } finally {
      if (mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (_loadingMore || cursor == null || _query.isNotEmpty) return;
    setState(() => _loadingMore = true);
    final gen = _gen;
    try {
      final page = await context.read<AppConfig>().apiClient.getMailPage(
        box: _box,
        account: _account,
        cursor: cursor,
        limit: 40,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
      });
    } catch (_) {
      // Keep what we have; pull-to-refresh retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _setBox(String box) {
    setState(() {
      _box = box;
      _items.clear();
    });
    _reload();
  }

  Future<void> _pickAccount() async {
    final picked = await showAppBottomSheet<Object>(
      context: context,
      title: 'เลือกกล่องเมล',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(NxI.envelope)),
            title: const Text('เมลภายใน NEXTX'),
            subtitle: const Text('ส่งหาคนในธุรกิจ'),
            trailing: _account == null ? const Icon(NxI.check) : null,
            onTap: () => Navigator.pop(context, 'internal'),
          ),
          for (final a in _accounts)
            ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    (a.provider == 'outlook'
                            ? NxBrandColor.outlook
                            : NxBrandColor.gmail)
                        .withValues(alpha: 0.12),
                child: Icon(
                  a.provider == 'outlook' ? NxI.brandOutlook : NxI.brandGmail,
                  size: 20,
                  color: a.provider == 'outlook'
                      ? NxBrandColor.outlook
                      : NxBrandColor.gmail,
                ),
              ),
              title: Text(a.email.isEmpty ? a.providerLabel : a.email),
              subtitle: Text(
                [
                  a.providerLabel,
                  if (a.readOnly) 'อ่านอย่างเดียว',
                  if (a.status != null && a.status != 'active') a.status!,
                ].join(' · '),
              ),
              trailing: _account == a ? const Icon(NxI.check) : null,
              onTap: () => Navigator.pop(context, a),
            ),
          if (_accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'ยังไม่ได้เชื่อม Gmail / Outlook — เชื่อมได้ที่เว็บ เมนูเมล → ตั้งค่าบัญชี',
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _account = picked is MailAccount ? picked : null;
      if (!_boxes.containsKey(_box)) _box = 'inbox';
      _items.clear();
    });
    _reload();
  }

  Future<void> _compose() async {
    final sent = await nxPush<bool>(
      context,
      _account == null
          ? const MailComposeScreen()
          : ExternalMailComposeScreen(account: _account!),
    );
    if (sent == true && mounted) _reload();
  }

  Future<void> _open(Map<String, dynamic> m, bool twoPane) async {
    if (_box == 'drafts' && _account == null) {
      final api = context.read<AppConfig>().apiClient;
      Map<String, dynamic> full = m;
      try {
        full = await api.getMailItem(m['id']?.toString() ?? '');
      } catch (_) {
        // Fall back to the list row; the server re-validates on save.
      }
      if (!mounted) return;
      final done = await nxPush<bool>(
        context,
        MailComposeScreen(mode: MailComposeMode.draft, original: full),
      );
      if (done == true && mounted) _reload();
      return;
    }
    // Opening marks it read: update the row now instead of reloading.
    if (isMailUnread(m, _box))
      setState(() => m['read_at'] = DateTime.now().toIso8601String());
    if (twoPane) {
      setState(() => _selected = m);
      return;
    }
    final changed = await nxPush<bool>(
      context,
      MailDetailScreen(
        id: m['id']?.toString() ?? '',
        preview: m,
        box: _box,
        account: _account,
      ),
    );
    if (mounted && changed == true) _reload();
  }

  void _removeRow(Map<String, dynamic> m) => setState(() => _items.remove(m));

  Future<void> _rowAction(
    Future<void> Function() call, {
    String? done,
    Map<String, dynamic>? remove,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (remove != null) _removeRow(remove);
    try {
      await call();
      if (done != null)
        messenger.showSnackBar(
          SnackBar(content: Text(done), duration: const Duration(seconds: 2)),
        );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(formatApiError(e))));
      _reload();
    }
  }

  Future<void> _toggleStar(Map<String, dynamic> m) async {
    final acc = _account;
    if (acc == null) return;
    final next = !(m['starred'] == true);
    HapticFeedback.selectionClick();
    setState(() => m['starred'] = next);
    try {
      await context.read<AppConfig>().apiClient.setMailStarred(
        m['id'].toString(),
        next,
        account: acc,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => m['starred'] = !next);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final twoPane = NxBreakpoint.of(context).twoPane;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final acc = _account;
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'เมล',
        subtitle: acc == null
            ? 'เมลภายใน NEXTX'
            : '${acc.providerLabel} · ${acc.email}',
        actions: [
          IconButton(
            tooltip: _searching ? 'ปิดค้นหา' : 'ค้นหาเมล',
            icon: Icon(_searching ? NxI.x : NxI.magnifyingGlass),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _search.clear();
                  _query = '';
                }
              });
              if (!_searching) _reload();
            },
          ),
          IconButton(
            tooltip: 'เลือกกล่องเมล',
            onPressed: _pickAccount,
            icon: const Icon(NxI.tray),
          ),
          IconButton(
            tooltip: 'เปิดเว็บเมล',
            onPressed: () async {
              final base = context.read<AppConfig>().apiBaseUrl.replaceAll(
                RegExp(r'/+$'),
                '',
              );
              final uri = Uri.parse('$base/mail');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(NxI.arrowSquareOut),
          ),
          // The FAB hides on wide layouts; keep compose reachable on tablets.
          if (twoPane) NxAddButton(tooltip: 'เขียนเมล', onPressed: _compose),
        ],
      ),
      floatingActionButton: NxCreateFab(label: 'เขียน', onPressed: _compose),
      body: Column(
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'ค้นหาหัวข้อ เนื้อหา หรือผู้ส่ง',
                  prefixIcon: const Icon(NxI.magnifyingGlass),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (v) {
                  setState(() => _query = v.trim());
                  _reload();
                },
              ),
            ),
          if (_query.isEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  for (final e in _boxes.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: _box == e.key,
                        showCheckmark: false,
                        onSelected: (_) => _setBox(e.key),
                      ),
                    ),
                ],
              ),
            ),
          if (_syncing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'กำลังซิงก์เมลจาก ${acc?.providerLabel ?? ''}…',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          Expanded(child: _listBody(theme, cs, twoPane)),
        ],
      ),
    );
  }

  Widget _listBody(ThemeData theme, ColorScheme cs, bool twoPane) {
    if (_loading && _items.isEmpty) return const NxSkeletonList();
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatApiError(_error!), textAlign: TextAlign.center),
            TextButton(onPressed: _reload, child: const Text('ลองใหม่')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          children: [
            SizedBox(
              height: 260,
              child: Center(
                child: Text(
                  _query.isNotEmpty
                      ? 'ไม่พบเมลที่ตรงกับ "$_query"'
                      : 'ไม่มีจดหมายใน${_boxes[_box]}',
                ),
              ),
            ),
          ],
        ),
      );
    }
    final acc = _account;
    final list = RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length)
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          final m = _items[i];
          final id = m['id']?.toString() ?? '';
          final unread = isMailUnread(m, _box);
          final tile = _MailRow(
            m: m,
            box: _box,
            unread: unread,
            showStar: acc != null,
            onStar: () => _toggleStar(m),
            onTap: () => _open(m, twoPane),
          );
          if (id.isEmpty || _box == 'drafts') return tile;
          final api = context.read<AppConfig>().apiClient;
          // Swipe right: archive (Gmail/Outlook) or mark read/unread; swipe left: trash.
          return Dismissible(
            key: ValueKey('mail-${acc?.id ?? 'in'}-$_box-$id'),
            background: _swipeBg(
              acc != null && _box != 'archive'
                  ? const Color(0xFF16A34A)
                  : cs.primary,
              acc != null && _box != 'archive' ? NxI.archive : NxI.envelopeOpen,
              acc != null && _box != 'archive'
                  ? 'เก็บถาวร'
                  : (unread ? 'อ่านแล้ว' : 'ยังไม่อ่าน'),
              Alignment.centerLeft,
            ),
            secondaryBackground: _swipeBg(
              cs.error,
              NxI.trash,
              _box == 'trash' ? 'ลบถาวร' : 'ลบ',
              Alignment.centerRight,
            ),
            confirmDismiss: (dir) async {
              HapticFeedback.mediumImpact();
              if (dir == DismissDirection.startToEnd) {
                if (acc != null && _box != 'archive') {
                  _rowAction(
                    () => api.archiveMail(id, account: acc),
                    done: 'เก็บถาวรแล้ว',
                    remove: m,
                  );
                  return false;
                }
                setState(
                  () => m['read_at'] = unread
                      ? DateTime.now().toIso8601String()
                      : null,
                );
                _rowAction(
                  () => unread
                      ? api.markMailRead(id, account: acc)
                      : api.markMailUnread(id, account: acc),
                );
                return false;
              }
              _rowAction(
                () => api.deleteMail(
                  id,
                  permanent: _box == 'trash',
                  account: acc,
                ),
                done: _box == 'trash' ? 'ลบถาวรแล้ว' : 'ย้ายไปถังขยะแล้ว',
                remove: m,
              );
              return false;
            },
            child: tile,
          );
        },
      ),
    );
    return NxSplitView(
      list: list,
      detail: _selected == null
          ? null
          : MailDetailScreen(
              key: ValueKey(_selected!['id']),
              id: _selected!['id']?.toString() ?? '',
              preview: _selected!,
              box: _box,
              account: _account,
              embedded: true,
              onChanged: _reload,
            ),
    );
  }

  Widget _swipeBg(Color color, IconData icon, String label, Alignment align) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: align,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inbox-style row: avatar initial, sender, time, subject, snippet, star.
class _MailRow extends StatelessWidget {
  const _MailRow({
    required this.m,
    required this.box,
    required this.unread,
    required this.showStar,
    required this.onStar,
    required this.onTap,
  });

  final Map<String, dynamic> m;
  final String box;
  final bool unread;
  final bool showStar;
  final VoidCallback onStar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final who = mailCounterparty(m, box);
    final subject = m['subject']?.toString().trim().isNotEmpty == true
        ? m['subject'].toString()
        : '(ไม่มีหัวข้อ)';
    final snippet = stripHtmlPreview(
      m['snippet']?.toString() ?? m['body_text']?.toString() ?? '',
      maxLen: 120,
    );
    final starred = m['starred'] == true;
    final count = (m['thread_count'] as num?)?.toInt() ?? 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: NxSurfaceCard(
        radius: 18,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NxAvatar(label: who.isEmpty ? '?' : who, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (unread) ...[
                        Icon(Icons.circle, size: 9, color: cs.primary),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          [
                            who.isEmpty ? '—' : who,
                            if (count > 1) '($count)',
                          ].join(' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        mailShortTime(m['sent_at'] ?? m['created_at']),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (snippet.isNotEmpty)
                    Text(
                      snippet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                if (showStar)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: starred ? 'เอาดาวออก' : 'ติดดาว',
                    onPressed: onStar,
                    icon: Icon(
                      starred ? NxI.starFill : NxI.star,
                      size: 20,
                      color: starred
                          ? const Color(0xFFF59E0B)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                if (m['has_attachments'] == true)
                  Icon(NxI.paperclip, size: 16, color: cs.onSurfaceVariant),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// `7 พ.ย. 2569 · 14:05` (local time).
String mailLongTime(dynamic raw) {
  final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (d == null) return raw?.toString() ?? '';
  const m = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];
  return '${d.day} ${m[d.month - 1]} ${d.year + 543} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// `14:05` today, `7 พ.ย.` otherwise.
String mailShortTime(dynamic raw) {
  final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
  const m = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];
  return '${d.day} ${m[d.month - 1]}';
}

/// Inbox rows have `read_at == null` until the recipient opens them.
bool isMailUnread(Map<String, dynamic> m, String box) =>
    box == 'inbox' && m.containsKey('read_at') && m['read_at'] == null;

/// "From" for received mail, "To" for sent mail.
String mailCounterparty(Map<String, dynamic> m, String box) {
  if (box == 'sent' || box == 'drafts') {
    final to = m['to_display']?.toString() ?? '';
    return to.isEmpty ? '' : 'ถึง $to';
  }
  final name =
      m['from_display']?.toString() ??
      [
            m['from_first_name'] ?? m['first_name'],
            m['from_last_name'] ?? m['last_name'],
          ]
          .where((e) => e != null && e.toString().trim().isNotEmpty)
          .join(' ')
          .trim();
  if (name.isNotEmpty) return name;
  return m['from_email']?.toString() ??
      m['from_name']?.toString() ??
      m['from']?.toString() ??
      '';
}

class MailDetailScreen extends StatefulWidget {
  const MailDetailScreen({
    super.key,
    required this.id,
    required this.preview,
    this.box = 'inbox',
    this.account,
    this.embedded = false,
    this.onChanged,
  });
  final String id;
  final Map<String, dynamic> preview;
  final String box;

  /// Connected Gmail / Outlook mailbox; null = internal NEXTX mail.
  final MailAccount? account;
  final bool embedded;

  /// Called after delete/restore when shown embedded (two-pane).
  final VoidCallback? onChanged;

  @override
  State<MailDetailScreen> createState() => _MailDetailScreenState();
}

class _MailDetailScreenState extends State<MailDetailScreen> {
  Map<String, dynamic>? _item;
  Object? _error;
  List<Map<String, dynamic>> _attachments = const [];
  bool? _starred;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MailDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _item = null;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    final api = context.read<AppConfig>().apiClient;
    try {
      final item = await api.getMailItem(widget.id, account: widget.account);
      if (mounted) setState(() => _item = item);
      final acc = widget.account;
      if (acc != null || isMailUnread(widget.preview, widget.box)) {
        api.markMailRead(widget.id, account: acc).catchError((Object e) {
          debugPrint('[mail] mark read: $e');
        });
      }
      final inline = extractMapList(item['attachments']);
      if (inline.isNotEmpty) {
        if (mounted) setState(() => _attachments = inline);
      } else if (acc != null &&
          (item['has_attachments'] == true ||
              widget.preview['has_attachments'] == true)) {
        final rows = await api.getMailAttachments(widget.id, account: acc);
        if (mounted) setState(() => _attachments = rows);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _done() {
    if (widget.embedded) {
      widget.onChanged?.call();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _respond(MailComposeMode mode) async {
    final acc = widget.account;
    final sent = await nxPush<bool>(
      context,
      acc == null
          ? MailComposeScreen(mode: mode, original: _item ?? widget.preview)
          : ExternalMailComposeScreen(
              account: acc,
              mode: mode,
              original: _item ?? widget.preview,
            ),
    );
    if (sent == true && mounted) widget.onChanged?.call();
  }

  Future<void> _act(
    Future<void> Function() call,
    String done, {
    bool close = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await call();
      messenger.showSnackBar(
        SnackBar(content: Text(done), duration: const Duration(seconds: 2)),
      );
      if (close && mounted) _done();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> a) async {
    final api = context.read<AppConfig>().apiClient;
    final acc = widget.account;
    final name = (a['filename'] ?? a['name'] ?? 'file').toString();
    final url = a['url']?.toString();
    try {
      if (acc != null && a['id'] != null) {
        final bytes = await api.downloadMailAttachment(
          widget.id,
          a['id'].toString(),
          account: acc,
        );
        await openFileBytes(bytes, name);
      } else if (url != null && url.isNotEmpty) {
        await launchUrl(
          Uri.parse(api.absoluteUrl(url)),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  Future<void> _delete() async {
    final permanent = widget.box == 'trash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(permanent ? 'ลบถาวร?' : 'ย้ายไปถังขยะ?'),
        content: Text(permanent ? 'ลบแล้วกู้คืนไม่ได้' : 'กู้คืนได้จากถังขยะ'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppConfig>().apiClient.deleteMail(
        widget.id,
        permanent: permanent,
        account: widget.account,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(permanent ? 'ลบถาวรแล้ว' : 'ย้ายไปถังขยะแล้ว')),
      );
      _done();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  Future<void> _restore() async {
    try {
      await context.read<AppConfig>().apiClient.restoreMail(
        widget.id,
        account: widget.account,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กู้คืนแล้ว')));
      _done();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _item ?? widget.preview;
    final acc = widget.account;
    final api = context.read<AppConfig>().apiClient;
    final starred = _starred ?? (data['starred'] == true);
    return NxScrollScaffold(
      insetBody: false,
      header: NxAppHeader(
        title: data['subject']?.toString() ?? 'เมล',
        automaticallyImplyLeading: !widget.embedded,
        menu: [
          NxHeaderMenuItem(
            label: 'ทำเป็นยังไม่อ่าน',
            icon: NxI.envelope,
            onTap: () => _act(
              () => api.markMailUnread(widget.id, account: acc),
              'ทำเป็นยังไม่อ่านแล้ว',
              close: true,
            ),
          ),
          if (acc != null && widget.box != 'archive')
            NxHeaderMenuItem(
              label: 'เก็บถาวร',
              icon: NxI.archive,
              onTap: () => _act(
                () => api.archiveMail(widget.id, account: acc),
                'เก็บถาวรแล้ว',
                close: true,
              ),
            ),
          if (acc != null && widget.box == 'archive')
            NxHeaderMenuItem(
              label: 'ย้ายกลับกล่องเข้า',
              icon: NxI.tray,
              onTap: () => _act(
                () => api.archiveMail(widget.id, account: acc, undo: true),
                'ย้ายกลับกล่องเข้าแล้ว',
                close: true,
              ),
            ),
        ],
        actions: [
          if (acc != null)
            IconButton(
              tooltip: starred ? 'เอาดาวออก' : 'ติดดาว',
              icon: Icon(
                starred ? NxI.starFill : NxI.star,
                color: starred ? const Color(0xFFF59E0B) : null,
              ),
              onPressed: () {
                setState(() => _starred = !starred);
                _act(
                  () => api.setMailStarred(widget.id, !starred, account: acc),
                  starred ? 'เอาดาวออกแล้ว' : 'ติดดาวแล้ว',
                );
              },
            ),
          if (widget.box == 'trash')
            IconButton(
              tooltip: 'กู้คืน',
              onPressed: _restore,
              icon: const Icon(NxI.arrowCounterClockwise),
            ),
          IconButton(
            tooltip: widget.box == 'trash' ? 'ลบถาวร' : 'ลบ',
            onPressed: _delete,
            icon: const Icon(NxI.trash),
          ),
        ],
      ),
      bottomNavigationBar: widget.box == 'trash'
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    if (widget.box != 'sent') ...[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _respond(MailComposeMode.reply),
                          icon: const Icon(NxI.reply),
                          label: const Text('ตอบกลับ'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _respond(MailComposeMode.forward),
                        icon: const Icon(NxI.forward),
                        label: const Text('ส่งต่อ'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16 + NxScrollScaffold.topInset(context),
            16,
            16,
          ),
          children: [
            if (_error != null) Text(formatApiError(_error!)),
            Text(
              mailCounterparty(data, 'inbox'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (_recipientsLine(data).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _recipientsLine(data),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if ((data['sent_at'] ?? data['created_at']) != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  mailLongTime(data['sent_at'] ?? data['created_at']),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            NxHtmlView(
              html:
                  data['body_html']?.toString() ??
                  data['body']?.toString() ??
                  data['body_text']?.toString() ??
                  data['snippet']?.toString() ??
                  '',
            ),
            if (_attachments.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'ไฟล์แนบ (${_attachments.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              for (final a in _attachments)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: const Icon(NxI.paperclip),
                    title: Text(
                      (a['filename'] ?? a['name'] ?? 'file').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: a['size'] == null
                        ? null
                        : Text(_fileSize(a['size'])),
                    trailing: const Icon(NxI.arrowSquareOut, size: 18),
                    onTap: () => _openAttachment(a),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _fileSize(dynamic raw) {
  final n = (raw is num)
      ? raw.toDouble()
      : double.tryParse(raw.toString()) ?? 0;
  if (n >= 1 << 20) return '${(n / (1 << 20)).toStringAsFixed(1)} MB';
  if (n >= 1024) return '${(n / 1024).round()} KB';
  return '${n.round()} B';
}

String _recipientsLine(Map<String, dynamic> m) {
  String names(dynamic raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((e) => (e['display'] ?? e['email'] ?? '').toString())
            .where((e) => e.isNotEmpty)
            .join(', ')
      : '';
  final to = names(m['to']);
  final cc = names(m['cc']);
  return [
    if (to.isNotEmpty) 'ถึง: $to',
    if (cc.isNotEmpty) 'สำเนา: $cc',
  ].join('  ');
}

/// Socket events that mean the mailbox may have changed.
bool isMailRealtimeEvent(RealtimeEvent e) {
  if (e.type == 'mail:new' || e.type == 'mail:updated') return true;
  if (e.type != 'notification') return false;
  final hint = '${e.data['type'] ?? ''} ${e.data['link_path'] ?? ''}'
      .toLowerCase();
  return hint.contains('mail');
}
