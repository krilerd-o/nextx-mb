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

  /// A settings group: rounded card with a title.
  Widget _group(String title, IconData icon, List<Widget> children) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: dark ? cs.surfaceContainer : cs.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: dark ? 0.25 : 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  /// One option of a single choice, as a selectable row.
  Widget _choice(String key, IconData icon, String title, String hint, bool on, VoidCallback tap) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(14),
        onTap: tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: on ? cs.primary.withValues(alpha: 0.10) : Colors.transparent,
            border: Border.all(color: on ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6), width: on ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: on ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(title),
                      style: TextStyle(fontWeight: FontWeight.w700, color: on ? cs.primary : null),
                    ),
                    Text(tr(hint), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(on ? NxI.radioOn : NxI.radioOff, size: 20, color: on ? cs.primary : cs.outline),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _filled(String hint, {IconData? icon, String? helper}) => InputDecoration(
    hintText: tr(hint),
    helperText: helper == null ? null : tr(helper),
    prefixIcon: icon == null ? null : Icon(icon, size: 18),
    filled: true,
    isDense: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
  );

  Widget _form() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        TextField(
          key: const ValueKey('room-title'),
          controller: _title,
          style: theme.textTheme.titleMedium,
          decoration: _filled('หัวข้อการประชุม', icon: NxI.pencilSimple),
        ),
        const SizedBox(height: 12),
        _group('ใครเข้าได้', NxI.lock, [
          _choice('room-access-link', NxI.link, 'ทุกคนที่มีลิงก์', 'รวมแขกภายนอก ไม่ต้องมีบัญชี', _access == 'link', () => setState(() => _access = 'link')),
          _choice('room-access-business', NxI.buildings, 'คนในองค์กร', 'ต้องเข้าสู่ระบบ NEXTX', _access == 'business', () => setState(() => _access = 'business')),
          _choice('room-access-invited', NxI.envelope, 'เฉพาะที่เชิญ', 'ระบุอีเมล หรือ @โดเมน', _access == 'invited', () => setState(() => _access = 'invited')),
          if (_access == 'invited')
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: TextField(
                key: const ValueKey('room-allowed'),
                controller: _allowed,
                decoration: _filled('a@x.com, @partner.co.th', icon: NxI.at),
              ),
            ),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('room-password'),
            controller: _password,
            obscureText: true,
            decoration: _filled('รหัสผ่านห้อง (ไม่บังคับ)', icon: NxI.password, helper: 'คนในองค์กรไม่ต้องใส่'),
          ),
          _switch('waiting', 'ห้องรอ', 'ผู้จัดกดรับแขกจากภายนอกเข้าห้องทีละคน', _waiting, (v) => _waiting = v),
          _switch('guest-email', 'แขกต้องใส่อีเมล', null, _guestEmail, (v) => _guestEmail = v),
          Row(
            children: [
              Expanded(child: Text('${tr('ผู้เข้าร่วมสูงสุด')} ${_max.round()} ${tr('คน')}')),
              SizedBox(
                width: 170,
                child: Slider(key: const ValueKey('room-max'), min: 2, max: 100, divisions: 49, value: _max, onChanged: (v) => setState(() => _max = v)),
              ),
            ],
          ),
        ]),
        _group('เวลา', NxI.calendarClock, [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(NxI.calendarBlank),
            title: Text(_scheduled == null ? tr('เริ่มตอนนี้') : '${tr('นัดไว้')} ${minuteWhen(_scheduled)}'),
            trailing: TextButton(onPressed: _pickSchedule, child: Text(tr('เลือกเวลา'))),
          ),
          Text(tr('ลิงก์หมดอายุ'), style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in const [('end', 'เมื่อจบประชุม'), ('1d', '1 วัน'), ('7d', '7 วัน'), ('30d', '30 วัน')])
                ChoiceChip(key: ValueKey('room-exp-${e.$1}'), label: Text(tr(e.$2)), selected: _expires == e.$1, showCheckmark: false, onSelected: (_) => setState(() => _expires = e.$1)),
            ],
          ),
          const SizedBox(height: 8),
        ]),
        _group('ตอนเข้าห้อง', NxI.signIn, [
          _switch('mute', 'ปิดไมค์เมื่อเข้าห้อง', null, _muteOnJoin, (v) => _muteOnJoin = v),
          _switch('cam', 'ปิดกล้องเมื่อเข้าห้อง', null, _camOff, (v) => _camOff = v),
          _switch('chat', 'แชทในห้อง', null, _chat, (v) => _chat = v),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text(tr('ใครแชร์หน้าจอได้'))),
                ChoiceChip(label: Text(tr('ผู้จัด')), selected: _screen == 'host', showCheckmark: false, onSelected: (_) => setState(() => _screen = 'host')),
                const SizedBox(width: 6),
                ChoiceChip(label: Text(tr('ทุกคน')), selected: _screen == 'all', showCheckmark: false, onSelected: (_) => setState(() => _screen = 'all')),
              ],
            ),
          ),
        ]),
        _group('ไอแซค', NxI.sparkle, [
          _switch('transcribe', 'ถอดข้อความสด', 'แยกผู้พูดตามชื่อในห้อง', _transcribe, (v) => _transcribe = v),
          if (_transcribe) ...[
            _switch('captions', 'แสดงคำบรรยายให้ทุกคน', 'ปิดไว้ = เห็นเฉพาะผู้จัด', _captionsAll, (v) => _captionsAll = v),
            Text(tr('ภาษาที่แปลสดได้'), style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            MinuteLangChips(selected: _langs, onChanged: (v) => setState(() => _langs = v)),
            const SizedBox(height: 10),
          ],
          Text(tr('การบันทึก'), style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in const [('none', 'ไม่บันทึก'), ('audio', 'บันทึกเสียง'), ('video', 'บันทึกภาพและเสียง')])
                ChoiceChip(key: ValueKey('room-rec-${e.$1}'), label: Text(tr(e.$2)), selected: _record == e.$1, showCheckmark: false, onSelected: (_) => setState(() => _record = e.$1)),
            ],
          ),
          const SizedBox(height: 10),
          Text(tr('สรุปการประชุม'), style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(label: Text(tr('สรุปทันทีเมื่อจบ')), selected: _summary == 'now', showCheckmark: false, onSelected: (_) => setState(() => _summary = 'now')),
              ChoiceChip(label: Text(tr('สรุปภายหลัง')), selected: _summary == 'later', showCheckmark: false, onSelected: (_) => setState(() => _summary = 'later')),
            ],
          ),
          if (_summary == 'now') ...[
            const SizedBox(height: 10),
            MinuteTemplatePicker(value: _template, onChanged: (v) => setState(() => _template = v)),
            _switch('email-summary', 'ส่งสรุปให้ผู้เข้าร่วมทางอีเมล', null, _emailSummary, (v) => _emailSummary = v),
          ],
        ]),
        Row(
          children: [
            Icon(NxI.shieldCheck, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(tr('ทุกคนจะเห็นประกาศว่าห้องนี้มีการบันทึก / ถอดข้อความก่อนเข้าห้อง'), style: theme.textTheme.bodySmall)),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(tr(_error!), style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('room-create-go'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item['title'] ?? ''}',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(tr('รหัสห้อง'), style: const TextStyle(color: Colors.white70)),
              SelectableText(
                code,
                key: const ValueKey('room-code'),
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 1.5),
              ),
              const SizedBox(height: 6),
              Text(link, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
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
          ],
        ),
        MinuteSectionTitle('เชิญทางอีเมล', icon: NxI.envelope),
        TextField(
          key: const ValueKey('room-invite-emails'),
          controller: _invite,
          decoration: InputDecoration(hintText: 'a@company.com, b@partner.com', border: const OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            key: const ValueKey('room-invite-send'),
            onPressed: () async {
              final list = [
                for (final e in _invite.text.split(RegExp(r'[,;\s]+')))
                  if (e.contains('@')) e.trim(),
              ];
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
