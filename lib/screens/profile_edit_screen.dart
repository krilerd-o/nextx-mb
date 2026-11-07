import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../services/api_client.dart';
import '../widgets/nx_app_header.dart';
import '../widgets/nx_skeleton.dart';
import '../core/i18n.dart';

/// Editable fields of `PUT /api/me/profile` (NEXTX PROFILE_UPDATE_SETS).
const profileEditableFields = <String, String>{
  'first_name': 'ชื่อ (อังกฤษ)',
  'last_name': 'นามสกุล (อังกฤษ)',
  'first_name_th': 'ชื่อ (ไทย)',
  'last_name_th': 'นามสกุล (ไทย)',
  'title': 'ตำแหน่ง',
  'department': 'แผนก',
  'phone_mobile': 'มือถือ',
  'phone_work': 'โทรศัพท์ที่ทำงาน',
  'description': 'เกี่ยวกับฉัน',
  'signature': 'ลายเซ็นอีเมล',
};

/// Only fields that changed, so the server keeps everything else as is.
Map<String, dynamic> profileChanges(Map<String, dynamic> original, Map<String, String> edited) {
  final out = <String, dynamic>{};
  edited.forEach((k, v) {
    final before = original[k]?.toString() ?? '';
    if (v.trim() != before.trim()) out[k] = v.trim();
  });
  return out;
}

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _c = {
    for (final k in profileEditableFields.keys) k: TextEditingController(),
  };
  Map<String, dynamic> _original = {};
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await context.read<AppConfig>().apiClient.getMyProfile();
      if (!mounted) return;
      setState(() {
        _original = p;
        for (final e in _c.entries) {
          e.value.text = p[e.key]?.toString() ?? '';
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_form.currentState?.validate() != true) return;
    final changes = profileChanges(_original, {for (final e in _c.entries) e.key: e.value.text});
    if (changes.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    final config = context.read<AppConfig>();
    try {
      await config.apiClient.updateMyProfile(changes);
      await config.refreshSession();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('บันทึกโปรไฟล์แล้ว'))));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NxAppHeader(
        title: 'แก้ไขโปรไฟล์',
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('บันทึก')),
          ),
        ],
      ),
      body: _loading
          ? const NxSkeletonList()
          : _error != null
              ? Center(child: Text(tr(formatApiError(_error!))))
              : Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final e in profileEditableFields.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextFormField(
                            controller: _c[e.key],
                            decoration: InputDecoration(labelText: trn(e.value), border: const OutlineInputBorder()),
                            keyboardType: e.key.startsWith('phone') ? TextInputType.phone : TextInputType.text,
                            minLines: e.key == 'description' || e.key == 'signature' ? 3 : 1,
                            maxLines: e.key == 'description' || e.key == 'signature' ? 6 : 1,
                            validator: e.key == 'first_name'
                                ? (v) => (v == null || v.trim().isEmpty) && (_c['first_name_th']!.text.trim().isEmpty)
                                    ? 'กรุณาใส่ชื่ออย่างน้อยหนึ่งภาษา'
                                    : null
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
