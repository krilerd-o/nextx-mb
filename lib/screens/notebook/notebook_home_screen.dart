import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/notebook/notebook_models.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../widgets/nx_refresh.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_sliding_segmented.dart';
import '../comm_ai/comm_ai_isaac.dart';
import 'notebook_book_card.dart';
import 'notebook_share_sheet.dart';
import 'notebook_widgets.dart';

/// `/notebook` — the user's ISAAC notebooks (NotebookLM-style library): book cards in each
/// notebook's colour / icon (pinned first), search from the header icon like the other lists.
class NotebookHomeScreen extends StatefulWidget {
  const NotebookHomeScreen({super.key, this.controller});

  /// For tests.
  final NotebookLibraryController? controller;

  @override
  State<NotebookHomeScreen> createState() => _NotebookHomeScreenState();
}

class _NotebookHomeScreenState extends State<NotebookHomeScreen> {
  late final NotebookLibraryController _c = widget.controller ??
      NotebookLibraryController(
        context.read<AppConfig>().apiClient,
        meId: context.read<AppConfig>().session.userId,
        prefsScope: context.read<AppConfig>().businessScope,
      );
  NxListQuery _query = const NxListQuery();

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.load());
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _open(Notebook n) async {
    HapticFeedback.selectionClick();
    await context.push('/notebook/${n.id}');
    if (mounted) _c.load();
  }

  Future<void> _create() async {
    final out = await showNotebookEditSheet(context);
    if (out == null || !mounted) return;
    try {
      final nb = await _c.create(title: out.title, description: out.description, visibility: out.visibility, appearance: out.appearance);
      if (mounted) await _open(nb);
    } catch (e) {
      _snack(notebookError(e).text);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(text))));
  }

  /// Header ⋮: privacy — delete every recording I made in Notebooks (the privacy policy promises this).
  Future<void> _moreMenu() async {
    final pick = await showAppBottomSheet<String>(
      context: context,
      title: tr('สมุดโน้ต'),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          key: const ValueKey('notebook-delete-my-recordings'),
          leading: Icon(NxI.trash, color: Theme.of(context).colorScheme.error),
          title: Text(tr('ลบบันทึกเสียงทั้งหมดของฉัน')),
          subtitle: Text(tr('เสียง บทถอดข้อความ และสรุปการประชุมที่ฉันบันทึกในทุกเล่ม')),
          onTap: () => Navigator.pop(context, 'delete-recordings'),
        ),
      ]),
    );
    if (pick != 'delete-recordings' || !mounted) return;
    final ok = await showDeleteConfirm(
      context,
      name: tr('บันทึกเสียงทั้งหมดของฉัน'),
      loses: const ['ไฟล์เสียงที่ฉันบันทึกในสมุดโน้ตทุกเล่ม', 'บทถอดข้อความและแหล่งข้อมูลบันทึกเสียง', 'โน้ตสรุปการประชุมจากบันทึกเหล่านั้น'],
      note: 'ลบแล้วกู้คืนไม่ได้ — บันทึกของคนอื่นในเล่มเดียวกันไม่ถูกลบ',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final r = await context.read<AppConfig>().apiClient.deleteMyNotebookRecordings();
      final n = (r['recordings'] as num?)?.toInt() ?? 0;
      messenger?.showSnackBar(SnackBar(content: Text(n == 0 ? tr('ไม่มีบันทึกเสียงของคุณให้ลบ') : tr('ลบบันทึกเสียงแล้ว $n รายการ'))));
      await _c.load();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(tr('ลบไม่สำเร็จ ลองใหม่อีกครั้ง'))));
    }
  }

  Future<void> _menu(Notebook n) async {
    HapticFeedback.mediumImpact();
    final me = context.read<AppConfig>().session.userId;
    final owner = n.userId == null || n.userId == me;
    final action = await showAppBottomSheet<String>(
      context: context,
      title: null,
      child: Builder(builder: (ctx) {
        final theme = Theme.of(ctx);
        Widget item(String id, IconData icon, String label, {Color? color}) => ListTile(
              key: ValueKey('notebook-menu-$id'),
              leading: Icon(icon, color: color),
              title: Text(tr(label), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, id),
            );
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Row(children: [
              NotebookMiniBook(look: n.look, width: 40, height: 50),
              const SizedBox(width: 12),
              Expanded(child: Text(n.title.isEmpty ? tr('สมุดไม่มีชื่อ') : n.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            ]),
          ),
          item('open', LucideIcons300.bookOpenText, 'เปิดสมุด'),
          if (n.canWrite) item('rename', NxI.pencilSimple, 'แก้ไขชื่อและรายละเอียด'),
          if (n.canWrite) item('appearance', LucideIcons300.palette, 'ปรับแต่งหน้าปก'),
          if (n.canWrite) item('pin', n.pinned ? LucideIcons300.pinOff : LucideIcons300.pin, n.pinned ? 'เลิกปักหมุด' : 'ปักหมุดไว้บนสุด'),
          if (n.canWrite) item('share', NxI.shareNetwork, 'แชร์'),
          if (owner) item('delete', NxI.trash, 'ลบสมุด', color: kNxDangerRed),
        ]);
      }),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'open':
        await _open(n);
      case 'rename':
        final out = await showNotebookEditSheet(context, initial: n);
        if (out == null) return;
        try {
          await _c.update(
            n,
            title: out.title,
            description: out.description,
            visibility: out.visibility,
            appearance: out.appearance == n.look ? null : out.appearance,
          );
        } catch (e) {
          _snack(notebookError(e).text);
        }
      case 'appearance':
        final look = await showNotebookAppearanceSheet(context, notebook: n, scopeLabel: _scopeOf(n).$2, scopeIcon: _scopeOf(n).$1);
        if (look == null || look == n.look) return;
        try {
          await _c.setAppearance(n, look);
        } catch (e) {
          _snack(notebookError(e).text);
        }
      case 'pin':
        try {
          await _c.togglePin(n);
          _snack(n.pinned ? 'เลิกปักหมุดแล้ว' : 'ปักหมุดไว้บนสุดแล้ว');
        } catch (e) {
          _snack(notebookError(e).text);
        }
      case 'share':
        await showNotebookShareSheet(context, notebook: n);
      case 'delete':
        final ok = await showDeleteConfirm(
          context,
          name: n.title.isEmpty ? tr('สมุดไม่มีชื่อ') : n.title,
          loses: const ['แหล่งข้อมูลทั้งหมดในสมุดนี้', 'โน้ตและผลงานในสตูดิโอ', 'ลิงก์ที่แชร์ไว้'],
          note: 'ลบแล้วกู้คืนไม่ได้',
        );
        if (!ok) return;
        try {
          await _c.delete(n);
          _snack('ลบสมุดแล้ว');
        } catch (e) {
          _snack(notebookError(e).text);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'สมุดโน้ต',
        subtitle: 'ไอแซคเอไอ',
        actions: [
          IconButton(
            key: const ValueKey('notebook-layout-toggle'),
            tooltip: tr(_c.grid ? 'แสดงเป็นรายการ' : 'แสดงเป็นกริด'),
            icon: Icon(_c.grid ? LucideIcons300.list : LucideIcons300.layoutGrid),
            onPressed: () {
              HapticFeedback.selectionClick();
              _c.toggleGrid();
            },
          ),
          IconButton(
            key: const ValueKey('notebook-home-more'),
            tooltip: tr('เพิ่มเติม'),
            icon: const Icon(NxI.dotsThreeVertical),
            onPressed: _moreMenu,
          ),
        ],
      ),
      floatingActionButton: _c.disabled
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [BoxShadow(color: kIsaacIndigo.withValues(alpha: 0.22), blurRadius: 16, spreadRadius: -4, offset: const Offset(0, 6))],
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)])),
                    child: InkWell(
                      key: const ValueKey('notebook-create'),
                      onTap: _create,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 22, 14),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(NxI.plus, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(tr('สมุดใหม่'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      body: NotebookBackdrop(
        child: Column(children: [
          if (!_c.disabled)
            NxListToolbar(
              key: const ValueKey('notebook-toolbar'),
              query: _query,
              liveSearch: true,
              allowSavedViews: false,
              searchHint: 'ค้นหาสมุดโน้ต',
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              leading: _scopeChips(context),
              onChanged: (q) {
                setState(() => _query = q);
                _c.setQuery(q.q);
              },
            ),
          Expanded(child: _body(context)),
        ]),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_c.disabled) return NotebookDisabledState(message: _c.error);
    if (!_c.loaded && _c.loading) {
      return const SingleChildScrollView(key: ValueKey('notebook-skeleton'), child: NxSkeletonBoard(columns: 2));
    }
    if (_c.error != null && _c.items.isEmpty) {
      return NotebookState(
        mood: 'error',
        title: 'เปิดสมุดโน้ตไม่ได้',
        message: _c.error,
        action: FilledButton.tonal(onPressed: _c.load, child: Text(tr('ลองอีกครั้ง'))),
      );
    }
    final bp = NxBreakpoint.of(context);
    final list = _c.visible;
    final pad = EdgeInsets.fromLTRB(16, 6, 16, 110 + MediaQuery.paddingOf(context).bottom);
    return NxRefresh(
      onRefresh: _c.load,
      child: CustomScrollView(
        key: const ValueKey('notebook-library'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_c.items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: NotebookState(
                key: const ValueKey('notebook-empty'),
                mood: 'reading',
                title: 'ยังไม่มีสมุดโน้ต',
                message: 'สร้างสมุด เพิ่มไฟล์ ลิงก์ หรือข้อความ แล้วถามไอแซคจากแหล่งข้อมูลของคุณ',
                action: FilledButton.icon(onPressed: _create, icon: const Icon(NxI.plus, size: 18), label: Text(tr('สร้างสมุดแรก'))),
              ),
            )
          else if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: NotebookState(mood: 'searching', title: 'ไม่พบสมุดที่ตรงกัน', message: _c.query.isEmpty ? 'ลองเลือกตัวกรองอื่น' : tr('ไม่พบรายการที่ตรงกับ "${_c.query}"')),
            )
          else if (_c.grid)
            SliverPadding(
              padding: pad,
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: bp.isCompact ? 210 : 230,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 192,
                ),
                delegate: SliverChildBuilderDelegate((context, i) => _gridCard(context, list[i]), childCount: list.length),
              ),
            )
          else
            SliverPadding(
              padding: pad,
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _listTile(context, list[i]),
              ),
            ),
        ],
      ),
    );
  }

  /// ทั้งหมด / ของฉัน / แชร์กับฉัน / ทั้งธุรกิจ — compact chips under the header (with counts).
  List<Widget> _scopeChips(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const scopes = [
      (NotebookScope.all, 'ทั้งหมด'),
      (NotebookScope.mine, 'ของฉัน'),
      (NotebookScope.shared, 'แชร์กับฉัน'),
      (NotebookScope.business, 'ทั้งธุรกิจ'),
    ];
    return [
      for (final (s, label) in scopes)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(
            key: ValueKey('notebook-scope-${s.name}'),
            label: Text('${tr(label)}${_c.loaded ? ' ${_c.countFor(s)}' : ''}'),
            selected: _c.scope == s,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle: TextStyle(color: _c.scope == s ? cs.onPrimary : cs.onSurface, fontWeight: FontWeight.w600, fontSize: 13),
            selectedColor: cs.primary,
            side: BorderSide(color: _c.scope == s ? cs.primary : cs.outlineVariant.withValues(alpha: 0.7)),
            onSelected: (_) {
              HapticFeedback.selectionClick();
              _c.setScope(s);
            },
          ),
        ),
    ];
  }

  (IconData, String) _scopeOf(Notebook n) => switch (notebookScopeOf(n, context.read<AppConfig>().session.userId)) {
        NotebookScope.business => (LucideIcons300.building2, 'ทั้งธุรกิจ'),
        NotebookScope.shared => (LucideIcons300.users, 'แชร์กับฉัน'),
        _ => (n.isBusiness ? LucideIcons300.building2 : NxI.lock, n.isBusiness ? 'ทั้งธุรกิจ' : 'ส่วนตัว'),
      };

  NotebookCardInfo _info(Notebook n) {
    final (icon, label) = _scopeOf(n);
    return NotebookCardInfo.of(n, scopeLabel: label, scopeIcon: icon);
  }

  Widget _gridCard(BuildContext context, Notebook n) => NotebookBookCard(
        key: ValueKey('notebook-card-${n.id}'),
        info: _info(n),
        onTap: () => _open(n),
        onLongPress: () => _menu(n),
      );

  Widget _listTile(BuildContext context, Notebook n) => NotebookListCard(
        key: ValueKey('notebook-card-${n.id}'),
        info: _info(n),
        onTap: () => _open(n),
        onLongPress: () => _menu(n),
        trailing: IconButton(
          key: ValueKey('notebook-more-${n.id}'),
          tooltip: tr('ตัวเลือก'),
          icon: const Icon(NxI.dotsThreeVertical),
          onPressed: () => _menu(n),
        ),
      );
}

