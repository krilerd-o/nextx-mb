import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/html_display.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';
import '../../widgets/app_bottom_sheet.dart' show nxSheetHeight;
import '../../widgets/nx_unsaved_guard.dart';

enum MailComposeMode { compose, reply, forward, draft }

/// A NEXTX internal-mail recipient (a member of the current business).
class MailRecipient {
  const MailRecipient({required this.userId, required this.display, this.email});

  final String userId;
  final String display;
  final String? email;

  factory MailRecipient.fromUser(Map<String, dynamic> u) {
    final id = u['id']?.toString() ?? u['user_id']?.toString() ?? '';
    return MailRecipient(userId: id, display: userDisplayName(u), email: userEmail(u));
  }

  @override
  bool operator ==(Object other) => other is MailRecipient && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
}

/// Builds the initial fields for reply / forward / draft so the logic is testable.
class MailComposeSeed {
  const MailComposeSeed({this.to = const [], this.cc = const [], this.subject = '', this.body = '', this.quotedHtml, this.draftId});

  final List<MailRecipient> to;
  final List<MailRecipient> cc;
  final String subject;
  final String body;

  /// Original message HTML appended under the user's text when sending.
  final String? quotedHtml;
  final String? draftId;

  static String _prefixed(String prefix, String subject) {
    final s = subject.trim();
    if (s.toLowerCase().startsWith(prefix.toLowerCase())) return s;
    return '$prefix $s'.trim();
  }

  static List<MailRecipient> _recipients(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['user_id'] ?? e['id']) != null)
        .map(
          (e) => MailRecipient(
            userId: (e['user_id'] ?? e['id']).toString(),
            display: e['display']?.toString() ?? e['email']?.toString() ?? 'User #${e['user_id']}',
            email: e['email']?.toString(),
          ),
        )
        .toList();
  }

  static String _originalHtml(Map<String, dynamic> m) {
    final html = m['body_html']?.toString();
    if (html != null && html.trim().isNotEmpty) return html;
    return plainTextToHtml(m['body']?.toString() ?? '');
  }

  static String _sender(Map<String, dynamic> m) =>
      m['from_display']?.toString() ?? [m['from_first_name'], m['from_last_name']].where((e) => e != null).join(' ').trim();

  factory MailComposeSeed.from(MailComposeMode mode, Map<String, dynamic>? original) {
    final m = original ?? const <String, dynamic>{};
    final subject = m['subject']?.toString() ?? '';
    switch (mode) {
      case MailComposeMode.compose:
        return const MailComposeSeed();
      case MailComposeMode.reply:
        final fromId = m['from_user_id']?.toString();
        final sender = _sender(m);
        final when = m['sent_at']?.toString() ?? m['created_at']?.toString() ?? '';
        return MailComposeSeed(
          to: fromId == null || fromId.isEmpty
              ? const []
              : [MailRecipient(userId: fromId, display: sender.isEmpty ? 'User #$fromId' : sender, email: m['from_email']?.toString())],
          subject: _prefixed('Re:', subject),
          quotedHtml: '<p>${escapeHtml('เมื่อ $when $sender เขียนว่า:'.trim())}</p><blockquote>${_originalHtml(m)}</blockquote>',
        );
      case MailComposeMode.forward:
        final sender = _sender(m);
        return MailComposeSeed(
          subject: _prefixed('Fwd:', subject),
          quotedHtml:
              '<p>---------- ข้อความที่ส่งต่อ ----------<br>'
              'จาก: ${escapeHtml(sender)}<br>เรื่อง: ${escapeHtml(subject)}</p>${_originalHtml(m)}',
        );
      case MailComposeMode.draft:
        final html = m['body_html']?.toString();
        return MailComposeSeed(
          to: _recipients(m['to']),
          cc: _recipients(m['cc']),
          subject: subject,
          body: m['body']?.toString() ?? (html == null ? '' : stripHtmlPreview(html, maxLen: 1 << 20)),
          draftId: m['id']?.toString(),
        );
    }
  }
}

String escapeHtml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Plain text from the compose box → minimal safe HTML.
String plainTextToHtml(String text) {
  if (text.trim().isEmpty) return '';
  return text.split(RegExp(r'\n{2,}')).map((p) => '<p>${escapeHtml(p).replaceAll('\n', '<br>')}</p>').join();
}

class MailComposeScreen extends StatefulWidget {
  const MailComposeScreen({super.key, this.mode = MailComposeMode.compose, this.original});

  final MailComposeMode mode;
  final Map<String, dynamic>? original;

  @override
  State<MailComposeScreen> createState() => _MailComposeScreenState();
}

