import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/chat_format.dart';
import '../../../core/i18n.dart';
import '../../../services/location_service.dart';
import '../../../widgets/nx_avatar.dart';
import '../../../widgets/nx_emoji_picker.dart';
import '../../../widgets/nx_icons.dart';
import '../../../widgets/nx_overlay_panel.dart';
import 'chat_attachments.dart' show ChatTicker;
import 'chat_message_bubble.dart';

typedef ChatPickedFile = ({Uint8List bytes, String name});

/// Composer: + (camera / photos & videos / files / location), emoji, @mention, formatting,
/// voice message, per-room draft, reply / edit bars.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.draftKey,
    required this.members,
    required this.onSend,
    required this.onFiles,
    required this.onVoice,
    this.replyTo,
    this.onCancelReply,
    this.editing,
    this.onCancelEdit,
    this.sending = false,
    this.recorderFactory,
  });

  final TextEditingController controller;
  final String draftKey;
  final List<Map<String, dynamic>> members;
  final Future<void> Function(String text, Map<String, String> mentions) onSend;
  final Future<void> Function(List<ChatPickedFile> files) onFiles;
  final Future<void> Function(ChatPickedFile file, Duration duration) onVoice;
  final Map<String, dynamic>? replyTo;
  final VoidCallback? onCancelReply;
  final Map<String, dynamic>? editing;
  final VoidCallback? onCancelEdit;
  final bool sending;

  /// Tests replace the microphone.
  final AudioRecorder Function()? recorderFactory;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _focus = FocusNode();
  final Map<String, String> _mentions = {}; // display name → user id
  Timer? _draftSave;
  var _showFormat = false;
  String? _mentionQuery;

  // voice
  AudioRecorder? _rec;
  ChatTicker? _ticker;
  var _recording = false;
  var _recElapsed = Duration.zero;
  double _level = 0;
  StreamSubscription<Amplitude>? _ampSub;

  TextEditingController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChanged);
    _loadDraft();
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _draftSave?.cancel();
    _saveDraftNow();
    _ampSub?.cancel();
    _rec?.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      final d = p.getString(widget.draftKey);
      if (d != null && d.isNotEmpty && _c.text.isEmpty && mounted) {
        _c.text = d;
        _c.selection = TextSelection.collapsed(offset: d.length);
      }
    } catch (_) {}
  }

  void _saveDraftNow() {
    if (widget.editing != null) return;
    final text = _c.text;
    SharedPreferences.getInstance().then((p) => text.trim().isEmpty ? p.remove(widget.draftKey) : p.setString(widget.draftKey, text)).catchError((_) => false);
  }

  void _onChanged() {
    _draftSave?.cancel();
    _draftSave = Timer(const Duration(milliseconds: 600), _saveDraftNow);
    // @mention: the word being typed starts with @
    final sel = _c.selection;
    String? q;
    if (sel.isValid && sel.isCollapsed) {
      final before = _c.text.substring(0, sel.baseOffset.clamp(0, _c.text.length));
      final m = RegExp(r'(^|\s)@([^\s@]{0,30})$').firstMatch(before);
      if (m != null) q = m[2];
    }
    if (q != _mentionQuery) setState(() => _mentionQuery = q);
    setState(() {});
  }

  void _replace(int start, int end, String text) {
    _c.value = TextEditingValue(
      text: _c.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  void _insert(String text) {
    final sel = _c.selection;
    final start = sel.isValid ? sel.start : _c.text.length;
    final end = sel.isValid ? sel.end : _c.text.length;
    _replace(start, end, text);
  }

  void _wrap(String open, String close) {
    final sel = _c.selection;
    if (!sel.isValid) return _insert('$open$close');
    final picked = sel.textInside(_c.text);
    _c.value = TextEditingValue(
      text: _c.text.replaceRange(sel.start, sel.end, '$open$picked$close'),
      selection: picked.isEmpty
          ? TextSelection.collapsed(offset: sel.start + open.length)
          : TextSelection(baseOffset: sel.start + open.length, extentOffset: sel.start + open.length + picked.length),
    );
    _focus.requestFocus();
  }

  void _linePrefix(String prefix) {
    final sel = _c.selection;
    final at = sel.isValid ? sel.start : _c.text.length;
    final lineStart = _c.text.lastIndexOf('\n', at - 1) + 1;
    _replace(lineStart, lineStart, prefix);
    _focus.requestFocus();
  }

  void _pickMention(Map<String, dynamic> u) {
    final name = chatSenderName(u);
    final id = '${u['user_id'] ?? u['id']}';
    final sel = _c.selection;
    final before = _c.text.substring(0, sel.baseOffset);
    final at = before.lastIndexOf('@');
    final after = _c.text.substring(sel.baseOffset);
    final text = '${before.substring(0, at)}@$name $after';
    _mentions[name] = id;
    _c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at + name.length + 2));
    setState(() => _mentionQuery = null);
  }

  Future<void> _send() async {
    final text = _c.text.trim();
    if (text.isEmpty || widget.sending) return;
    final mentions = {for (final e in _mentions.entries) if (text.contains('@${e.key}')) e.key: e.value};
    await widget.onSend(text, mentions);
    _mentions.clear();
    final p = await SharedPreferences.getInstance();
    await p.remove(widget.draftKey);
  }

  Future<void> _plus() async {
    _focus.unfocus();
    final choice = await showNxBlurPanel<String>(
      context: context,
      builder: (ctx) {
        Widget tile(String key, IconData icon, String label, Color color) => InkWell(
              key: ValueKey('chat-attach-$key'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.pop(ctx, key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(radius: 26, backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color)),
                  const SizedBox(height: 6),
                  Text(tr(label), style: Theme.of(ctx).textTheme.labelMedium),
                ]),
              ),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              tile('camera', NxI.camera, 'ถ่ายรูป', const Color(0xFF0EA5E9)),
              tile('video', NxI.videoCamera, 'ถ่ายวิดีโอ', const Color(0xFFEF4444)),
              tile('gallery', NxI.images, 'รูป/วิดีโอ', const Color(0xFF8B5CF6)),
              tile('file', NxI.file, 'ไฟล์', const Color(0xFFF59E0B)),
              tile('location', NxI.mapPin, 'ตำแหน่ง', const Color(0xFF10B981)),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    try {
      final picker = ImagePicker();
      switch (choice) {
        case 'camera':
          final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2560);
          if (f != null) await widget.onFiles([(bytes: await f.readAsBytes(), name: f.name)]);
        case 'video':
          final f = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 5));
          if (f != null) await widget.onFiles([(bytes: await f.readAsBytes(), name: f.name)]);
        case 'gallery':
          final list = await picker.pickMultipleMedia(imageQuality: 85, maxWidth: 2560, limit: 10);
          if (list.isNotEmpty) await widget.onFiles([for (final f in list) (bytes: await f.readAsBytes(), name: f.name)]);
        case 'file':
          final r = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
          final files = [for (final f in r?.files ?? const <PlatformFile>[]) if (f.bytes != null) (bytes: f.bytes!, name: f.name)];
          if (files.isNotEmpty) await widget.onFiles(files);
        case 'location':
          final fix = await LocationService().currentFix();
          final lat = fix.latitude.toStringAsFixed(6), lng = fix.longitude.toStringAsFixed(6);
          await widget.onSend('📍 ${tr('ตำแหน่งของฉัน')}\nhttps://maps.google.com/?q=$lat,$lng', const {});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(e is StateError ? e.message : 'ทำรายการไม่สำเร็จ'))));
    }
  }

  Future<void> _emoji() async {
    final e = await showNxEmojiPicker(context);
    if (e != null) {
      _insert(e);
      _focus.requestFocus();
    }
  }

  // ---- voice --------------------------------------------------------------

  Future<void> _startVoice() async {
    final rec = (widget.recorderFactory ?? AudioRecorder.new)();
    try {
      if (!await rec.hasPermission()) {
        await rec.dispose();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ไม่ได้รับสิทธิ์ไมโครโฟน'))));
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: path);
      HapticFeedback.mediumImpact();
      _rec = rec;
      _ampSub = rec.onAmplitudeChanged(const Duration(milliseconds: 150)).listen((a) {
        if (mounted) setState(() => _level = ((a.current + 50) / 50).clamp(0.0, 1.0));
      });
      _ticker = ChatTicker((d) {
        if (mounted) setState(() => _recElapsed = d);
        if (d >= const Duration(minutes: 5)) _stopVoice(send: true);
      })
        ..start();
      setState(() => _recording = true);
    } catch (e) {
      await rec.dispose();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('เริ่มอัดเสียงไม่ได้'))));
    }
  }

  Future<void> _stopVoice({required bool send}) async {
    final rec = _rec;
    if (rec == null) return;
    _rec = null;
    final dur = _ticker?.stop() ?? Duration.zero;
    await _ampSub?.cancel();
    _ampSub = null;
    String? path;
    try {
      path = send ? await rec.stop() : null;
      if (!send) await rec.cancel();
    } catch (_) {}
    await rec.dispose();
    if (mounted) setState(() => _recording = false);
    if (!send || path == null || dur < const Duration(milliseconds: 700)) return;
    final bytes = await File(path).readAsBytes();
    final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(RegExp(r'[-:T]'), '');
    await widget.onVoice((bytes: bytes, name: 'voice-$stamp.m4a'), dur);
    try {
      await File(path).delete();
    } catch (_) {}
  }

  // ---- UI -----------------------------------------------------------------

  Widget _bar({required IconData icon, required String title, required String body, required VoidCallback onClose}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      child: Row(children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(tr(title), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
            Text(body, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]),
        ),
        IconButton(icon: const Icon(NxI.x, size: 18), onPressed: onClose),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasText = _c.text.trim().isNotEmpty;
    final reply = widget.replyTo;
    final editing = widget.editing;
    final q = _mentionQuery?.toLowerCase();
    final mentionList = q == null
        ? const <Map<String, dynamic>>[]
        : widget.members.where((u) => chatSenderName(u).toLowerCase().contains(q)).take(6).toList();

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (mentionList.isNotEmpty)
        Container(
          key: const ValueKey('chat-mention-list'),
          constraints: const BoxConstraints(maxHeight: 220),
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: Material(
            color: cs.surfaceContainerHigh,
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 4), children: [
            for (final u in mentionList)
              ListTile(
                dense: true,
                key: ValueKey('chat-mention-${u['user_id'] ?? u['id']}'),
                leading: NxAvatar(label: chatSenderName(u), size: 28),
                title: Text(chatSenderName(u)),
                onTap: () => _pickMention(u),
              ),
          ]),
          ),
        ),
      if (editing != null)
        _bar(icon: NxI.pencilSimple, title: 'กำลังแก้ไขข้อความ', body: chatPlainText(editing['body']?.toString()), onClose: () => widget.onCancelEdit?.call()),
      if (reply != null && editing == null)
        _bar(
          icon: NxI.reply,
          title: 'ตอบกลับ ${chatSenderName(reply)}',
          body: chatPlainText(reply['body']?.toString()).isNotEmpty
              ? chatPlainText(reply['body']?.toString())
              : chatKindLabel(chatAttachmentKind(chatAttachmentsOf(reply).firstOrNull?['mime_type']?.toString())),
          onClose: () => widget.onCancelReply?.call(),
        ),
      if (_showFormat && !_recording)
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            IconButton(tooltip: tr('ตัวหนา'), icon: const Icon(NxI.textB, size: 20), onPressed: () => _wrap('**', '**')),
            IconButton(tooltip: tr('ตัวเอียง'), icon: const Icon(NxI.textItalic, size: 20), onPressed: () => _wrap('_', '_')),
            IconButton(tooltip: tr('โค้ด'), icon: const Icon(NxI.code, size: 20), onPressed: () => _wrap('`', '`')),
            IconButton(tooltip: tr('รายการ'), icon: const Icon(NxI.listBullets, size: 20), onPressed: () => _linePrefix('- ')),
            IconButton(tooltip: tr('อ้างอิง'), icon: const Icon(NxI.quote, size: 20), onPressed: () => _linePrefix('> ')),
            IconButton(tooltip: tr('กล่าวถึง'), icon: const Icon(NxI.at, size: 20), onPressed: () {
              _insert('@');
              _focus.requestFocus();
            }),
          ]),
        ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 8, 8),
          child: _recording
              ? Row(key: const ValueKey('chat-recording'), children: [
                  IconButton(tooltip: tr('ยกเลิก'), icon: Icon(NxI.trash, color: cs.error), onPressed: () => _stopVoice(send: false)),
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(
                    '${_recElapsed.inMinutes}:${(_recElapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(children: [
                      for (var i = 0; i < 18; i++)
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            height: 6 + 22 * _level * (0.5 + 0.5 * ((i * 7) % 5) / 4),
                            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const ValueKey('chat-voice-send'),
                    tooltip: tr('ส่งข้อความเสียง'),
                    onPressed: () => _stopVoice(send: true),
                    icon: const Icon(NxI.paperPlaneTilt),
                  ),
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  IconButton(
                    key: const ValueKey('chat-plus'),
                    tooltip: tr('แนบ'),
                    onPressed: widget.sending || editing != null ? null : _plus,
                    icon: Icon(NxI.plus, color: cs.primary),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('chat-input'),
                      controller: _c,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: tr('พิมพ์ข้อความ…'),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        isDense: true,
                        contentPadding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                        suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            key: const ValueKey('chat-format'),
                            tooltip: tr('จัดรูปแบบ'),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(NxI.textT, size: 20, color: _showFormat ? cs.primary : cs.onSurfaceVariant),
                            onPressed: () => setState(() => _showFormat = !_showFormat),
                          ),
                          IconButton(
                            key: const ValueKey('chat-emoji'),
                            tooltip: tr('อิโมจิ'),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(NxI.smiley, size: 20, color: cs.onSurfaceVariant),
                            onPressed: _emoji,
                          ),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: hasText || editing != null
                        ? IconButton.filled(
                            key: const ValueKey('chat-send'),
                            tooltip: tr('ส่ง'),
                            onPressed: widget.sending || !hasText ? null : _send,
                            icon: widget.sending
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Icon(editing != null ? NxI.check : NxI.paperPlaneTilt),
                          )
                        : IconButton.filledTonal(
                            key: const ValueKey('chat-mic'),
                            tooltip: tr('อัดข้อความเสียง'),
                            onPressed: widget.sending ? null : _startVoice,
                            icon: const Icon(NxI.microphone),
                          ),
                  ),
                ]),
        ),
      ),
    ]);
  }
}
