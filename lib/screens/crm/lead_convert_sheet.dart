import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/fields/nx_entity_picker_sheet.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../deep_link_loaders.dart';

/// "แปลงเป็นลูกค้า" for a Lead, same rules and Config as the web
/// (`LeadConvertDrawer`): Account / Contact per convert settings (always /
/// optional), deal, copy history, link duplicates. Returns the API result
/// (`account_id`, `contact_id`, `deal_id`) when converted.
Future<Map<String, dynamic>?> showLeadConvertSheet(BuildContext context, {required String leadId}) async {
  Map<String, dynamic>? result;
  await showNxSnapSheet<void>(
    context: context,
    title: tr('แปลงเป็นลูกค้า'),
    snaps: const [0.92],
    builder: (ctx, controller) => LeadConvertBody(
      leadId: leadId,
      controller: controller,
      onConverted: (r) => result = r,
    ),
  );
  return result;
}

class LeadConvertBody extends StatefulWidget {
  const LeadConvertBody({super.key, required this.leadId, this.controller, this.onConverted});

  final String leadId;
  final ScrollController? controller;
  final ValueChanged<Map<String, dynamic>>? onConverted;

  @override
  State<LeadConvertBody> createState() => _LeadConvertBodyState();
}

class _LeadConvertBodyState extends State<LeadConvertBody> {
  Map<String, dynamic>? _p;
  Object? _error;
  List<Map<String, dynamic>> _users = const [];
  bool _busy = false;
  Map<String, dynamic>? _result;

