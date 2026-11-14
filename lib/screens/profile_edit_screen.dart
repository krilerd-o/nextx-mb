import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/i18n.dart';
import '../core/nx_page_route.dart';
import '../services/api_client.dart';
import '../widgets/fields/nx_field_chrome.dart';
import '../widgets/nx_icons.dart';
import '../widgets/nx_shake.dart';
import '../widgets/nx_skeleton.dart';
import '../widgets/nx_sliding_segmented.dart';
import '../widgets/nx_unsaved_guard.dart';
import '../widgets/settings_tiles.dart';
import 'profile/phone_change_screen.dart';
import 'profile/profile_ui.dart';

/// One editable text field of `PUT /api/me/profile` (NEXTX PROFILE_UPDATE_SETS).
class ProfileField {
  const ProfileField(this.key, this.label, {this.icon, this.lines = 1, this.max = 255, this.phone = false, this.hint});
  final String key;
  final String label;
  final IconData? icon;
  final int lines;
  final int max;
  final bool phone;
  final String? hint;
}

/// Sections of the edit form, in order. A field shows when the server's
/// profile has it (older servers return fewer columns).
const profileFieldSections = <(String, List<ProfileField>)>[
  ('ชื่อ', [
    ProfileField('first_name_th', 'ชื่อ (ไทย)', icon: NxI.user),
    ProfileField('last_name_th', 'นามสกุล (ไทย)'),
    ProfileField('first_name', 'ชื่อ (อังกฤษ)', icon: NxI.user),
    ProfileField('last_name', 'นามสกุล (อังกฤษ)'),
  ]),
  ('การทำงาน', [
    ProfileField('title', 'ตำแหน่ง', icon: NxI.briefcase),
    ProfileField('department', 'แผนก', icon: NxI.buildings),
  ]),
  ('ติดต่อ', [
    ProfileField('phone_work', 'โทรศัพท์ที่ทำงาน', icon: NxI.phone, phone: true, max: 32),
    ProfileField('phone_home', 'โทรศัพท์บ้าน', icon: NxI.house, phone: true, max: 32),
  ]),
  ('ที่อยู่', [
    ProfileField('address_street', 'ที่อยู่', icon: NxI.mapPin, lines: 2),
    ProfileField('address_city', 'อำเภอ / เขต'),
    ProfileField('address_state', 'จังหวัด'),
    ProfileField('address_postalcode', 'รหัสไปรษณีย์', max: 10),
    ProfileField('address_country', 'ประเทศ'),
  ]),
  ('เกี่ยวกับฉัน', [
    ProfileField('description', 'เกี่ยวกับฉัน', icon: NxI.note, lines: 4, max: 2000),
    ProfileField('signature', 'ลายเซ็นอีเมล', icon: NxI.envelope, lines: 3, max: 2000, hint: 'ต่อท้ายอีเมลที่ส่งจากระบบ'),
  ]),
];

/// Choice fields (segmented): key → options (value, Thai label).
const profileChoiceFields = <String, (String, List<(String, String)>)>{
  'user_language': ('ภาษาบนเว็บ', [('th', 'ไทย'), ('en', 'English')]),
  'hour_format': ('รูปแบบเวลา', [('24', '24 ชั่วโมง'), ('12', '12 ชั่วโมง')]),
  'weekstart': ('วันเริ่มต้นสัปดาห์', [('0', 'อาทิตย์'), ('1', 'จันทร์')]),
};

/// Editable fields of `PUT /api/me/profile` and their Thai labels.
final profileEditableFields = <String, String>{
  for (final s in profileFieldSections)
    for (final f in s.$2) f.key: f.label,
  for (final e in profileChoiceFields.entries) e.key: e.value.$1,
};

/// Only fields that changed, so the server keeps everything else as is.
Map<String, dynamic> profileChanges(Map<String, dynamic> original, Map<String, String> edited) {
  final out = <String, dynamic>{};
  edited.forEach((k, v) {
    final raw = original[k];
    final before = raw == null || '$raw' == 'null' ? '' : '$raw';
    if (v.trim() != before.trim()) out[k] = k == 'weekstart' ? (int.tryParse(v) ?? 0) : v.trim();
  });
  return out;
}

