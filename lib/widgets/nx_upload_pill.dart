import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/i18n.dart';
import '../services/photo_upload_center.dart';
import 'nx_icons.dart';

/// Floating upload status shown above every screen while photos are being
/// sent, waiting for signal, or refused. Tap = details (retry / discard).
class NxUploadPill extends StatelessWidget {
  const NxUploadPill({super.key, required this.navigatorKey});

  /// Navigator to open the details sheet on (the pill sits above the router).
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UploadCenterState>(
      valueListenable: PhotoUploadCenter.instance,
      builder: (context, s, _) {
        final mq = MediaQuery.of(context);
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          left: 0,
          right: 0,
          bottom: s.visible ? mq.padding.bottom + 92 : -80,
          child: Center(
            child: AnimatedOpacity(
              opacity: s.visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(ignoring: !s.visible, child: _Pill(state: s, navigatorKey: navigatorKey)),
            ),
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.state, required this.navigatorKey});
  final UploadCenterState state;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // Inverse colours so it reads on any page (like the bulk dock).
    final bg = dark ? Colors.white : const Color(0xFF0F172A);
    final fg = dark ? const Color(0xFF0F172A) : Colors.white;
    final s = state;
    final sending = s.active > 0;
    final String text;
    final IconData icon;
    Color accent = const Color(0xFF6366F1);
    if (sending) {
      text = tr('กำลังอัปโหลด ${s.sent}/${s.total} รูป');
      icon = NxI.cloud;
    } else if (s.failed > 0) {
      text = tr('ส่งไม่สำเร็จ ${s.failed} รูป · แตะเพื่อจัดการ');
      icon = NxI.warning;
      accent = const Color(0xFFF43F5E);
    } else {
      text = s.offline ? tr('รอสัญญาณ · ค้างส่ง ${s.waiting} รูป') : tr('รอส่ง ${s.waiting} รูป');
      icon = NxI.cloud;
      accent = const Color(0xFFF59E0B);
    }
    return Material(
      key: const ValueKey('upload-pill'),
      color: bg,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () {
          HapticFeedback.selectionClick();
          final ctx = navigatorKey?.currentContext ?? context;
          showUploadQueueSheet(ctx);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 16, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: Stack(alignment: Alignment.center, children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: sending ? s.fraction : 1),
                    duration: const Duration(milliseconds: 300),
                    builder: (_, v, _) => CircularProgressIndicator(
                      value: sending && s.total == 0 ? null : v,
                      strokeWidth: 2.6,
                      color: accent,
                      backgroundColor: fg.withValues(alpha: 0.15),
                    ),
                  ),
                  Icon(icon, size: 13, color: fg),
                ]),
              ),
              const SizedBox(width: 10),
              Text(text, style: theme.textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saved photos with their record: retry all / discard one.
Future<void> showUploadQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => const _QueueSheet(),
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final center = PhotoUploadCenter.instance;
    return ValueListenableBuilder<UploadCenterState>(
      valueListenable: center,
      builder: (context, s, _) {
        final items = center.items.where((q) => q.scope == center.scope).toList();
        final other = center.items.length - items.length;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(tr('รูปที่รออัปโหลด'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    tr('รูปเก็บไว้ในเครื่องแล้ว ปิดแอปหรือเน็ตหลุดก็ไม่หาย — ระบบจะส่งให้เองเมื่อมีสัญญาณ'),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                if (s.active > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(tr('กำลังอัปโหลด ${s.sent}/${s.total} รูป'), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: s.total == 0 ? null : s.fraction, minHeight: 6)),
                    ]),
                  ),
                Flexible(
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(tr(other > 0 ? 'มีรูปของพื้นที่ทำงานอื่น $other รูป — จะส่งเมื่อสลับไปพื้นที่ทำงานนั้น' : 'ไม่มีรูปค้างส่ง'),
                              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final q = items[i];
                            return ListTile(
                              key: ValueKey('upload-q-${q.clientId}'),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(File(q.path), width: 48, height: 48, fit: BoxFit.cover, cacheWidth: 144,
                                    errorBuilder: (_, _, _) => Container(width: 48, height: 48, color: cs.surfaceContainerHighest, child: const Icon(NxI.image))),
                              ),
                              title: Text(q.title ?? '${_moduleLabel(q.module)} #${q.recordId}', maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                q.failed ? tr('เซิร์ฟเวอร์ไม่รับรูปนี้ — ลองใหม่หรือลบ') : tr('รอส่ง'),
                                style: TextStyle(color: q.failed ? cs.error : cs.onSurfaceVariant),
                              ),
                              trailing: IconButton(
                                tooltip: tr('ลบรูปนี้'),
                                icon: const Icon(NxI.trash),
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (d) => AlertDialog(
                                      title: Text(tr('ลบรูปที่ยังไม่ได้ส่ง?')),
                                      content: Text(tr('รูปนี้ยังไม่ถึงเซิร์ฟเวอร์ ลบแล้วจะกู้คืนไม่ได้')),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('ยกเลิก'))),
                                        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('ลบ'))),
                                      ],
                                    ),
                                  );
                                  if (ok == true) await center.discard(q.clientId);
                                },
                              ),
                            );
                          },
                        ),
                ),
                if (items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: FilledButton.icon(
                      key: const ValueKey('upload-q-send'),
                      onPressed: s.active > 0 ? null : () => center.drain(context.read<AppConfig>().apiClient, includeFailed: true),
                      icon: const Icon(NxI.arrowsClockwise, size: 18),
                      label: Text(tr('ส่งตอนนี้')),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _moduleLabel(String m) => tr(switch (m) {
      'job' => 'ใบสั่งงาน',
      'activity' => 'กิจกรรม',
      'quotation' => 'ใบเสนอราคา',
      'case' => 'เคส',
      _ => m,
    });
