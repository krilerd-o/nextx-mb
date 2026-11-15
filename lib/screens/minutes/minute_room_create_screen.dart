import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';
import 'minute_join_sheet.dart';
import 'minute_share_sheet.dart' show shareMinuteText;
import 'minutes_widgets.dart';

/// "สร้างห้องประชุม": everything a host may want to set before sharing the link.
class MinuteRoomCreateScreen extends StatefulWidget {
  const MinuteRoomCreateScreen({super.key});
  @override
  State<MinuteRoomCreateScreen> createState() => _MinuteRoomCreateScreenState();
}

class _MinuteRoomCreateScreenState extends State<MinuteRoomCreateScreen> {
  final _title = TextEditingController();
  final _password = TextEditingController();
  final _allowed = TextEditingController();
  final _invite = TextEditingController();
  String _access = 'link';
  bool _waiting = true;
  bool _muteOnJoin = true;
  bool _camOff = false;
  bool _guestEmail = false;
  String _screen = 'all';
  bool _chat = true;
  double _max = 50;
  String _expires = 'end';
  DateTime? _scheduled;
  bool _transcribe = true;
  bool _captionsAll = true;
  List<String> _langs = const ['en'];
  String _record = 'audio';
  String _summary = 'now';
  String _template = 'general';
  bool _emailSummary = false;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _created;

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void dispose() {
    for (final c in [_title, _password, _allowed, _invite]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _settings => {
    'access': _access,
    if (_access == 'invited') 'allowed_emails': _allowed.text,
    if (_password.text.isNotEmpty) 'password': _password.text,
    'waiting_room': _waiting,
    'max_participants': _max.round(),
    'expires': _expires,
    if (_scheduled != null) 'scheduled_at': _scheduled!.toUtc().toIso8601String(),
    'mute_on_join': _muteOnJoin,
    'camera_off_on_join': _camOff,
    'guest_email_required': _guestEmail,
    'screen_share': _screen,
    'chat': _chat,
    'ai': {
      'transcribe': _transcribe,
      'captions_for_all': _captionsAll,
      'translate_langs': _langs,
      'record': _record,
      'summary': _summary,
      'template': _template,
      'email_summary': _emailSummary,
      'consent_notice': true,
    },
  };

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.createMinuteRoom({'title': _title.text.trim(), 'settings': _settings});
      if (!mounted) return;
      setState(() => _created = r);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiEnvelopeException ? e.message : tr('สร้างห้องไม่สำเร็จ'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), initialDate: _scheduled ?? now);
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_scheduled ?? now.add(const Duration(minutes: 30))));
    if (t == null) return;
    setState(() => _scheduled = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    return Scaffold(
      key: const ValueKey('minute-room-create'),
      appBar: AppBar(title: Text(tr(created == null ? 'สร้างห้องประชุม' : 'ห้องประชุมพร้อมแล้ว'))),
      body: created == null ? _form() : _share(created),
    );
  }

  Widget _switch(String key, String title, String? sub, bool v, ValueChanged<bool> on) => SwitchListTile(
    key: ValueKey('room-set-$key'),
    contentPadding: EdgeInsets.zero,
    title: Text(tr(title)),
    subtitle: sub == null ? null : Text(tr(sub)),
    value: v,
    onChanged: (x) => setState(() => on(x)),
  );

  Widget _form() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        TextField(key: const ValueKey('room-title'), controller: _title, decoration: InputDecoration(labelText: tr('หัวข้อการประชุม'), border: const OutlineInputBorder())),
        MinuteSectionTitle('ใครเข้าได้', icon: NxI.lock),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'link', label: Text(tr('ทุกคนที่มีลิงก์'))),
            ButtonSegment(value: 'business', label: Text(tr('คนในองค์กร'))),
            ButtonSegment(value: 'invited', label: Text(tr('เฉพาะที่เชิญ'))),
          ],
          selected: {_access},
          onSelectionChanged: (s) => setState(() => _access = s.first),
        ),
        if (_access == 'invited')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              key: const ValueKey('room-allowed'),
              controller: _allowed,
              decoration: InputDecoration(labelText: tr('อีเมล หรือ @โดเมน ที่เข้าได้'), hintText: 'a@x.com, @partner.co.th', border: const OutlineInputBorder(), isDense: true),
            ),
          ),
        const SizedBox(height: 8),
        TextField(key: const ValueKey('room-password'), controller: _password, obscureText: true, decoration: InputDecoration(labelText: tr('รหัสผ่านห้อง (ไม่บังคับ)'), helperText: tr('คนในองค์กรไม่ต้องใส่'), border: const OutlineInputBorder(), isDense: true)),
        _switch('waiting', 'ห้องรอ', 'ผู้จัดกดรับแขกจากภายนอกเข้าห้องทีละคน', _waiting, (v) => _waiting = v),
        _switch('guest-email', 'แขกต้องใส่อีเมล', null, _guestEmail, (v) => _guestEmail = v),
        Row(children: [
          Expanded(child: Text('${tr('ผู้เข้าร่วมสูงสุด')} ${_max.round()} ${tr('คน')}')),
          SizedBox(width: 180, child: Slider(key: const ValueKey('room-max'), min: 2, max: 100, divisions: 49, value: _max, onChanged: (v) => setState(() => _max = v))),
        ]),
        MinuteSectionTitle('เวลา', icon: NxI.calendarClock),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(NxI.calendarBlank),
          title: Text(_scheduled == null ? tr('เริ่มตอนนี้') : '${tr('นัดไว้')} ${minuteWhen(_scheduled)}'),
          trailing: TextButton(onPressed: _pickSchedule, child: Text(tr('เลือกเวลา'))),
        ),
        Wrap(spacing: 6, children: [
          for (final e in const [('end', 'ลิงก์หมดอายุเมื่อจบประชุม'), ('1d', '1 วัน'), ('7d', '7 วัน'), ('30d', '30 วัน')])
            ChoiceChip(key: ValueKey('room-exp-${e.$1}'), label: Text(tr(e.$2)), selected: _expires == e.$1, onSelected: (_) => setState(() => _expires = e.$1)),
        ]),
        MinuteSectionTitle('ตอนเข้าห้อง', icon: NxI.signIn),
        _switch('mute', 'ปิดไมค์เมื่อเข้าห้อง', null, _muteOnJoin, (v) => _muteOnJoin = v),
        _switch('cam', 'ปิดกล้องเมื่อเข้าห้อง', null, _camOff, (v) => _camOff = v),
        _switch('chat', 'แชทในห้อง', null, _chat, (v) => _chat = v),
        Row(children: [
          Expanded(child: Text(tr('แชร์หน้าจอได้'))),
          SegmentedButton<String>(
            segments: [ButtonSegment(value: 'host', label: Text(tr('ผู้จัด'))), ButtonSegment(value: 'all', label: Text(tr('ทุกคน')))],
            selected: {_screen},
            onSelectionChanged: (s) => setState(() => _screen = s.first),
          ),
        ]),
        MinuteSectionTitle('ไอแซค', icon: NxI.sparkle),
        _switch('transcribe', 'ถอดข้อความสด', 'แยกผู้พูดตามชื่อในห้อง', _transcribe, (v) => _transcribe = v),
        if (_transcribe) ...[
          _switch('captions', 'แสดงคำบรรยายให้ทุกคน', 'ปิดไว้ = เห็นเฉพาะผู้จัด', _captionsAll, (v) => _captionsAll = v),
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(tr('ภาษาที่แปลสดได้'), style: theme.textTheme.bodySmall)),
          MinuteLangChips(selected: _langs, onChanged: (v) => setState(() => _langs = v)),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          for (final e in const [('none', 'ไม่บันทึก'), ('audio', 'บันทึกเสียง'), ('video', 'บันทึกภาพและเสียง')])
            ChoiceChip(key: ValueKey('room-rec-${e.$1}'), label: Text(tr(e.$2)), selected: _record == e.$1, onSelected: (_) => setState(() => _record = e.$1)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          ChoiceChip(label: Text(tr('สรุปทันทีเมื่อจบ')), selected: _summary == 'now', onSelected: (_) => setState(() => _summary = 'now')),
          ChoiceChip(label: Text(tr('สรุปภายหลัง')), selected: _summary == 'later', onSelected: (_) => setState(() => _summary = 'later')),
        ]),
        if (_summary == 'now') ...[
          const SizedBox(height: 8),
          MinuteTemplatePicker(value: _template, onChanged: (v) => setState(() => _template = v)),
          _switch('email-summary', 'ส่งสรุปให้ผู้เข้าร่วมทางอีเมล', null, _emailSummary, (v) => _emailSummary = v),
        ],
        const SizedBox(height: 6),
        Text(tr('ทุกคนจะเห็นประกาศว่าห้องนี้มีการบันทึก / ถอดข้อความก่อนเข้าห้อง'), style: theme.textTheme.bodySmall),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(tr(_error!), style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('room-create-go'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _busy ? null : _create,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.link),
          label: Text(tr('สร้างห้องและลิงก์')),
        ),
      ],
    );
  }

  Widget _share(Map<String, dynamic> r) {
    final room = Map<String, dynamic>.from(r['room'] as Map);
    final item = Map<String, dynamic>.from(r['item'] as Map);
    final link = '${room['link'] ?? ''}';
    final code = '${room['code'] ?? ''}';
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey('room-created'),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: kMinuteGradient, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item['title'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(tr('รหัสห้อง'), style: const TextStyle(color: Colors.white70)),
            SelectableText(code, key: const ValueKey('room-code'), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            const SizedBox(height: 6),
            Text(link, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('room-copy'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('คัดลอกลิงก์แล้ว'))));
              },
              icon: const Icon(NxI.copySimple),
              label: Text(tr('คัดลอกลิงก์')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('room-share'),
              onPressed: () => shareMinuteText('${tr('เชิญเข้าร่วมประชุม')} "${item['title']}"\n$link\n${tr('รหัสห้อง')}: $code'),
              icon: const Icon(NxI.shareNetwork),
              label: Text(tr('แชร์')),
            ),
          ),
        ]),
        MinuteSectionTitle('เชิญทางอีเมล', icon: NxI.envelope),
        TextField(key: const ValueKey('room-invite-emails'), controller: _invite, decoration: InputDecoration(hintText: 'a@company.com, b@partner.com', border: const OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            key: const ValueKey('room-invite-send'),
            onPressed: () async {
              final list = [for (final e in _invite.text.split(RegExp(r'[,;\s]+'))) if (e.contains('@')) e.trim()];
              if (list.isEmpty) return;
              try {
                await _api.inviteToMinuteRoom('${item['id']}', list);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('ส่งคำเชิญแล้ว')} ${list.length} ${tr('คน')}')));
                _invite.clear();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiEnvelopeException ? e.message : tr('ส่งคำเชิญไม่สำเร็จ'))));
              }
            },
            icon: const Icon(NxI.paperPlaneTilt, size: 16),
            label: Text(tr('ส่งคำเชิญ + ปฏิทิน')),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const ValueKey('room-start'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: () => joinMinuteRoomAsMember(context, meetingId: '${item['id']}', code: code, title: '${item['title'] ?? ''}'),
          icon: const Icon(NxI.videoCamera),
          label: Text(tr('เข้าห้องประชุม')),
        ),
        const SizedBox(height: 6),
        Text(tr('ลิงก์นี้เปิดได้ทั้งในแอปและเว็บเบราว์เซอร์ แขกจากภายนอกไม่ต้องมีบัญชี'), style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }
}