/// What the create / edit sheet returns.
typedef NotebookEditResult = ({String title, String description, String visibility, NotebookAppearance appearance});

/// Title / description / visibility + cover (colour, icon, style, pin) for a new or edited
/// notebook, with a live preview of the card at the top.
Future<NotebookEditResult?> showNotebookEditSheet(BuildContext context, {Notebook? initial}) {
  return showAppBottomSheet<NotebookEditResult>(
    context: context,
    title: initial == null ? 'สร้างสมุดโน้ต' : 'แก้ไขสมุดโน้ต',
    child: _NotebookEditForm(initial: initial),
  );
}

/// "ปรับแต่งหน้าปก": colour / icon / cover style / pin only.
Future<NotebookAppearance?> showNotebookAppearanceSheet(BuildContext context, {required Notebook notebook, String scopeLabel = 'ส่วนตัว', IconData scopeIcon = NxI.lock}) {
  return showAppBottomSheet<NotebookAppearance>(
    context: context,
    title: 'ปรับแต่งหน้าปก',
    child: _AppearanceForm(notebook: notebook, scopeLabel: scopeLabel, scopeIcon: scopeIcon),
  );
}

class _AppearanceForm extends StatefulWidget {
  const _AppearanceForm({required this.notebook, required this.scopeLabel, required this.scopeIcon});
  final Notebook notebook;
  final String scopeLabel;
  final IconData scopeIcon;

