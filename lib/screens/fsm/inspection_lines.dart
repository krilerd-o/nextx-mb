import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../services/file_open.dart';
import '../../widgets/nx_icons.dart';
import '../docs/document_preview.dart';

/// Result of one inspection line.
enum InspResult { none, pass, fail, na }

InspResult inspResultOf(Map<String, dynamic> l) => switch ('${l['item_result'] ?? l['result'] ?? ''}'.toLowerCase()) {
  'pass' => InspResult.pass,
  'fail' => InspResult.fail,
  'na' || 'n/a' => InspResult.na,
  _ => InspResult.none,
};

String? _resultValue(InspResult r) => switch (r) {
  InspResult.pass => 'pass',
  InspResult.fail => 'fail',
  InspResult.na => 'na',
  InspResult.none => null,
};

/// Ready-made checklists (same as the server's defaults per template).
const kInspectionPresets = <String, List<String>>{
  'งานบริการ / PM': ['ตรวจสภาพทั่วไป', 'ทำความสะอาด / บำรุงรักษาตามแผน', 'ทดสอบการทำงานหลัง PM', 'ลูกค้ายืนยันการให้บริการ'],
  'งานซ่อม': ['รับทราบอาการ / ปัญหา', 'วินิจฉัยสาเหตุ', 'ดำเนินการซ่อม / แก้ไข', 'ทดสอบหลังซ่อม', 'ลูกค้ายืนยันปิดงาน'],
  'ตรวจรับติดตั้ง': ['ตรวจความปลอดภัย', 'ตรวจการติดตั้ง', 'ตรวจเอกสารส่งมอบ'],
};

/// Inspection checklist editor: big Pass / Fail / N/A buttons, progress,
/// add a line from the box at the bottom (or a ready-made set), optional
/// remark per line, delete. Saves automatically (the server replaces all
/// lines at once) and shows "saved" / errors clearly.
class InspectionLinesEditor extends StatefulWidget {
  const InspectionLinesEditor({super.key, required this.inspectionId, this.canEdit = true, this.showPdf = true});
  final String inspectionId;
  final bool canEdit;
  final bool showPdf;

  @override
  State<InspectionLinesEditor> createState() => _InspectionLinesEditorState();
}

class _InspectionLinesEditorState extends State<InspectionLinesEditor> {
  final List<Map<String, dynamic>> _lines = [];
  final _add = TextEditingController();
  final _addFocus = FocusNode();
  final Set<int> _remarkOpen = {};
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _savedOnce = false;
  Object? _error;
  Timer? _debounce;
  int? _flash;