/// Null when [v] is fine for profile [key], else the Thai reason.
String? profileFieldProblem(String key, String v, {String? otherFirstName}) {
  final t = v.trim();
  if (key == 'first_name_th' && t.isEmpty && (otherFirstName ?? '').trim().isEmpty) return 'กรุณาใส่ชื่ออย่างน้อยหนึ่งภาษา';
  if ((key == 'phone_work' || key == 'phone_home') && t.isNotEmpty && !RegExp(r'^\+?[\d\s\-()#]{6,20}(\s*(ต่อ|ext\.?|x)\s*\d{1,6})?$').hasMatch(t)) {
    return 'เบอร์โทรไม่ถูกต้อง';
  }
  if (key == 'address_postalcode' && t.isNotEmpty && !RegExp(r'^[0-9A-Za-z\- ]{3,10}$').hasMatch(t)) return 'รหัสไปรษณีย์ไม่ถูกต้อง';
  return null;
}

/// "แก้ไขโปรไฟล์": my fields from `GET /api/me/profile`, grouped, saved with
/// `PUT /api/me/profile` (changed fields only). Mobile number changes go
/// through OTP ([PhoneChangeScreen]); leaving with unsaved edits asks first.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _c = {
    for (final s in profileFieldSections)
      for (final f in s.$2) f.key: TextEditingController(),
  };
  final Map<String, String> _choice = {};
  Map<String, dynamic> _original = {};
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    for (final c in _c.values) {
      c.addListener(_changed);
    }
    _load();
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _str(Object? v) => v == null || '$v' == 'null' ? '' : '$v';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await context.read<AppConfig>().apiClient.getMyProfile();
      if (!mounted) return;
      setState(() {
        _original = p;
        for (final e in _c.entries) {
          e.value.text = _str(p[e.key]);
        }
        for (final k in profileChoiceFields.keys) {
          if (p.containsKey(k)) _choice[k] = _str(p[k]).isEmpty ? profileChoiceFields[k]!.$2.first.$1 : _str(p[k]);
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

  /// A field shows when the profile has it; the four name fields always do.
  bool _has(String key) => _original.containsKey(key) || key.contains('name');

  Map<String, String> get _values => {
        for (final e in _c.entries)
          if (_has(e.key)) e.key: e.value.text,
        ..._choice,
      };

  Map<String, dynamic> get _changes {
    // Choices the server had as null count as "unchanged" when left at the default.
    final orig = {..._original};
    for (final k in _choice.keys) {
      if (_str(orig[k]).isEmpty) orig[k] = profileChoiceFields[k]!.$2.first.$1;
    }
    return profileChanges(orig, _values);
  }

  Future<void> _save() async {
    if (_form.currentState?.validate() != true) {
      HapticFeedback.heavyImpact();
      nxRevealFormError(context);
      return;
    }
    final changes = _changes;
    final nav = Navigator.of(context);
    if (changes.isEmpty) {
      nav.pop(false);
      return;
    }
    setState(() => _saving = true);
    final config = context.read<AppConfig>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await config.apiClient.updateMyProfile(changes);
      await config.refreshSession();
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(SnackBar(content: Text(tr('บันทึกโปรไฟล์แล้ว'))));
      nav.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Widget _field(ProfileField f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NxShake(
        child: TextFormField(
          key: ValueKey('pe-${f.key}'),
          controller: _c[f.key],
          enabled: !_saving,
          keyboardType: f.phone ? TextInputType.phone : (f.lines > 1 ? TextInputType.multiline : TextInputType.text),
          textInputAction: f.lines > 1 ? TextInputAction.newline : TextInputAction.next,
          minLines: f.lines,
          maxLines: f.lines > 1 ? f.lines + 3 : 1,
          inputFormatters: [LengthLimitingTextInputFormatter(f.max)],
          decoration: NxFieldStyle.input(
            context,
            label: f.label,
            // Multi-line boxes carry no icon (like the entity forms).
            icon: f.lines > 1 ? null : f.icon,
            hint: f.hint,
            required: f.key == 'first_name_th',
            multiline: f.lines > 1,
          ),
          validator: (v) => trn(profileFieldProblem(f.key, v ?? '', otherFirstName: _c['first_name']!.text)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dirty = !_loading && _error == null && _changes.isNotEmpty;
    final mobile = _str(_original['phone_mobile']);
    final saveBtn = IconButton(
      key: const ValueKey('pe-save-top'),
      tooltip: tr('บันทึก'),
      onPressed: _saving || _loading || _error != null ? null : _save,
      icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.check),
    );

    final List<Widget> children;
    if (_loading) {
      // Section captions over input boxes at the standard field height.
      children = [
        NxSkeletonFields(
          key: const ValueKey('profile-edit-skeleton'),
          sections: [for (final s in profileFieldSections) s.$2.length.clamp(1, 4)],
          padded: false,
        ),
      ];
    } else if (_error != null) {
      children = [
        NxSoftNote(
          icon: NxI.warningCircle,
          color: cs.error,
          text: formatApiError(_error!),
          action: TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
        ),
      ];
    } else {
      children = [
        for (final s in profileFieldSections)
          if (s.$2.any((f) => _has(f.key))) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
              child: Text(tr(s.$1).toUpperCase(), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.8)),
            ),
            if (s.$1 == 'ติดต่อ')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                // Read-only value in the standard box; tap → change-phone flow.
                child: NxOutlinedTapField(
                  key: const ValueKey('pe-mobile'),
                  label: 'มือถือ',
                  isEmpty: false,
                  enabled: !_saving,
                  prefixIcon: const Icon(NxI.deviceMobile),
                  suffixIcon: const NxFieldTextAction('เปลี่ยน'),
                  onTap: _saving
                      ? null
                      : () async {
                          final api = context.read<AppConfig>().apiClient;
                          final changed = await nxPush<bool>(context, PhoneChangeScreen(currentPhone: mobile.isEmpty ? null : mobile));
                          if (changed == true && mounted) {
                            final p = await api.getMyProfile().catchError((_) => _original);
                            if (mounted) setState(() => _original = {..._original, 'phone_mobile': p['phone_mobile']});
                          }
                        },
                  child: Text(
                    mobile.isEmpty ? tr('ยังไม่มีเบอร์มือถือ') : formatPhone(mobile),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mobile.isEmpty ? NxFieldStyle.restingStyle(cs) : theme.textTheme.bodyLarge,
                  ),
                ),
              ),
            for (final f in s.$2)
              if (_has(f.key)) _field(f),
          ],
        if (_choice.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
            child: Text(tr('การแสดงผลบนเว็บ').toUpperCase(), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.8)),
          ),
          for (final e in profileChoiceFields.entries)
            if (_choice.containsKey(e.key))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(tr(e.value.$1), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  KeyedSubtree(
                    key: ValueKey('pe-${e.key}'),
                    child: NxSlidingSegmented<String>(
                      value: _choice[e.key]!,
                      translate: e.key != 'user_language',
                      options: [for (final o in e.value.$2) (o.$1, o.$2, null)],
                      onChanged: (v) => setState(() => _choice[e.key] = v),
                    ),
                  ),
                ]),
              ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('pe-save'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.check, size: 20),
          label: Text(tr(dirty ? 'บันทึกการเปลี่ยนแปลง' : 'บันทึก')),
        ),
        if (dirty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr('แก้ไขแล้ว ${_changes.length} ช่อง · ยังไม่ได้บันทึก'),
              key: const ValueKey('pe-dirty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
      ];
    }

    return NxUnsavedGuard(
      enabled: !_loading && _error == null && !_saving,
      snapshot: () => jsonEncode(_values),
      child: Form(
        key: _form,
        child: ProfileSubPage(title: 'แก้ไขโปรไฟล์', maxWidth: 640, actions: [saveBtn], children: children),
      ),
    );
  }
}