  @override
  State<_AppearanceForm> createState() => _AppearanceFormState();
}

class _AppearanceFormState extends State<_AppearanceForm> {
  late NotebookAppearance _look = widget.notebook.look;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NotebookCardPreview(info: NotebookCardInfo.of(widget.notebook, scopeLabel: widget.scopeLabel, scopeIcon: widget.scopeIcon, look: _look)),
      const SizedBox(height: 18),
      NotebookAppearancePicker(value: _look, onChanged: (v) => setState(() => _look = v)),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('notebook-appearance-save'),
        onPressed: () => Navigator.pop(context, _look),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        child: Text(tr('บันทึก')),
      ),
    ]);
  }
}

class _NotebookEditForm extends StatefulWidget {
  const _NotebookEditForm({this.initial});
  final Notebook? initial;

  @override
  State<_NotebookEditForm> createState() => _NotebookEditFormState();
}

class _NotebookEditFormState extends State<_NotebookEditForm> {
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _desc = TextEditingController(text: widget.initial?.description ?? '');
  late String _visibility = widget.initial?.visibility ?? 'private';

  /// Null on a new notebook until the user picks something: the look follows the title.
  late NotebookAppearance? _picked = widget.initial?.look;

  NotebookAppearance get _look => _picked ?? NotebookAppearance.forTitle(_title.text.trim().isEmpty ? tr('สมุดโน้ตใหม่') : _title.text);