  late final ApiClient _api = context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _api; // read while the context is valid (dispose saves with it)
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_dirty) _save(); // keep what was typed when leaving the page
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await _api.getInspectionLines(widget.inspectionId);
      if (!mounted) return;
      setState(() {
        _lines
          ..clear()
          ..addAll(l.map((e) => Map<String, dynamic>.from(e)));
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  void _changed({bool now = false}) {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: now ? 50 : 900), _save);
    setState(() {});
  }

  Future<void> _save() async {
    if (!_dirty) return;
    _dirty = false;
    if (mounted) setState(() => _saving = true);
    try {
      await _api.putInspectionLines(widget.inspectionId, [
        for (var i = 0; i < _lines.length; i++)
          {
            'line_no': i + 1,
            'item_label': '${_lines[i]['item_label'] ?? ''}'.trim(),
            'item_result': _lines[i]['item_result'],
            'remark': '${_lines[i]['remark'] ?? ''}'.trim().isEmpty ? null : '${_lines[i]['remark']}'.trim(),
            if (_lines[i]['photo_path'] != null) 'photo_path': _lines[i]['photo_path'],
          },
      ]);
      if (mounted) {
        setState(() {
          _saving = false;
          _savedOnce = true;
          _error = null;
        });
      }
    } catch (e) {
      _dirty = true;
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e;
        });
      }
    }
  }

  void _addLine([String? label]) {
    final text = (label ?? _add.text).trim();
    if (text.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _lines.add({'item_label': text, 'item_result': null, 'remark': null});
      _flash = _lines.length - 1;
      if (label == null) _add.clear();
    });
    _changed(now: true);
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _flash = null);
    });
    if (label == null) _addFocus.requestFocus();
  }

  void _addPreset(List<String> items) {
    final have = {for (final l in _lines) '${l['item_label']}'.trim()};
    var n = 0;
    for (final t in items) {
      if (!have.contains(t)) {
        _lines.add({'item_label': t, 'item_result': null, 'remark': null});
        n++;
      }
    }
    if (n == 0) return;
    _changed(now: true);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('เพิ่ม $n รายการแล้ว'))));
  }

  void _setResult(int i, InspResult r) {
    HapticFeedback.selectionClick();
    final cur = inspResultOf(_lines[i]);
    _lines[i]['item_result'] = _resultValue(cur == r ? InspResult.none : r);
    _changed(now: true);
  }

  Future<void> _rename(int i) async {
    final c = TextEditingController(text: '${_lines[i]['item_label'] ?? ''}');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('แก้ชื่อรายการ')),
        content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: Text(tr('บันทึก'))),
        ],
      ),
    );
    if (v == null || v.trim().isEmpty) return;
    _lines[i]['item_label'] = v.trim();
    _changed(now: true);
  }

  void _remove(int i) {
    final removed = _lines.removeAt(i);
    _remarkOpen.clear();
    _changed(now: true);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(tr('ลบรายการแล้ว')),
        action: SnackBarAction(
          label: tr('เลิกทำ'),
          onPressed: () {
            if (!mounted) return;
            _lines.insert(i.clamp(0, _lines.length), removed);
            _changed(now: true);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final counts = {for (final r in InspResult.values) r: 0};
    for (final l in _lines) {
      counts[inspResultOf(l)] = counts[inspResultOf(l)]! + 1;
    }
    final total = _lines.length;
    final done = total - counts[InspResult.none]!;
    return Column(
      key: const ValueKey('insp-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(tr('รายการตรวจ ($total)'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _saving
                  ? Row(
                      key: const ValueKey('saving'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 6),
                        Text(tr('กำลังบันทึก…'), style: theme.textTheme.labelSmall),
                      ],
                    )
                  : _error != null && _savedOnce
                  ? TextButton.icon(
                      key: const ValueKey('insp-retry'),
                      onPressed: () {
                        _dirty = true;
                        _save();
                      },
                      icon: Icon(NxI.warning, size: 16, color: cs.error),
                      label: Text(tr('บันทึกไม่สำเร็จ — ลองใหม่'), style: TextStyle(color: cs.error)),
                    )
                  : _savedOnce
                  ? Row(
                      key: const ValueKey('insp-saved'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(NxI.checkCircle, size: 16, color: Color(0xFF16A34A)),
                        const SizedBox(width: 4),
                        Text(tr('บันทึกแล้ว'), style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFF16A34A))),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        if (total > 0) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(key: const ValueKey('insp-progress'), value: total == 0 ? 0 : done / total, minHeight: 7),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            children: [
              _count(context, 'ผ่าน', counts[InspResult.pass]!, const Color(0xFF16A34A)),
              _count(context, 'ไม่ผ่าน', counts[InspResult.fail]!, cs.error),
              _count(context, 'N/A', counts[InspResult.na]!, cs.outline),
              _count(context, 'ยังไม่ตรวจ', counts[InspResult.none]!, const Color(0xFFD97706)),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_loading && _error != null && !_savedOnce)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(
                  formatApiError(_error!),
                  style: TextStyle(color: cs.error),
                  textAlign: TextAlign.center,
                ),
                TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
              ],
            ),
          ),
        if (!_loading && total == 0 && _error == null)
          Container(
            key: const ValueKey('insp-empty'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                Icon(NxI.clipboardText, size: 32, color: cs.outline),
                const SizedBox(height: 8),
                Text(tr('ยังไม่มีรายการตรวจ'), style: theme.textTheme.titleSmall),
                Text(tr(widget.canEdit ? 'พิมพ์รายการด้านล่าง หรือเลือกชุดรายการมาตรฐาน' : '—'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        for (var i = 0; i < _lines.length; i++) _lineCard(context, i),
        if (widget.canEdit && !_loading) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('insp-add-field'),
                  controller: _add,
                  focusNode: _addFocus,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(hintText: tr('เพิ่มรายการตรวจ เช่น ตรวจแรงดันน้ำยา'), prefixIcon: const Icon(NxI.plus, size: 18)),
                  onSubmitted: (_) => _addLine(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(key: const ValueKey('insp-add-btn'), onPressed: () => _addLine(), child: Text(tr('เพิ่ม'))),
            ],
          ),
          const SizedBox(height: 10),
          Text(tr('ชุดรายการมาตรฐาน'), style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in kInspectionPresets.entries)
                ActionChip(key: ValueKey('insp-preset-${e.key}'), avatar: const Icon(NxI.listChecks, size: 16), label: Text('${tr(e.key)} (${e.value.length})'), onPressed: () => _addPreset(e.value)),
            ],
          ),
        ],
        if (widget.showPdf) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('insp-pdf'),
            onPressed: () async {
              await _save();
              if (!context.mounted) return;
              await openDocumentPreview(context, inspectionDocumentSource(widget.inspectionId));
            },
            icon: const Icon(NxI.filePdf, size: 18),
            label: Text(tr('ดูเอกสารใบตรวจรับ')),
          ),
        ],
      ],
    );
  }

  Widget _count(BuildContext context, String label, int n, Color c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text('${tr(label)} $n', style: Theme.of(context).textTheme.labelSmall),
    ],
  );

  Widget _lineCard(BuildContext context, int i) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = _lines[i];
    final r = inspResultOf(l);
    final remark = '${l['remark'] ?? ''}';
    final showRemark = _remarkOpen.contains(i) || remark.trim().isNotEmpty;
    final accent = switch (r) {
      InspResult.pass => const Color(0xFF16A34A),
      InspResult.fail => cs.error,
      InspResult.na => cs.outline,
      InspResult.none => cs.outlineVariant,
    };
    Widget btn(InspResult v, String label, IconData icon, Color c) {
      final on = r == v;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: on ? c : c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: ValueKey('insp-$i-${v.name}'),
              borderRadius: BorderRadius.circular(12),
              onTap: widget.canEdit ? () => _setResult(i, v) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: on ? Colors.white : c),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        tr(label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(color: on ? Colors.white : c, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      key: ValueKey('insp-line-$i'),
      duration: const Duration(milliseconds: 400),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _flash == i ? cs.primary.withValues(alpha: 0.12) : theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      // Rounded borders must be one colour, so the result colour is a bar.
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: AnimatedContainer(duration: const Duration(milliseconds: 250), color: accent),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle),
                      child: Text('${i + 1}', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: widget.canEdit ? () => _rename(i) : null,
                        child: Text('${l['item_label'] ?? ''}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.4)),
                      ),
                    ),
                    if (widget.canEdit)
                      PopupMenuButton<String>(
                        key: ValueKey('insp-menu-$i'),
                        icon: const Icon(NxI.dotsThree, size: 18),
                        onSelected: (v) => switch (v) {
                          'rename' => _rename(i),
                          'remark' => setState(() => _remarkOpen.add(i)),
                          _ => _remove(i),
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'rename', child: Text(tr('แก้ชื่อรายการ'))),
                          PopupMenuItem(value: 'remark', child: Text(tr('เพิ่มหมายเหตุ'))),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(tr('ลบรายการ'), style: TextStyle(color: cs.error)),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(children: [btn(InspResult.pass, 'ผ่าน', NxI.check, const Color(0xFF16A34A)), btn(InspResult.fail, 'ไม่ผ่าน', NxI.x, cs.error), btn(InspResult.na, 'N/A', NxI.minus, cs.outline)]),
                if (showRemark) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey('insp-remark-$i-${l['item_label']}'),
                    enabled: widget.canEdit,
                    initialValue: remark,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: tr('หมายเหตุ'), isDense: true),
                    onChanged: (v) {
                      _lines[i]['remark'] = v;
                      _dirty = true;
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 900), _save);
                    },
                  ),
                ] else if (widget.canEdit)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: ValueKey('insp-add-remark-$i'),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
                      onPressed: () => setState(() => _remarkOpen.add(i)),
                      child: Text(tr('+ หมายเหตุ')),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
