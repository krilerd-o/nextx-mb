import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../services/ongoing/ongoing_activities.dart';
import 'app_bottom_sheet.dart';
import 'nx_icons.dart';

/// Ask before switching business while a call, meeting room, recording or upload is running.
/// Recordings and uploads carry on in the business they started in; a call / room stays open too.
/// Returns true to go ahead.
Future<bool> confirmBusinessSwitch(BuildContext context, {List<OngoingActivity>? running}) async {
  final list = running ?? ongoingActivities();
  if (list.isEmpty) return true;
  final ok = await showAppBottomSheet<bool>(
    context: context,
    title: tr('มีงานที่กำลังทำอยู่'),
    child: Column(
      key: const Key('business-switch-guard'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_icon(a.kind)),
            title: Text(tr(a.label)),
          ),
        const SizedBox(height: 4),
        Text(
          tr('สลับธุรกิจได้เลย — การบันทึกและอัปโหลดจะทำต่อในธุรกิจเดิมจนเสร็จ สายและห้องประชุมยังเปิดอยู่'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('business-switch-continue'),
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
          child: Text(tr('สลับธุรกิจ')),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
          child: Text(tr('ยกเลิก')),
        ),
      ],
    ),
  );
  return ok == true;
}

IconData _icon(String kind) => switch (kind) {
      'call' => NxI.phone,
      'room' => NxI.videoCamera,
      'upload' => NxI.cloud,
      _ => NxI.microphone,
    };