  @override
  void initState() {
    super.initState();
    _title.addListener(_onTitle);
  }

  void _onTitle() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _title.removeListener(_onTitle);
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _title.text.trim();
    Navigator.pop<NotebookEditResult>(context, (
      title: t.isEmpty ? tr('สมุดโน้ตใหม่') : t,
      description: _desc.text.trim(),
      visibility: _visibility,
      appearance: _picked ?? NotebookAppearance.forTitle(t.isEmpty ? tr('สมุดโน้ตใหม่') : t),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final business = _visibility == 'business';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NotebookCardPreview(
        info: NotebookCardInfo(
          title: _title.text.trim().isEmpty ? tr('ชื่อสมุด') : _title.text.trim(),
          look: _look,
          sources: widget.initial?.sourcesTotal ?? 0,
          when: widget.initial == null ? 'เมื่อสักครู่' : notebookRelativeTime(widget.initial!.updatedAt),
          scopeLabel: business ? 'ทั้งธุรกิจ' : 'ส่วนตัว',
          scopeIcon: business ? LucideIcons300.building2 : NxI.lock,
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('notebook-title-field'),
        controller: _title,
        autofocus: widget.initial == null,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(labelText: tr('ชื่อสมุด'), hintText: tr('เช่น ข้อมูลสินค้า 2569')),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('notebook-desc-field'),
        controller: _desc,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(labelText: tr('รายละเอียด (ไม่บังคับ)')),
      ),
      const SizedBox(height: 16),
      Text(tr('ใครเห็นสมุดนี้'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      NxSlidingSegmented<String>(
        value: _visibility,
        options: const [('private', 'เฉพาะฉัน', NxI.lock), ('business', 'ทั้งธุรกิจ', LucideIcons300.building2)],
        onChanged: (v) => setState(() => _visibility = v),
      ),
      const SizedBox(height: 18),
      NotebookAppearancePicker(value: _look, onChanged: (v) => setState(() => _picked = v)),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('notebook-edit-save'),
        onPressed: _submit,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        child: Text(tr(widget.initial == null ? 'สร้างสมุด' : 'บันทึก')),
      ),
    ]);
  }
}
