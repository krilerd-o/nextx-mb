import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_split_view.dart';
import '../../core/html_display.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_create_fab.dart';
import 'mail_compose_screen.dart';

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

class _MailHomeScreenState extends State<MailHomeScreen> {
  var _revision = 0;
  var _box = 'inbox';
  Map<String, dynamic>? _selected;

  void _reload() => setState(() {
        _revision++;
        _selected = null;
      });

  Future<void> _compose() async {
    final sent = await nxPush<bool>(context, const MailComposeScreen());
    if (sent == true && mounted) _reload();
  }

  Future<void> _open(Map<String, dynamic> m, bool twoPane) async {
    if (_box == 'drafts') {
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
    if (twoPane) {
      setState(() => _selected = m);
      return;
    }
    final changed = await nxPush<bool>(
      context,
      MailDetailScreen(id: m['id']?.toString() ?? '', preview: m, box: _box),
    );
    if (mounted) {
      // Refresh to drop unread styling / removed items.
      if (changed == true || _box == 'inbox') setState(() => _revision++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final twoPane = NxBreakpoint.of(context).twoPane;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: NxAppHeader(
        title: 'เมล',
        subtitle: 'เมลภายใน NEXTX',
        actions: [
          IconButton(
            tooltip: 'เปิดเว็บเมล',
            onPressed: () async {
              final base = context.read<AppConfig>().apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
              final uri = Uri.parse('$base/mail');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(NxI.arrowSquareOut),
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(NxI.arrowCounterClockwise),
          ),
        ],
      ),
      floatingActionButton: NxCreateFab(label: 'เขียน', onPressed: _compose),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                for (final e in _mailBoxes.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _box == e.key,
                      showCheckmark: false,
                      onSelected: (_) => setState(() {
                        _box = e.key;
                        _selected = null;
                        _revision++;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: NxCachedFuture<List<Map<String, dynamic>>>(
              key: ValueKey(_box),
              revision: _revision,
              load: () => context.read<AppConfig>().apiClient.getMail(box: _box, limit: 100),
              skeleton: const NxSkeletonList(),
              isEmpty: (list) => list.isEmpty,
              empty: Center(child: Text('ไม่มีจดหมายใน${_mailBoxes[_box]}')),
              builder: (context, list) {
                final items = RefreshIndicator(
                  onRefresh: () async => setState(() => _revision++),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      for (final m in list)
                        DenseCardTile(
                          title: m['subject']?.toString().trim().isNotEmpty == true
                              ? m['subject'].toString()
                              : '(ไม่มีหัวข้อ)',
                          subtitle: [
                            mailCounterparty(m, _box),
                            stripHtmlPreview(m['snippet']?.toString() ?? m['body_text']?.toString() ?? ''),
                          ].where((e) => e.isNotEmpty).join(' · '),
                          leading: Icon(
                            _box == 'drafts' ? NxI.pencilSimple : NxI.envelope,
                            color: isMailUnread(m, _box) ? theme.colorScheme.primary : null,
                          ),
                          trailing: isMailUnread(m, _box)
                              ? Icon(Icons.circle, size: 10, color: theme.colorScheme.primary)
                              : null,
                          onTap: () => _open(m, twoPane),
                        ),
                    ],
                  ),
                );
                return NxSplitView(
                  list: items,
                  detail: _selected == null
                      ? null
                      : MailDetailScreen(
                          key: ValueKey(_selected!['id']),
                          id: _selected!['id']?.toString() ?? '',
                          preview: _selected!,
                          box: _box,
                          embedded: true,
                          onChanged: _reload,
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
  final name = m['from_display']?.toString() ??
      [m['from_first_name'], m['from_last_name']]
          .where((e) => e != null && e.toString().trim().isNotEmpty)
          .join(' ')
          .trim();
  if (name.isNotEmpty) return name;
  return m['from_email']?.toString() ?? m['from_name']?.toString() ?? m['from']?.toString() ?? '';
}

class MailDetailScreen extends StatefulWidget {
  const MailDetailScreen({
    super.key,
    required this.id,
    required this.preview,
    this.box = 'inbox',
    this.embedded = false,
    this.onChanged,
  });
  final String id;
  final Map<String, dynamic> preview;
  final String box;
  final bool embedded;

  /// Called after delete/restore when shown embedded (two-pane).
  final VoidCallback? onChanged;

  @override
  State<MailDetailScreen> createState() => _MailDetailScreenState();
}

class _MailDetailScreenState extends State<MailDetailScreen> {
  Map<String, dynamic>? _item;
  Object? _error;

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
      final item = await api.getMailItem(widget.id);
      if (mounted) setState(() => _item = item);
      if (isMailUnread(widget.preview, widget.box)) {
        api.markMailRead(widget.id).catchError((Object e) {
          debugPrint('[mail] mark read: $e');
        });
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
    final sent = await nxPush<bool>(
      context,
      MailComposeScreen(mode: mode, original: _item ?? widget.preview),
    );
    if (sent == true && mounted) widget.onChanged?.call();
  }

  Future<void> _delete() async {
    final permanent = widget.box == 'trash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(permanent ? 'ลบถาวร?' : 'ย้ายไปถังขยะ?'),
        content: Text(permanent ? 'ลบแล้วกู้คืนไม่ได้' : 'กู้คืนได้จากถังขยะ'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppConfig>().apiClient.deleteMail(widget.id, permanent: permanent);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(permanent ? 'ลบถาวรแล้ว' : 'ย้ายไปถังขยะแล้ว')),
      );
      _done();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  Future<void> _restore() async {
    try {
      await context.read<AppConfig>().apiClient.restoreMail(widget.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กู้คืนแล้ว')));
      _done();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _item ?? widget.preview;
    return Scaffold(
      appBar: NxAppHeader(
        title: data['subject']?.toString() ?? 'เมล',
        automaticallyImplyLeading: !widget.embedded,
        actions: [
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
                    if (widget.box == 'inbox') ...[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _respond(MailComposeMode.reply),
                          icon: const Icon(Icons.reply),
                          label: const Text('ตอบกลับ'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _respond(MailComposeMode.forward),
                        icon: const Icon(Icons.forward),
                        label: const Text('ส่งต่อ'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
                '${data['sent_at'] ?? data['created_at']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          NxHtmlView(
            html: data['body_html']?.toString() ??
                data['body']?.toString() ??
                data['body_text']?.toString() ??
                data['snippet']?.toString() ??
                '',
          ),
        ],
      ),
    );
  }
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