  bool _createContact = true;
  bool _createAccount = false;
  bool _createDeal = true;
  bool _copyHistory = true;
  final _accountName = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  String? _accountOwner;
  String? _contactOwner;
  NxPickOption? _linkAccount;
  NxPickOption? _linkContact;

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _accountName.dispose();
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        _api.previewLeadConvert(widget.leadId),
        _api.getUsersCached().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      final p = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      final s = _settings(p);
      final d = (p['form_defaults'] as Map?) ?? const {};
      setState(() {
        _p = p;
        _users = results[1] as List<Map<String, dynamic>>;
        _createContact = p['can_convert_contact'] == true && (s.contactAlways || s.contactMode == 'optional');
        _createAccount = p['can_convert_account'] == true && s.accountAlways;
        _createDeal = true;
        _accountName.text = '${d['account_name'] ?? ''}';
        _first.text = '${d['contact_firstname'] ?? ''}';
        _last.text = '${d['contact_lastname'] ?? ''}';
        _accountOwner = d['account_owner_id']?.toString();
        _contactOwner = d['contact_owner_id']?.toString();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  static ({bool contactEnabled, String contactMode, bool accountEnabled, String accountMode, bool contactAlways, bool accountAlways}) _settings(
    Map<String, dynamic>? p,
  ) {
    final s = (p?['settings'] as Map?) ?? const {};
    final ce = s['contact_enabled'] == true, ae = s['account_enabled'] == true;
    final cm = '${s['contact_mode'] ?? ''}', am = '${s['account_mode'] ?? ''}';
    return (
      contactEnabled: ce,
      contactMode: cm,
      accountEnabled: ae,
      accountMode: am,
      contactAlways: ce && cm == 'always',
      accountAlways: ae && am == 'always',
    );
  }

  bool get _showAccount => _settings(_p).accountEnabled && _p?['can_convert_account'] == true;
  bool get _showContact => _settings(_p).contactEnabled && _p?['can_convert_contact'] == true;

  bool get _wantAccount {
    final s = _settings(_p);
    if (!_showAccount) return false;
    return s.accountMode == 'always' || _createAccount || _linkAccount != null;
  }

  bool get _wantContact {
    final s = _settings(_p);
    if (!_showContact) return false;
    return s.contactMode == 'always' || _createContact || _linkContact != null;
  }

  /// Same as the web's `canSubmit`.
  bool get _canSubmit {
    if (_p == null || _p!['already_converted'] == true) return false;
    if (!_wantAccount && !_wantContact) return false;
    if (_wantAccount && _linkAccount == null) {
      if (_accountName.text.trim().isEmpty || (_accountOwner ?? '').isEmpty) return false;
    }
    if (_wantContact && _linkContact == null && (_contactOwner ?? '').isEmpty) return false;
    return true;
  }

  Map<String, dynamic> get body {
    final s = _settings(_p);
    final wantContact = s.contactEnabled && (s.contactMode == 'always' || _createContact || _linkContact != null);
    final wantAccount = s.accountEnabled && (s.accountMode == 'always' || _createAccount || _linkAccount != null);
    return {
      'create_contact': wantContact,
      'create_account': wantAccount,
      'create_deal': _createDeal,
      'account_name': _accountName.text.trim(),
      'contact_firstname': _first.text.trim(),
      'contact_lastname': _last.text.trim(),
      if ((_accountOwner ?? '').isNotEmpty) 'account_owner_id': int.tryParse(_accountOwner!) ?? _accountOwner,
      if ((_contactOwner ?? '').isNotEmpty) 'contact_owner_id': int.tryParse(_contactOwner!) ?? _contactOwner,
      if (_accountName.text.trim().isNotEmpty) 'deal_name': _accountName.text.trim(),
      if (_linkContact != null) 'existing_contact_id': int.tryParse(_linkContact!.value) ?? _linkContact!.value,
      if (_linkAccount != null) 'existing_account_id': int.tryParse(_linkAccount!.value) ?? _linkAccount!.value,
      'copy_history': _copyHistory,
    };
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final r = await _api.convertLead(widget.leadId, body);
      HapticFeedback.heavyImpact();
      widget.onConverted?.call(r);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('แปลงเป็นลูกค้าไม่สำเร็จ: ${formatApiError(e)}'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<NxPickOption?> _pickEntity(String module, String title) => showNxEntityPickerSheet(
        context: context,
        title: tr(title),
        search: (q) async {
          final page = await _api.getEntityList(module, limit: 20, q: q.trim().isEmpty ? null : q.trim());
          return [
            for (final r in page.items)
              NxPickOption(value: '${r['id']}', label: entityTitle(r, module: module), subtitle: '${r['${module}_no'] ?? ''}'),
          ];
        },
      );

  Future<void> _pickOwner(bool account) async {
    final picked = await showNxEntityPickerSheet(
      context: context,
      title: tr('เจ้าของ'),
      users: true,
      search: (q) async => [
        for (final u in _users)
          if (q.trim().isEmpty || NxPickOption.fromMap(u).label.toLowerCase().contains(q.trim().toLowerCase())) NxPickOption.fromMap(u),
      ],
    );
    if (picked == null) return;
    setState(() => account ? _accountOwner = picked.value : _contactOwner = picked.value);
  }

  String _userName(String? id) {
    if (id == null || id.isEmpty) return tr('เลือกเจ้าของ');
    for (final u in _users) {
      final o = NxPickOption.fromMap(u);
      if (o.value == id) return o.label;
    }
    if (id == '${_p?['smownerid']}' && _p?['owner_label'] != null) return '${_p!['owner_label']}';
    return '#$id';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pad = EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 20);
    if (_error != null && _p == null) {
      return ListView(controller: widget.controller, padding: pad, children: [
        const SizedBox(height: 24),
        Icon(NxI.warning, size: 40, color: cs.error),
        const SizedBox(height: 8),
        Text(tr(formatApiError(_error!)), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(child: OutlinedButton(onPressed: _load, child: Text(tr('ลองใหม่')))),
      ]);
    }
    if (_p == null) {
      return ListView(controller: widget.controller, padding: pad, children: const [NxSkeletonList(rows: 4)]);
    }
    if (_result != null) return _success(theme, pad);
    final p = _p!;
    final s = _settings(p);
    final dupA = [for (final r in (p['duplicates']?['accounts'] as List? ?? const [])) if (r is Map) r];
    final dupC = [for (final r in (p['duplicates']?['contacts'] as List? ?? const [])) if (r is Map) r];
    return Stack(
      children: [
        ListView(
          controller: widget.controller,
          padding: pad,
          children: [
            // Lead name + status.
            Center(
              child: Text(
                '${p['lead_name'] ?? '#${widget.leadId}'}',
                key: const ValueKey('convert-lead-name'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if ('${p['lead_status'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                    child: Text(tr('${p['lead_status']}'), style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            if (p['already_converted'] == true)
              _notice(
                theme,
                key: const ValueKey('convert-already'),
                icon: NxI.info,
                text: 'รายการนี้ถูกแปลงเป็นลูกค้าแล้ว ไม่สามารถแปลงซ้ำได้',
              )
            else ...[
              if (dupA.isNotEmpty || dupC.isNotEmpty)
                _notice(
                  theme,
                  key: const ValueKey('convert-duplicates'),
                  icon: NxI.warning,
                  text: 'พบรายการที่อาจซ้ำ — แปลงต่อได้ หรือแตะเพื่อใช้ของเดิม',
                  chips: [
                    for (final r in dupA)
                      ActionChip(
                        avatar: const Icon(NxI.buildings, size: 16),
                        label: Text('${r['name'] ?? '#${r['id']}'}'),
                        onPressed: () => setState(() => _linkAccount = NxPickOption(value: '${r['id']}', label: '${r['name'] ?? '#${r['id']}'}')),
                      ),
                    for (final r in dupC)
                      ActionChip(
                        avatar: const Icon(NxI.user, size: 16),
                        label: Text('${r['name'] ?? '#${r['id']}'}'),
                        onPressed: () => setState(() => _linkContact = NxPickOption(value: '${r['id']}', label: '${r['name'] ?? '#${r['id']}'}')),
                      ),
                  ],
                ),
              if (_showAccount)
                _section(
                  theme,
                  key: const ValueKey('convert-account'),
                  icon: NxI.buildings,
                  color: const Color(0xFF8B5CF6),
                  title: 'บัญชีลูกค้า (Account)',
                  active: _wantAccount,
                  always: s.accountAlways,
                  toggle: s.accountMode == 'optional' ? _createAccount : null,
                  onToggle: (v) => setState(() => _createAccount = v),
                  toggleLabel: 'สร้าง Account ใหม่',
                  link: _linkAccount,
                  onLink: () async {
                    final o = await _pickEntity('account', 'เลือกบัญชีลูกค้าที่มีอยู่');
                    if (o != null) setState(() => _linkAccount = o);
                  },
                  onUnlink: () => setState(() => _linkAccount = null),
                  linkLabel: 'หรือเลือกบัญชีที่มีอยู่',
                  fields: [
                    TextField(
                      key: const ValueKey('convert-account-name'),
                      controller: _accountName,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: tr('ชื่อบริษัท'), prefixIcon: const Icon(NxI.buildings)),
                    ),
                    _ownerTile(theme, _accountOwner, () => _pickOwner(true)),
                  ],
                ),
              if (_showContact)
                _section(
                  theme,
                  key: const ValueKey('convert-contact'),
                  icon: NxI.user,
                  color: const Color(0xFF0EA5E9),
                  title: 'ผู้ติดต่อ (Contact)',
                  active: _wantContact,
                  always: s.contactAlways,
                  toggle: s.contactMode == 'optional' ? _createContact : null,
                  onToggle: (v) => setState(() => _createContact = v),
                  toggleLabel: 'สร้าง Contact ใหม่',
                  link: _linkContact,
                  onLink: () async {
                    final o = await _pickEntity('contact', 'เลือกผู้ติดต่อที่มีอยู่');
                    if (o != null) setState(() => _linkContact = o);
                  },
                  onUnlink: () => setState(() => _linkContact = null),
                  linkLabel: 'หรือเลือกผู้ติดต่อที่มีอยู่',
                  fields: [
                    Row(
                      children: [
                        Expanded(child: TextField(controller: _first, decoration: InputDecoration(labelText: tr('ชื่อ')))),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: _last, decoration: InputDecoration(labelText: tr('นามสกุล')))),
                      ],
                    ),
                    _ownerTile(theme, _contactOwner, () => _pickOwner(false)),
                  ],
                ),
              if (!_showAccount && !_showContact)
                _notice(theme, icon: NxI.info, text: 'การตั้งค่าแปลงเป็นลูกค้าปิดอยู่ — ติดต่อผู้ดูแลระบบ'),
              _switchCard(
                theme,
                key: const ValueKey('convert-deal'),
                icon: NxI.handshake,
                color: const Color(0xFFF59E0B),
                title: 'สร้างดีล',
                hint: 'เปิดดีลสถานะ Qualification ผูกกับ Lead และลูกค้าที่แปลง',
                value: _createDeal,
                onChanged: (v) => setState(() => _createDeal = v),
              ),
              _switchCard(
                theme,
                key: const ValueKey('convert-history'),
                icon: NxI.clockCounterClockwise,
                color: const Color(0xFF14B8A6),
                title: 'คัดลอกประวัติไป Contact / Deal',
                hint: 'กิจกรรม คอมเมนต์ แท็ก และบันทึกโทร — ไม่ลบฝั่ง Lead',
                value: _copyHistory,
                onChanged: (v) => setState(() => _copyHistory = v),
              ),
              // What happens after.
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('หลังจากแปลงแล้ว'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    for (final t in const [
                      'สถานะจะเป็น "แปลงเป็นลูกค้าแล้ว" (Converted) และแปลงซ้ำไม่ได้',
                      'รายการนี้จะแก้ไขหรือลบไม่ได้ (อ่านอย่างเดียว)',
                      'ยังสามารถทำซ้ำเพื่อสร้างรายการใหม่ได้',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(padding: const EdgeInsets.only(top: 3), child: Icon(NxI.check, size: 14, color: cs.onSurfaceVariant)),
                            const SizedBox(width: 6),
                            Expanded(child: Text(tr(t), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  key: const ValueKey('convert-submit'),
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(NxI.userCheck),
                  label: Text(tr(_busy ? 'กำลังแปลงเป็นลูกค้า…' : 'แปลงเป็นลูกค้า')),
                  style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  onPressed: _busy || !_canSubmit ? null : _submit,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _success(ThemeData theme, EdgeInsets pad) {
    final r = _result!;
    final cs = theme.colorScheme;
    Widget link(String module, String label, IconData icon, Color color) {
      final id = '${r['${module}_id'] ?? ''}';
      if (id.isEmpty || id == 'null') return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            key: ValueKey('convert-open-$module'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.18), child: Icon(icon, color: color)),
            title: Text(tr(label), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('#$id'),
            trailing: const Icon(NxI.caretRight),
            onTap: () => nxPush<void>(context, EntityByIdLoader(module: module, id: id), root: true),
          ),
        ),
      );
    }

    return ListView(
      controller: widget.controller,
      padding: pad,
      children: [
        const SizedBox(height: 12),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
              child: const Icon(NxI.check, size: 44, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          tr('แปลงเป็นลูกค้าสำเร็จ'),
          key: const ValueKey('convert-success'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(tr('${_p?['lead_name'] ?? ''}'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 20),
        link('account', 'เปิดบัญชีลูกค้า', NxI.buildings, const Color(0xFF8B5CF6)),
        link('contact', 'เปิดผู้ติดต่อ', NxI.user, const Color(0xFF0EA5E9)),
        link('deal', 'เปิดดีล', NxI.handshake, const Color(0xFFF59E0B)),
        const SizedBox(height: 6),
        OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(tr('ปิด'))),
      ],
    );
  }

  Widget _notice(ThemeData theme, {Key? key, required IconData icon, required String text, List<Widget> chips = const []}) {
    const amber = Color(0xFFF59E0B);
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: amber.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: amber),
              const SizedBox(width: 8),
              Expanded(child: Text(tr(text), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
        ],
      ),
    );
  }

  Widget _ownerTile(ThemeData theme, String? id, VoidCallback onTap) {
    final cs = theme.colorScheme;
    final missing = (id ?? '').isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: tr('เจ้าของ'),
            prefixIcon: const Icon(NxI.userCircle),
            suffixIcon: const Icon(NxI.caretDown),
            errorText: missing ? tr('กรุณาเลือกเจ้าของ') : null,
          ),
          child: Text(_userName(id), style: theme.textTheme.bodyLarge?.copyWith(color: missing ? cs.onSurfaceVariant : null)),
        ),
      ),
    );
  }

  Widget _section(
    ThemeData theme, {
    Key? key,
    required IconData icon,
    required Color color,
    required String title,
    required bool active,
    required bool always,
    required bool? toggle,
    required ValueChanged<bool> onToggle,
    required String toggleLabel,
    required NxPickOption? link,
    required VoidCallback onLink,
    required VoidCallback onUnlink,
    required String linkLabel,
    required List<Widget> fields,
  }) {
    final cs = theme.colorScheme;
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? color.withValues(alpha: 0.6) : cs.outlineVariant.withValues(alpha: 0.6), width: active ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 18, backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, size: 20, color: color)),
              const SizedBox(width: 10),
              Expanded(child: Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              if (always)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                  child: Text(tr('สร้างเสมอ'), style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          if (toggle != null && link == null)
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: toggle,
                onChanged: onToggle,
                title: Text(tr(toggleLabel)),
              ),
            ),
          if (link != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: InputChip(
                avatar: Icon(NxI.link, size: 16, color: color),
                label: Text(tr('ใช้ของเดิม: ${link.label}')),
                onDeleted: onUnlink,
              ),
            )
          else ...[
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: active || always
                  ? Padding(padding: const EdgeInsets.only(top: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: fields))
                  : const SizedBox(width: double.infinity),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: onLink, icon: const Icon(NxI.magnifyingGlass, size: 18), label: Text(tr(linkLabel))),
            ),
          ],
        ],
      ),
    );
  }

  Widget _switchCard(
    ThemeData theme, {
    Key? key,
    required IconData icon,
    required Color color,
    required String title,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile.adaptive(
        key: key,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        secondary: CircleAvatar(radius: 18, backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, size: 20, color: color)),
        title: Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(tr(hint)),
        value: value,
        onChanged: onChanged,
      ),
      ),
    );
  }
}
