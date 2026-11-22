import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai_consent.dart';
import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/legal_links.dart';
import '../../services/api_client.dart';
import '../../widgets/ai_consent_gate.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/settings_tiles.dart';
import 'profile_ui.dart';

/// Profile → ความเป็นส่วนตัวและ AI: the AI consent (App Store 5.1.2(i)), the privacy policy / terms /
/// account-deletion pages, and "delete my data" for AI Minute Meeting and Notebook recordings in one place.
class PrivacyAiScreen extends StatefulWidget {
  const PrivacyAiScreen({super.key});

  @override
  State<PrivacyAiScreen> createState() => _PrivacyAiScreenState();
}

class _PrivacyAiScreenState extends State<PrivacyAiScreen> {
  bool? _ai;

  String? get _uid => context.read<AppConfig>().session.userId;

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
    final g = await AiConsent.instance.isGranted(_uid);
    if (mounted) setState(() => _ai = g);
  }

  Future<void> _setAi(bool on) async {
    if (on) {
      await ensureAiConsent(context);
    } else {
      await AiConsent.instance.set(_uid, false);
    }
    await _load();
  }

  void _snack(String text) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _deleteMeetings() async {
    final ok = await showDeleteConfirm(
      context,
      title: tr('ลบข้อมูลการประชุมของฉัน'),
      name: tr('ข้อมูลการประชุมของฉัน'),
      loses: const [
        'การประชุมทั้งหมดที่ฉันสร้างในธุรกิจนี้ (ไฟล์ ถอดเสียง สรุป โน้ต แชท)',
        'ข้อความที่ฉันพูดและพิมพ์ในห้องประชุมของคนอื่น',
      ],
      note: 'ย้อนกลับไม่ได้',
    );
    if (!ok || !mounted) return;
    try {
      final r = await context.read<AppConfig>().apiClient.deleteMyMinuteData();
      _snack(tr('ลบแล้ว: ${r['meetings'] ?? 0} การประชุม, ${r['lines'] ?? 0} ข้อความถอดเสียง, ${r['chat'] ?? 0} แชท'));
    } catch (e) {
      _snack(e is ApiEnvelopeException ? e.message : tr('ลบไม่สำเร็จ ลองใหม่อีกครั้ง'));
    }
  }

  Future<void> _deleteRecordings() async {
    final ok = await showDeleteConfirm(
      context,
      name: tr('บันทึกเสียงทั้งหมดของฉัน'),
      loses: const ['ไฟล์เสียงที่ฉันบันทึกในสมุดโน้ตทุกเล่ม', 'บทถอดข้อความและแหล่งข้อมูลบันทึกเสียง', 'โน้ตสรุปการประชุมจากบันทึกเหล่านั้น'],
      note: 'ลบแล้วกู้คืนไม่ได้ — บันทึกของคนอื่นในเล่มเดียวกันไม่ถูกลบ',
    );
    if (!ok || !mounted) return;
    try {
      final r = await context.read<AppConfig>().apiClient.deleteMyNotebookRecordings();
      final n = (r['recordings'] as num?)?.toInt() ?? 0;
      _snack(n == 0 ? tr('ไม่มีบันทึกเสียงของคุณให้ลบ') : tr('ลบบันทึกเสียงแล้ว $n รายการ'));
    } catch (e) {
      _snack(e is ApiEnvelopeException ? e.message : tr('ลบไม่สำเร็จ ลองใหม่อีกครั้ง'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return ProfileSubPage(title: 'ความเป็นส่วนตัวและ AI', children: [
      SettingsGroup(
        title: 'AI',
        caption: 'ฟีเจอร์ AI ส่งข้อความที่คุณถาม ข้อมูลงานที่เกี่ยวข้อง เสียงและบทถอดเสียงการประชุม และเอกสารในสมุดโน้ต ไปยังผู้ให้บริการ AI ภายนอก (OpenAI, Anthropic หรือที่ธุรกิจเลือก) เพื่อถอดเสียง สรุป แปล และตอบคำถาม',
        children: [
          SettingsTile(
            key: const ValueKey('privacy-ai-consent'),
            icon: NxI.robot,
            tint: const Color(0xFF8B5CF6),
            title: 'อนุญาตให้ใช้ AI',
            subtitle: _ai == true ? 'เปิดอยู่ · ปิดได้ทุกเมื่อ' : 'ปิดอยู่ · ฟีเจอร์ AI ใช้ไม่ได้จนกว่าจะอนุญาต',
            trailing: Switch(
              key: const ValueKey('privacy-ai-switch'),
              value: _ai == true,
              onChanged: _ai == null ? null : _setAi,
            ),
          ),
        ],
      ),
      SettingsGroup(title: 'เอกสาร', children: [
        SettingsTile(
          key: const ValueKey('privacy-open-policy'),
          icon: NxI.shieldCheck,
          tint: const Color(0xFF10B981),
          title: 'นโยบายความเป็นส่วนตัว',
          onTap: () => openLegal(LegalPage.privacy),
        ),
        SettingsTile(
          key: const ValueKey('privacy-open-terms'),
          icon: NxI.info,
          tint: const Color(0xFF3B82F6),
          title: 'ข้อกำหนดการใช้บริการ',
          onTap: () => openLegal(LegalPage.terms),
        ),
        SettingsTile(
          key: const ValueKey('privacy-open-deletion'),
          icon: NxI.arrowSquareOut,
          tint: const Color(0xFF64748B),
          title: 'วิธีลบบัญชีและข้อมูล',
          onTap: () => openLegal(LegalPage.accountDeletion),
        ),
      ]),
      SettingsGroup(title: 'ลบข้อมูลของฉัน', children: [
        SettingsTile(
          key: const ValueKey('privacy-delete-meetings'),
          icon: NxI.trash,
          tint: danger,
          title: 'ลบข้อมูลการประชุมของฉัน',
          subtitle: 'AI Minute Meeting ในธุรกิจนี้',
          onTap: _deleteMeetings,
        ),
        SettingsTile(
          key: const ValueKey('privacy-delete-recordings'),
          icon: NxI.trash,
          tint: danger,
          title: 'ลบบันทึกเสียงทั้งหมดของฉัน',
          subtitle: 'บันทึกเสียงในสมุดโน้ตทุกเล่มในธุรกิจนี้',
          onTap: _deleteRecordings,
        ),
      ]),
    ]);
  }
}
