import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../services/api_client.dart';
import '../core/i18n.dart';

bool _showing = false;

/// Signed in + an invite link is waiting: ask to join that business
/// (`POST /api/me/request-join`). Returns true when the user joined.
Future<bool> maybePromptInviteJoin(BuildContext context) async {
  final config = context.read<AppConfig>();
  final invite = config.pendingInvite;
  if (invite == null || !config.isLoggedIn || _showing) return false;
  _showing = true;
  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('เข้าร่วมธุรกิจจากลิงก์เชิญ')),
        content: Text(tr('เข้าร่วมธุรกิจด้วยบัญชี ${config.session.email ?? config.session.displayName ?? ''} ใช่ไหม')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ไม่ใช่ตอนนี้'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('เข้าร่วม'))),
        ],
      ),
    );
    if (ok != true) {
      config.clearPendingInvite();
      return false;
    }
    if (!context.mounted) return false;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final r = await config.joinWithInvite(invite.token);
      messenger?.showSnackBar(SnackBar(
        content: Text(tr(r['already_member'] == true ? 'คุณอยู่ในธุรกิจนี้แล้ว' : 'เข้าร่วมธุรกิจแล้ว — เลือกธุรกิจเพื่อเริ่มใช้งาน')),
      ));
      return true;
    } catch (e) {
      config.clearPendingInvite();
      messenger?.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      return false;
    }
  } finally {
    _showing = false;
  }
}
