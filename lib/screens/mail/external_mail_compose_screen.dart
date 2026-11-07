import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/api_client.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../crm/entity_detail_parts.dart' show pickAttachments;
import 'mail_compose_screen.dart' show MailComposeMode, escapeHtml, plainTextToHtml;
import '../../core/i18n.dart';

final _emailRe = RegExp(r'^[^@\s,;]+@[^@\s,;]+\.[^@\s,;]+$');

/// Splits "a@x.com, b@y.com; c@z.com" into valid addresses.
List<String> parseEmails(String raw) => [
      for (final p in raw.split(RegExp(r'[,;\s]+')))
        if (_emailRe.hasMatch(p.trim())) p.trim(),
    ];

/// Prefill for reply / forward on a Gmail / Outlook message.
({List<String> to, String subject, String quoted, String? action, String? replyToId, String? threadId}) externalSeed(
  MailComposeMode mode,
  Map<String, dynamic>? m,
) {
  final o = m ?? const <String, dynamic>{};
  final subject = o['subject']?.toString() ?? '';
  String prefixed(String p) => subject.toLowerCase().startsWith(p.toLowerCase()) ? subject : '$p $subject'.trim();
  final from = o['from_email']?.toString() ?? '';
  final who = o['from_display']?.toString() ?? from;
  final when = o['sent_at']?.toString() ?? o['created_at']?.toString() ?? '';
  final html = (o['body_html']?.toString().trim().isNotEmpty ?? false) ? o['body_html'].toString() : plainTextToHtml(o['body']?.toString() ?? o['snippet']?.toString() ?? '');
  switch (mode) {
    case MailComposeMode.reply:
      return (
        to: from.isEmpty ? const <String>[] : [from],
        subject: prefixed('Re:'),
        quoted: '<p>${escapeHtml('เมื่อ $when $who เขียนว่า:')}</p><blockquote>$html</blockquote>',
        action: 'reply',
        replyToId: o['id']?.toString(),
        threadId: o['thread_id']?.toString(),
      );
    case MailComposeMode.forward:
      return (
        to: const <String>[],
        subject: prefixed('Fwd:'),
        quoted: '<p>---------- ข้อความที่ส่งต่อ ----------<br>จาก: ${escapeHtml(who)}<br>เรื่อง: ${escapeHtml(subject)}</p>$html',
        action: 'forward',
        replyToId: o['id']?.toString(),
        threadId: null,
      );
    default:
      return (to: const <String>[], subject: '', quoted: '', action: null, replyToId: null, threadId: null);
  }
}

/// Compose through a connected Gmail / Outlook account.
class ExternalMailComposeScreen extends StatefulWidget {
  const ExternalMailComposeScreen({super.key, required this.account, this.mode = MailComposeMode.compose, this.original});

  final MailAccount account;
  final MailComposeMode mode;
  final Map<String, dynamic>? original;

  @override
  State<ExternalMailComposeScreen> createState() => _ExternalMailComposeScreenState();
}

class _ExternalMailComposeScreenState extends State<ExternalMailComposeScreen> {
  late final _seed = externalSeed(widget.mode, widget.original);
  late final _to = TextEditingController(text: _seed.to.join(', '));
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  late final _subject = TextEditingController(text: _seed.subject);
  final _body = TextEditingController();
  final List<Map<String, dynamic>> _files = [];
  bool _showCc = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_to, _cc, _bcc, _subject, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _attach() async {
    final picked = await pickAttachments(context);
    if (picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final atts = await context.read<AppConfig>().apiClient.uploadCommentAttachments(picked);
      setState(() => _files.addAll(atts));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final to = parseEmails(_to.text);
    if (to.isEmpty && widget.mode != MailComposeMode.forward) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('กรุณาใส่อีเมลผู้รับ'))));
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppConfig>().apiClient.sendExternalMail(
            account: widget.account,
            to: to,
            cc: parseEmails(_cc.text),
            bcc: parseEmails(_bcc.text),
            subject: _subject.text.trim(),
            bodyHtml: '${plainTextToHtml(_body.text)}${_seed.quoted}',
            action: _seed.action,
            replyToId: _seed.replyToId,
            threadId: _seed.threadId,
            attachments: [
              for (final f in _files)
                {if (f['file_id'] != null) 'file_id': f['file_id'], 'name': f['name'], 'url': f['url'], 'mime': f['mime']},
            ],
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ส่งเมลแล้ว'))));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.mode) {
      MailComposeMode.reply => 'ตอบกลับ',
      MailComposeMode.forward => 'ส่งต่อ',
      _ => 'เขียนเมล',
    };
    final theme = Theme.of(context);
    InputDecoration deco(String label) => InputDecoration(labelText: trn(label), border: InputBorder.none, filled: false);
    return Scaffold(
      appBar: NxAppHeader(
        title: title,
        subtitle: 'จาก ${widget.account.email}',
        actions: [
          IconButton(tooltip: tr('แนบไฟล์'), icon: const Icon(NxI.paperclip), onPressed: _busy ? null : _attach),
          IconButton(
            tooltip: tr('ส่ง'),
            icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.paperPlaneTilt),
            onPressed: _busy ? null : _send,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Row(
            children: [
              Expanded(child: TextField(controller: _to, keyboardType: TextInputType.emailAddress, decoration: deco('ถึง (คั่นด้วย ,)'))),
              TextButton(onPressed: () => setState(() => _showCc = !_showCc), child: Text(tr('Cc/Bcc'))),
            ],
          ),
          if (_showCc) ...[
            const Divider(height: 1),
            TextField(controller: _cc, keyboardType: TextInputType.emailAddress, decoration: deco('สำเนา (Cc)')),
            const Divider(height: 1),
            TextField(controller: _bcc, keyboardType: TextInputType.emailAddress, decoration: deco('สำเนาลับ (Bcc)')),
          ],
          const Divider(height: 1),
          TextField(controller: _subject, decoration: deco('หัวข้อ')),
          const Divider(height: 1),
          if (_files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in _files)
                    InputChip(
        deleteIcon: const Icon(NxI.x, size: 16),
                      avatar: const Icon(NxI.paperclip, size: 16),
                      label: Text(tr(f['name']?.toString() ?? 'file')),
                      onDeleted: () => setState(() => _files.remove(f)),
                    ),
                ],
              ),
            ),
          TextField(
            controller: _body,
            minLines: 8,
            maxLines: null,
            decoration: InputDecoration(hintText: tr('เขียนข้อความ'), border: InputBorder.none, filled: false),
          ),
          if (_seed.quoted.isNotEmpty)
            Text(
              tr(widget.mode == MailComposeMode.reply ? 'ข้อความเดิมจะแนบท้ายให้อัตโนมัติ' : 'ข้อความที่ส่งต่อจะแนบท้ายให้อัตโนมัติ'),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
