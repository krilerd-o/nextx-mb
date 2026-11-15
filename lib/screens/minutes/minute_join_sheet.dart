import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../services/minutes/minute_room_session.dart';
import '../../services/realtime_service.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'minute_room_screen.dart';
import 'minutes_widgets.dart';

/// "abc-defg-hij" from a code or any link that contains one.
String? roomCodeFrom(String input) => RegExp(r'([a-z]{3}-[a-z]{4}-[a-z]{3})').firstMatch(input.trim().toLowerCase())?.group(1);

/// "เข้าร่วมด้วยรหัส": code / link → lobby → join.
Future<void> showMinuteJoinSheet(BuildContext context, {String? code}) async {
  final c = code ?? await showAppBottomSheet<String>(context: context, title: tr('เข้าร่วมประชุม'), child: const _CodePanel());
  if (c == null || !context.mounted) return;
  await openMinuteLobby(context, c);
}

class _CodePanel extends StatefulWidget {
  const _CodePanel();
  @override
  State<_CodePanel> createState() => _CodePanelState();
}

class _CodePanelState extends State<_CodePanel> {
  final _c = TextEditingController();
  String? _err;
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const ValueKey('minute-join-code'),
        controller: _c,
        autofocus: true,
        decoration: InputDecoration(labelText: tr('รหัสห้อง หรือ ลิงก์'), hintText: 'abc-defg-hij', errorText: _err, border: const OutlineInputBorder()),
        onSubmitted: (_) => _go(),
      ),
      const SizedBox(height: 12),
      FilledButton(key: const ValueKey('minute-join-next'), onPressed: _go, child: Text(tr('ต่อไป'))),
    ],
  );

  void _go() {
    final code = roomCodeFrom(_c.text);
    if (code == null) return setState(() => _err = tr('รหัสไม่ถูกต้อง (เช่น abc-defg-hij)'));
    Navigator.of(context).pop(code);
  }
}

/// Lobby: who hosts, when, what the room records (consent), password if needed → join (or wait).
Future<void> openMinuteLobby(BuildContext context, String code) async {
  final api = context.read<AppConfig>().apiClient;
  Map<String, dynamic> lobby;
  try {
    lobby = await api.getMinuteRoomLobby(code);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiEnvelopeException ? e.message : tr('ไม่พบห้องประชุม'))));
    return;
  }
  if (!context.mounted) return;
  await showAppBottomSheet<void>(context: context, title: '${lobby['title'] ?? tr('ห้องประชุม')}', child: _LobbyPanel(code: code, lobby: lobby));
}

class _LobbyPanel extends StatefulWidget {
  const _LobbyPanel({required this.code, required this.lobby});
  final String code;
  final Map<String, dynamic> lobby;
  @override
  State<_LobbyPanel> createState() => _LobbyPanelState();
}

class _LobbyPanelState extends State<_LobbyPanel> {
  final _password = TextEditingController();
  late bool _mic = widget.lobby['mute_on_join'] != true;
  late bool _cam = widget.lobby['camera_off_on_join'] != true;
  bool _busy = false;
  String? _err;
  String? _waitingTicket;
  Timer? _poll;
  StreamSubscription<RealtimeEvent>? _sub;

