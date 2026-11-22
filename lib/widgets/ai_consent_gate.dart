import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/ai_consent.dart';
import '../core/app_config.dart';
import '../core/i18n.dart';
import '../core/legal_links.dart';
import 'app_bottom_sheet.dart';
import 'nx_icons.dart';

String? _uid(BuildContext context) {
  try {
    return context.read<AppConfig>().session.userId;
  } catch (_) {
    return null;
  }
}

/// What is sent, to whom and why — shown before the first AI feature (App Store 5.1.2(i)).
class AiConsentContent extends StatelessWidget {
  const AiConsentContent({super.key, required this.onAccept, required this.onDecline});
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(tr(text), style: theme.textTheme.bodyMedium)),
          ]),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
          child: Icon(NxI.robot, color: theme.colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(tr('ก่อนใช้ AI ของไอแซค'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
      ]),
      const SizedBox(height: 14),
      Text(
        tr('ฟีเจอร์ AI จะส่งข้อมูลที่คุณใช้ไปยังผู้ให้บริการ AI ภายนอก (OpenAI, Anthropic หรือผู้ให้บริการที่ธุรกิจของคุณเลือก) เพื่อถอดเสียง สรุป แปล และตอบคำถาม เช่น ข้อความที่คุณถาม ข้อมูลงานที่เกี่ยวข้อง เสียงและบทถอดเสียงการประชุม และเอกสารในสมุดโน้ต'),
        style: theme.textTheme.bodyMedium?.copyWith(color: muted, height: 1.45),
      ),
      point(NxI.shieldCheck, 'ใช้เพื่อสร้างผลลัพธ์ที่คุณขอเท่านั้น ไม่ขาย และไม่ใช้เพื่อโฆษณา'),
      point(NxI.shield, 'ผู้ให้บริการ AI ไม่นำข้อมูลไปฝึกโมเดล ตามเงื่อนไขการใช้งานแบบ API'),
      point(NxI.info, 'ถ้าไม่อนุญาต ฟีเจอร์ AI จะปิด ส่วนอื่นของแอปใช้ได้ตามปกติ · เปลี่ยนได้ที่ โปรไฟล์ → ความเป็นส่วนตัวและ AI'),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('ai-consent-privacy'),
          onPressed: () => openLegal(LegalPage.privacy),
          icon: const Icon(NxI.arrowSquareOut, size: 16),
          label: Text(tr('อ่านนโยบายความเป็นส่วนตัว')),
        ),
      ),
      const SizedBox(height: 6),
      FilledButton(key: const ValueKey('ai-consent-accept'), onPressed: onAccept, child: Text(tr('อนุญาตและใช้ AI'))),
      const SizedBox(height: 6),
      TextButton(key: const ValueKey('ai-consent-decline'), onPressed: onDecline, child: Text(tr('ไม่ใช่ตอนนี้'))),
    ]);
  }
}

/// Asks once (bottom sheet) when the answer is not "allowed" yet. True = AI may be used.
Future<bool> ensureAiConsent(BuildContext context) async {
  final uid = _uid(context);
  if (await AiConsent.instance.isGranted(uid)) return true;
  if (!context.mounted) return false;
  final ok = await showAppBottomSheet<bool>(
    context: context,
    title: null,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Builder(
        builder: (ctx) => AiConsentContent(
          onAccept: () => Navigator.pop(ctx, true),
          onDecline: () => Navigator.pop(ctx, false),
        ),
      ),
    ),
  );
  await AiConsent.instance.set(uid, ok == true);
  return ok == true;
}

/// Wraps an AI screen: shows it only after consent, otherwise the consent page in its place.
class AiConsentGate extends StatefulWidget {
  const AiConsentGate({super.key, required this.child});
  final Widget child;

  @override
  State<AiConsentGate> createState() => _AiConsentGateState();
}

class _AiConsentGateState extends State<AiConsentGate> {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    AiConsent.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AiConsent.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid(context);
    final known = AiConsent.instance.peek(uid);
    if (known != null) {
      if (mounted && known != _granted) setState(() => _granted = known);
      if (known) return;
    }
    final g = await AiConsent.instance.isGranted(uid);
    if (mounted && g != _granted) setState(() => _granted = g);
  }

  @override
  Widget build(BuildContext context) {
    final g = _granted ?? AiConsent.instance.peek(_uid(context));
    if (g == true) return widget.child;
    if (g == null) return const Scaffold(body: SizedBox.shrink());
    return Scaffold(
      key: const ValueKey('ai-consent-page'),
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AiConsentContent(
                onAccept: () => AiConsent.instance.set(_uid(context), true),
                onDecline: () async {
                  await AiConsent.instance.set(_uid(context), false);
                  if (!context.mounted) return;
                  final nav = Navigator.of(context);
                  if (nav.canPop()) {
                    nav.pop();
                  } else {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(content: Text(tr('ฟีเจอร์ AI ปิดอยู่ · เปิดได้ที่ โปรไฟล์ → ความเป็นส่วนตัวและ AI'))),
                    );
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