class _MailComposeScreenState extends State<MailComposeScreen> {
  late final MailComposeSeed _seed = MailComposeSeed.from(widget.mode, widget.original);
  late final List<MailRecipient> _to = [..._seed.to];
  late final List<MailRecipient> _cc = [..._seed.cc];
  late final TextEditingController _subject = TextEditingController(text: _seed.subject);
  late final TextEditingController _body = TextEditingController(text: _seed.body);
  late bool _showCc = _cc.isNotEmpty;
  bool _busy = false;
  List<Map<String, dynamic>>? _users;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.mode) {
      case MailComposeMode.reply:
        return 'ตอบกลับ';
      case MailComposeMode.forward:
        return 'ส่งต่อ';
      case MailComposeMode.draft:
        return 'แก้ไขฉบับร่าง';
      case MailComposeMode.compose:
        return 'เขียนเมล';
    }
  }

  Future<void> _pick(List<MailRecipient> target) async {
    final api = context.read<AppConfig>().apiClient;
    try {
      _users ??= await api.getMailUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
      return;
    }
    if (!mounted) return;
    final all = _users!.map(MailRecipient.fromUser).where((r) => r.userId.isNotEmpty).toList();
    final picked = await showModalBottomSheet<MailRecipient>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => _RecipientPicker(users: all, exclude: {..._to, ..._cc}),
    );
    if (picked != null && mounted) setState(() => target.add(picked));
  }

  Future<void> _submit({required bool draft}) async {
    if (!draft && _to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('กรุณาเลือกผู้รับ'))));
      return;
    }
    if (!draft && _subject.text.trim().isEmpty && _body.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('กรุณาใส่หัวข้อหรือข้อความ'))));
      return;
    }
    setState(() => _busy = true);
    final api = context.read<AppConfig>().apiClient;
    final html = '${plainTextToHtml(_body.text)}${_seed.quotedHtml ?? ''}';
    final bodyText = _seed.quotedHtml == null ? _body.text : '${_body.text}\n\n${stripHtmlPreview(_seed.quotedHtml, maxLen: 1 << 20)}';
    try {
      final toIds = _to.map((r) => r.userId).toList();
      final ccIds = _cc.map((r) => r.userId).toList();
      if (_seed.draftId != null && _seed.draftId!.isNotEmpty) {
        await api.updateMailDraft(
          _seed.draftId!,
          toUserIds: toIds,
          ccUserIds: ccIds,
          subject: _subject.text.trim(),
          body: bodyText,
          bodyHtml: html,
          isDraft: draft,
        );
      } else {
        await api.sendMail(toUserIds: toIds, ccUserIds: ccIds, subject: _subject.text.trim(), body: bodyText, bodyHtml: html, isDraft: draft);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(draft ? 'บันทึกฉบับร่างแล้ว' : 'ส่งจดหมายแล้ว'))));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Widget _recipientRow(String label, List<MailRecipient> list) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(tr(label), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final r in list)
                  InputChip(
                    deleteIcon: const Icon(NxI.x, size: 16),
                    label: Text(tr(r.display)),
                    onDeleted: _busy ? null : () => setState(() => list.remove(r)),
                  ),
                ActionChip(avatar: const Icon(NxI.userPlus, size: 18), label: Text(tr('เพิ่ม')), onPressed: _busy ? null : () => _pick(list)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Back / swipe asks before throwing away what was typed.
  @override
  Widget build(BuildContext context) => NxUnsavedGuard(
        enabled: true,
        snapshot: () => [_to, _cc, _subject.text, _body.text].join('|'),
        child: _buildForm(context),
      );


  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: NxAppHeader(
        title: _title,
        actions: [
          IconButton(tooltip: tr('บันทึกฉบับร่าง'), onPressed: _busy ? null : () => _submit(draft: true), icon: const Icon(NxI.note)),
          IconButton(
            tooltip: tr('ส่ง'),
            onPressed: _busy ? null : () => _submit(draft: false),
            icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.paperPlaneTilt),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _recipientRow('ถึง', _to),
          if (_showCc)
            _recipientRow('สำเนา', _cc)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => setState(() => _showCc = true), child: Text(tr('+ สำเนา (CC)'))),
            ),
          const Divider(),
          TextField(
            controller: _subject,
            enabled: !_busy,
            decoration: InputDecoration(labelText: tr('หัวข้อ')),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            enabled: !_busy,
            minLines: 8,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(labelText: tr('ข้อความ'), alignLabelWithHint: true),
          ),
          if (_seed.quotedHtml != null) ...[
            const SizedBox(height: 16),
            Text(
              tr(widget.mode == MailComposeMode.forward ? 'ข้อความที่ส่งต่อจะแนบท้ายอัตโนมัติ' : 'ข้อความเดิมจะแนบท้ายอัตโนมัติ'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(tr(stripHtmlPreview(_seed.quotedHtml, maxLen: 400)), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

class _RecipientPicker extends StatefulWidget {
  const _RecipientPicker({required this.users, required this.exclude});

  final List<MailRecipient> users;
  final Set<MailRecipient> exclude;

  @override
  State<_RecipientPicker> createState() => _RecipientPickerState();
}

class _RecipientPickerState extends State<_RecipientPicker> {
  var _needle = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.users.where((u) {
      if (widget.exclude.contains(u)) return false;
      if (_needle.isEmpty) return true;
      return u.display.toLowerCase().contains(_needle) || (u.email ?? '').toLowerCase().contains(_needle);
    }).toList();
    return Padding(
      // Above the keyboard: the search field and results stay visible.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: nxSheetHeight(context, 0.7),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(labelText: tr('ค้นหาผู้รับ'), prefixIcon: Icon(NxI.magnifyingGlass)),
                  onChanged: (v) => setState(() => _needle = v.trim().toLowerCase()),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(child: Text(tr('ไม่พบผู้ใช้')))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final u = filtered[i];
                          return ListTile(
                            leading: const Icon(NxI.user),
                            title: Text(tr(u.display)),
                            subtitle: u.email == null ? null : Text(tr(u.email!)),
                            onTap: () => Navigator.pop(context, u),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