  @override
  void dispose() {
    _poll?.cancel();
    _sub?.cancel();
    _password.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    final api = context.read<AppConfig>().apiClient;
    try {
      final r = await api.joinMinuteRoomByCode(widget.code, password: _password.text.isEmpty ? null : _password.text, ticket: _waitingTicket);
      if (!mounted) return;
      if (r['status'] == 'waiting') {
        _waitingTicket = '${r['ticket']}';
        setState(() => _busy = false);
        _waitForHost();
        return;
      }
      _poll?.cancel();
      final nav = Navigator.of(context);
      nav.pop();
      await openMinuteRoomScreen(nav.context, join: r, code: widget.code, title: '${widget.lobby['title'] ?? ''}', micOn: _mic, camOn: _cam);
    } catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _err = e is ApiEnvelopeException ? e.message : tr('เข้าห้องไม่สำเร็จ');
      });
    }
  }

  void _waitForHost() {
    final rt = RealtimeService.instance;
    unawaited(rt.emitAck('minute:room_wait', {'ticket': _waitingTicket}));
    _sub ??= rt.events.listen((e) {
      if (e.type != 'minute:room_admit') return;
      if (e.data['allowed'] == true) {
        _join();
      } else if (mounted) {
        setState(() {
          _waitingTicket = null;
          _err = tr('ผู้จัดไม่อนุญาตให้เข้าห้อง');
        });
      }
    });
    // Polling too, in case the socket event is missed.
    _poll ??= Timer.periodic(const Duration(seconds: 5), (_) => _waitingTicket != null && !_busy ? _join() : null);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lobby;
    final theme = Theme.of(context);
    final ai = Map<String, dynamic>.from((l['ai'] as Map?) ?? const {});
    final consent = ai['consent_notice'] == true ? roomConsentText(transcribe: ai['transcribe'] == true, record: '${ai['record'] ?? 'none'}') : '';
    final status = '${l['status'] ?? ''}';
    final closed = status == 'ended' || status == 'expired';
    if (_waitingTicket != null) {
      return Column(
        key: const ValueKey('minute-lobby-waiting'),
        children: [
          const SizedBox(height: 8),
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(tr('รอผู้จัดรับเข้าห้อง…'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(tr('ผู้จัดจะเห็นชื่อของคุณในห้องรอ'), style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('ยกเลิก'))),
        ],
      );
    }
    return Column(
      key: const ValueKey('minute-lobby'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(NxI.userCircle),
          title: Text('${tr('ผู้จัด')}: ${l['host'] ?? '-'}'),
          subtitle: Text([widget.code, if (l['scheduled_at'] != null) '${tr('นัดไว้')} ${minuteWhen(DateTime.tryParse('${l['scheduled_at']}')?.toLocal())}'].join(' · ')),
        ),
        if (consent.isNotEmpty)
          Container(
            key: const ValueKey('minute-lobby-consent'),
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: kMinuteRecord.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [const Icon(NxI.microphone, color: kMinuteRecord, size: 18), const SizedBox(width: 8), Expanded(child: Text(tr(consent)))]),
          ),
        if (l['needs_password'] == true)
          TextField(key: const ValueKey('minute-lobby-password'), controller: _password, obscureText: true, decoration: InputDecoration(labelText: tr('รหัสผ่านห้อง'), helperText: tr('คนในองค์กรไม่ต้องใส่'), border: const OutlineInputBorder(), isDense: true)),
        Row(children: [
          Expanded(child: SwitchListTile(contentPadding: EdgeInsets.zero, value: _mic, onChanged: (v) => setState(() => _mic = v), title: Text(tr('ไมค์')), secondary: Icon(_mic ? NxI.microphone : NxI.microphoneSlash))),
          Expanded(child: SwitchListTile(contentPadding: EdgeInsets.zero, value: _cam, onChanged: (v) => setState(() => _cam = v), title: Text(tr('กล้อง')), secondary: Icon(_cam ? NxI.videoCamera : NxI.videoCameraSlash))),
        ]),
        if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_err!, style: TextStyle(color: theme.colorScheme.error))),
        FilledButton.icon(
          key: const ValueKey('minute-lobby-join'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _busy || closed || l['rooms_available'] == false ? null : _join,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.signIn),
          label: Text(tr(closed ? (status == 'ended' ? 'การประชุมจบแล้ว' : 'ลิงก์หมดอายุแล้ว') : 'เข้าร่วม')),
        ),
      ],
    );
  }
}

/// The host (or a member of the business) entering a room they can see in the app.
Future<void> joinMinuteRoomAsMember(BuildContext context, {required String meetingId, required String code, required String title}) => openMinuteLobby(context, code);
