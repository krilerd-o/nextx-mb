import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/app_routes.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_hero_illustration.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';

class _Slide {
  const _Slide(this.title, this.body, this.icon, this.chips);
  final String title;
  final String body;
  final IconData icon;
  final List<NxHeroChip> chips;
}

const _slides = [
  _Slide(
    'ทำงานได้ทุกที่\nครบในแอปเดียว',
    'ลูกค้า งานขาย งานบริการ ทีม และ HR\nเชื่อมกับระบบ MOAI NEXT ของธุรกิจคุณ',
    NxI.squaresFourFill,
    kDefaultHeroChips,
  ),
  _Slide(
    'ปิดการขายได้ไวขึ้น',
    'ลีด ดีล ใบเสนอราคา และการอนุมัติ\nติดตามได้ทันทีจากมือถือ',
    NxI.handshake,
    [
      NxHeroChip(NxI.receipt, 'ใบเสนอราคา QT-0421', 'รออนุมัติขั้นที่ 1', Alignment(-0.92, -0.35), color: Color(0xFF6366F1)),
      NxHeroChip(NxI.checkCircle, 'อนุมัติแล้ว', 'ดีล บริษัท บี ฿89k', Alignment(0.95, -0.05), color: Color(0xFF10B981)),
      NxHeroChip(NxI.calendarCheck, 'นัดลูกค้า 10:30', 'เช็คอินด้วย GPS', Alignment(-0.55, 0.72), color: Color(0xFFF59E0B)),
    ],
  ),
  _Slide(
    'ทีมเดียวกัน ทุกที่ทุกเวลา',
    'แชท งาน Workspace ลงเวลา และการลา\nแจ้งเตือนทันทีเมื่อมีอะไรใหม่',
    NxI.chatCircle,
    [
      NxHeroChip(NxI.kanban, 'งาน NSMO-250', 'กำหนดส่งวันนี้', Alignment(-0.92, -0.35), color: Color(0xFF0EA5E9)),
      NxHeroChip(NxI.bellRinging, 'คำขอลาได้รับอนุมัติ', 'ลาพักร้อน 2 วัน', Alignment(0.95, -0.05), color: Color(0xFF10B981)),
      NxHeroChip(NxI.clock, 'ลงเวลาออก 18:02', 'ทำงาน 9 ชม.', Alignment(-0.55, 0.72), color: Color(0xFF6366F1)),
    ],
  ),
];

/// First-run landing: illustrated slides + "เริ่มต้นใช้งาน" / "มีบัญชีอยู่แล้ว".
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pages = PageController();
  var _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final h = MediaQuery.sizeOf(context).height;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _slides.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final s = _slides[i];
                return Column(
                  children: [
                    NxHeroIllustration(height: (h * 0.48).clamp(260, 440).toDouble(), chips: s.chips, centerIcon: s.icon),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          Text(
                            tr(s.title),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr(s.body),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _slides.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _index ? cs.primary : cs.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                children: [
                  NxHeroCta(label: 'เริ่มต้นใช้งาน', onPressed: () => context.go(AppRoutes.server)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                      ),
                      onPressed: () => context.go(AppRoutes.server),
                      child: Text(tr('ฉันมีบัญชีอยู่แล้ว'), style: theme.textTheme.titleSmall),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
