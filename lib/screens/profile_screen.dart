import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/nx_breakpoint.dart';
import '../services/api_client.dart';
import '../services/device_push_service.dart';
import '../widgets/nx_app_header.dart';
import '../widgets/nx_hero_cta.dart';
import '../widgets/nx_surface_card.dart';
import '../widgets/nx_icons.dart';

/// Phase 7 — โปรไฟล์, ภาษา/รูปแบบวันที่, รหัสผ่าน/2FA placeholder, accent, avatar (C1)
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<AppConfig>();
    final email = config.session.email ?? '—';
    final b64 = config.profileAvatarBase64;

    Widget avatar;
    if (b64 != null && b64.isNotEmpty) {
      try {
        final bytes = base64Decode(b64);
        avatar = CircleAvatar(
          radius: 48,
          backgroundColor: theme.colorScheme.primaryContainer,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {
        avatar = CircleAvatar(
          radius: 48,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(NxI.userFill, size: 48, color: theme.colorScheme.primary),
        );
      }
    } else {
      avatar = CircleAvatar(
        radius: 48,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(NxI.userFill, size: 48, color: theme.colorScheme.primary),
      );
    }

    return Scaffold(
      appBar: const NxAppHeader(title: 'โปรไฟล์'),
      body: ListView(
        padding: NxBreakpoint.of(context).scrollPadding(context),
        children: [
          NxSurfaceCard(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              children: [
                avatar,
                const SizedBox(height: 12),
                Text(email, style: theme.textTheme.titleMedium),
                Text(
                  'v0.02.000',
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                Text(
                  'รูปโปรไฟล์อัปโหลดไปเซิร์ฟเวอร์',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                NxHeroCta(
                  label: 'เลือกรูป',
                  onPressed: () async {
                    try {
                      await config.uploadProfileAvatarToServer();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(formatApiError(e))),
                        );
                      }
                    }
                  },
                ),
                if (b64 != null && b64.isNotEmpty)
                  TextButton(
                    onPressed: () => config.clearProfileAvatar(),
                    child: const Text('ลบรูป'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'การแสดงผล',
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            child: Column(
              children: [
                ListTile(
                  title: const Text('ภาษา UI (บันทึกในเครื่อง)'),
                  subtitle: Text(config.uiLocaleCode == 'th' ? 'ไทย' : 'English'),
                  trailing: DropdownButton<String>(
                    value: config.uiLocaleCode,
                    items: const [
                      DropdownMenuItem(value: 'th', child: Text('ไทย')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: (v) {
                      if (v != null) config.setUiLocaleCode(v);
                    },
                  ),
                ),
                ListTile(
                  title: const Text('รูปแบบวันที่/เวลา'),
                  subtitle: Text(config.dateFormatPattern),
                  trailing: DropdownButton<String>(
                    value: config.dateFormatPattern,
                    items: const [
                      DropdownMenuItem(value: 'dd/MM/yyyy HH:mm', child: Text('dd/MM/yyyy HH:mm')),
                      DropdownMenuItem(value: 'yyyy-MM-dd HH:mm', child: Text('yyyy-MM-dd HH:mm')),
                      DropdownMenuItem(value: 'MM/dd/yyyy h:mm a', child: Text('MM/dd/yyyy h:mm a')),
                    ],
                    onChanged: (v) {
                      if (v != null) config.setDateFormatPattern(v);
                    },
                  ),
                ),
                ListTile(
                  title: const Text('สีเน้น (accent)'),
                  subtitle: const Text('เก็บใน SharedPreferences'),
                  trailing: DropdownButton<int>(
                    value: config.accentIndex.clamp(0, AppConfig.accentOptions.length - 1),
                    items: List.generate(
                      AppConfig.accentOptions.length,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppConfig.accentOptions[i],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('ตัวเลือก ${i + 1}'),
                          ],
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      if (v != null) config.setAccentIndex(v);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'ความปลอดภัย',
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(NxI.password),
                  title: const Text('เปลี่ยนรหัสผ่าน'),
                  subtitle: const Text('รหัสปัจจุบัน + รหัสใหม่ (ยืนยัน)'),
                  onTap: () async {
                    final current = TextEditingController();
                    final next = TextEditingController();
                    final confirm = TextEditingController();
                    final formKey = GlobalKey<FormState>();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('เปลี่ยนรหัสผ่าน'),
                        content: Form(
                          key: formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                controller: current,
                                obscureText: true,
                                decoration: const InputDecoration(labelText: 'รหัสผ่านปัจจุบัน'),
                                validator: (v) =>
                                    (v == null || v.isEmpty) ? 'กรุณากรอก' : null,
                              ),
                              TextFormField(
                                controller: next,
                                obscureText: true,
                                decoration: const InputDecoration(labelText: 'รหัสผ่านใหม่'),
                                validator: (v) =>
                                    (v == null || v.length < 6) ? 'อย่างน้อย 6 ตัวอักษร' : null,
                              ),
                              TextFormField(
                                controller: confirm,
                                obscureText: true,
                                decoration: const InputDecoration(labelText: 'ยืนยันรหัสใหม่'),
                                validator: (v) =>
                                    v != next.text ? 'รหัสไม่ตรงกัน' : null,
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
                          FilledButton(
                            onPressed: () {
                              if (formKey.currentState?.validate() == true) {
                                Navigator.pop(ctx, true);
                              }
                            },
                            child: const Text('บันทึก'),
                          ),
                        ],
                      ),
                    );
                    final value = next.text;
                    current.dispose();
                    next.dispose();
                    confirm.dispose();
                    if (ok == true) {
                      try {
                        await config.apiClient.changePassword(value);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('เปลี่ยนรหัสแล้ว')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(formatApiError(e))),
                          );
                        }
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(NxI.bell),
                  title: const Text('โทเคนพุช (FCM)'),
                  subtitle: Text(
                    DevicePushService.instance.lastToken == null ||
                            DevicePushService.instance.lastToken!.isEmpty
                        ? 'ยังไม่มี — เปิดแอปบนมือถือจริงแล้วล็อกอิน'
                        : DevicePushService.instance.lastToken!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    var token = DevicePushService.instance.lastToken;
                    if (token == null || token.isEmpty) {
                      await config.syncPushToken();
                      token = DevicePushService.instance.lastToken;
                    }
                    if (token == null || token.isEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('ยังไม่มีโทเคน — ใช้แอปบน Android หลังวาง google-services.json')),
                        );
                      }
                      return;
                    }
                    await Clipboard.setData(ClipboardData(text: token));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('คัดลอกโทเคนแล้ว — วางใน Firebase Cloud Messaging เพื่อทดสอบ')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(NxI.shieldCheck),
                  title: const Text('Two-factor (2FA)'),
                  subtitle: const Text('ยังไม่เปิดใช้บนเซิร์ฟเวอร์มือถือ'),
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Two-factor authentication'),
                        content: const Text(
                          'แอปยังไม่มี endpoint 2FA จาก NEXTX web API '
                          'เมื่อเซิร์ฟเวอร์เปิดใช้ จะเชื่อมจากหน้านี้',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ปิด')),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
