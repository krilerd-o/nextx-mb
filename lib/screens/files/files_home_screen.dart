import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../services/file_open.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_create_fab.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../widgets/nx_overlay_panel.dart';
import '../../widgets/nx_refresh.dart';

String formatBytes(dynamic raw) {
  final n = num.tryParse(raw?.toString() ?? '');
  if (n == null || n <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = n.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
}

/// Rough file kind for the type filter: image / pdf / doc / sheet / video / other.
String fileKindOf(String? mime, String? name) {
  final m = (mime ?? '').toLowerCase();
  final n = (name ?? '').toLowerCase();
  if (m.startsWith('image/') || RegExp(r'\.(png|jpe?g|gif|webp|heic)$').hasMatch(n)) return 'image';
  if (m.contains('pdf') || n.endsWith('.pdf')) return 'pdf';
  if (m.startsWith('video/') || RegExp(r'\.(mp4|mov|avi|mkv)$').hasMatch(n)) return 'video';
  if (m.contains('sheet') || m.contains('excel') || RegExp(r'\.(xlsx?|csv)$').hasMatch(n)) return 'sheet';
  if (m.contains('word') || m.contains('document') || m.startsWith('text/') || RegExp(r'\.(docx?|txt|pptx?)$').hasMatch(n)) {
    return 'doc';
  }
  return 'other';
}

IconData fileIconFor(String? mime, String? name) {
  final m = (mime ?? '').toLowerCase();
  final ext = (name ?? '').split('.').last.toLowerCase();
  if (m.startsWith('image/')) return NxI.image;
  if (m.contains('pdf') || ext == 'pdf') return NxI.filePdf;
  if (m.startsWith('video/')) return NxI.videoCamera;
  return NxI.file;
}

class FilesHomeScreen extends StatefulWidget {
  const FilesHomeScreen({super.key});

  @override
  State<FilesHomeScreen> createState() => _FilesHomeScreenState();
}

class _FilesHomeScreenState extends State<FilesHomeScreen> {
  String? _folderId;
  List<Map<String, dynamic>> _folders = [];
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _breadcrumb = [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  String _query = '';
  NxListQuery _lq = const NxListQuery();
  final Set<String> _opening = {};

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(text))));
  }

  Future<void> _load() async {
    setState(() {
      _loading = _folders.isEmpty && _files.isEmpty;
      _error = null;
    });
    try {
      final r = await _api.getFolderListing(folderId: _folderId);
      if (!mounted) return;
      setState(() {
        _folders = r.folders;
        _files = r.files;
        _breadcrumb = r.breadcrumb;
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

  void _goTo(String? folderId) {
    setState(() {
      _folderId = folderId;
      _folders = [];
      _files = [];
      _query = '';
    });
    _load();
  }

  Future<void> _upload(List<MultipartFile> files) async {
    if (files.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _api.uploadFiles(files, folderId: _folderId);
      _snack('อัปโหลด ${files.length} ไฟล์แล้ว');
      await _load();
    } catch (e) {
      _snack(formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addMenu() async {
    final choice = await showNxBlurPanel<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(NxI.uploadSimple), title: Text(tr('อัปโหลดไฟล์')), onTap: () => Navigator.pop(ctx, 'file')),
            ListTile(leading: const Icon(NxI.images), title: Text(tr('รูปจากคลัง')), onTap: () => Navigator.pop(ctx, 'gallery')),
            ListTile(leading: const Icon(NxI.camera), title: Text(tr('ถ่ายรูป')), onTap: () => Navigator.pop(ctx, 'camera')),
            ListTile(leading: const Icon(NxI.folder), title: Text(tr('สร้างโฟลเดอร์')), onTap: () => Navigator.pop(ctx, 'folder')),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      switch (choice) {
        case 'file':
          final picked = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
          final files = [
            for (final f in picked?.files ?? const <PlatformFile>[])
              if (f.bytes != null) MultipartFile.fromBytes(f.bytes!, filename: f.name),
          ];
          await _upload(files);
        case 'gallery':
          final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
          final files = [for (final x in picked) MultipartFile.fromBytes(await x.readAsBytes(), filename: x.name)];
          await _upload(files);
        case 'camera':
          final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
          if (x != null) await _upload([MultipartFile.fromBytes(await x.readAsBytes(), filename: x.name)]);
        case 'folder':
          final name = await _askName('สร้างโฟลเดอร์', '');
          if (name == null) return;
          await _api.createFolder(name, parentId: _folderId);
          await _load();
      }
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  Future<String?> _askName(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: tr('ชื่อ'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('บันทึก'))),
        ],
      ),
    );
    ctrl.dispose();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<void> _openFile(Map<String, dynamic> f, {bool share = false}) async {
    final id = f['id']?.toString() ?? '';
    if (id.isEmpty || _opening.contains(id)) return;
    setState(() => _opening.add(id));
    try {
      final bytes = await _api.downloadFile(id);
      final name = f['file_name']?.toString() ?? 'file-$id';
      if (share) {
        await shareFileBytes(bytes, name);
      } else {
        await openFileBytes(bytes, name);
      }
    } catch (e) {
      _snack(formatApiError(e));
    } finally {
      if (mounted) setState(() => _opening.remove(id));
    }
  }

  Future<void> _itemMenu(Map<String, dynamic> item, {required bool folder}) async {
    final name = (folder ? item['name'] : item['file_name'])?.toString() ?? '';
    // Grows out of the ⋯ button (see showNxBlurPanel), not a sheet.
    final action = await showNxBlurPanel<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              title: Text(tr(name), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (!folder) ...[
              ListTile(leading: const Icon(NxI.arrowSquareOut), title: Text(tr('เปิด')), onTap: () => Navigator.pop(ctx, 'open')),
              ListTile(leading: const Icon(NxI.shareNetwork), title: Text(tr('แชร์')), onTap: () => Navigator.pop(ctx, 'share')),
            ],
            ListTile(leading: const Icon(NxI.pencilSimple), title: Text(tr('เปลี่ยนชื่อ')), onTap: () => Navigator.pop(ctx, 'rename')),
            ListTile(
              leading: Icon(NxI.trash, color: Theme.of(ctx).colorScheme.error),
              title: Text(tr('ลบ'), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final id = item['id']?.toString() ?? '';
    try {
      switch (action) {
        case 'open':
          await _openFile(item);
        case 'share':
          await _openFile(item, share: true);
        case 'rename':
          final next = await _askName('เปลี่ยนชื่อ', name);
          if (next == null || next == name) return;
          folder ? await _api.renameFolder(id, next) : await _api.renameFile(id, next);
          await _load();
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr('ลบ "$name"?')),
              content: Text(tr(folder ? 'ไฟล์และโฟลเดอร์ย่อยข้างในจะถูกลบด้วย' : 'ลบแล้วกู้คืนไม่ได้')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ลบ'))),
              ],
            ),
          );
          if (ok != true) return;
          folder ? await _api.deleteFolder(id) : await _api.deleteFile(id);
          _snack('ลบแล้ว');
          await _load();
      }
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final needle = _query.trim().toLowerCase();
    final lq = _lq.copyWith(q: _query);
    int byName(Map a, Map b, String k) => '${a[k] ?? ''}'.toLowerCase().compareTo('${b[k] ?? ''}'.toLowerCase());
    final folders = nxApplyLocalQuery<Map<String, dynamic>>(
      _lq.values('kind').isEmpty || _lq.has('kind', 'folder') ? _folders : const [],
      lq.copyWith(filters: const {}),
      text: (f) => '${f['name'] ?? ''}',
      sorts: {
        'name': (a, b) => byName(a, b, 'name'),
        'new': (a, b) => '${b['created_at'] ?? ''}'.compareTo('${a['created_at'] ?? ''}'),
        'size': (a, b) => byName(a, b, 'name'),
      },
    );
    final files = nxApplyLocalQuery<Map<String, dynamic>>(
      _files,
      lq,
      text: (f) => '${f['file_name'] ?? ''}',
      filters: {
        'kind': (f, v) => v.contains(fileKindOf(f['mime_type']?.toString(), f['file_name']?.toString())),
      },
      sorts: {
        'name': (a, b) => byName(a, b, 'file_name'),
        'new': (a, b) => '${b['created_at'] ?? ''}'.compareTo('${a['created_at'] ?? ''}'),
        'size': (a, b) => (num.tryParse('${b['file_size'] ?? 0}') ?? 0).compareTo(num.tryParse('${a['file_size'] ?? 0}') ?? 0),
      },
    );

    Widget body;
    if (_loading) {
      body = const NxSkeletonList();
    } else if (_error != null) {
      body = ListView(children: [
        const SizedBox(height: 80),
        Center(child: Text(tr(formatApiError(_error!)))),
        Center(child: TextButton(onPressed: _load, child: Text(tr('ลองใหม่')))),
      ]);
    } else {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          NxListToolbar(
            key: ValueKey('files-${_folderId ?? 'root'}'),
            query: lq,
            liveSearch: true,
            padding: EdgeInsets.zero,
            searchHint: 'ค้นหาในโฟลเดอร์นี้',
            quickGroup: 'kind',
            groups: const [
              NxFilterGroup(key: 'kind', label: 'ชนิดไฟล์', options: [
                NxFilterOption('folder', 'โฟลเดอร์'),
                NxFilterOption('image', 'รูปภาพ'),
                NxFilterOption('pdf', 'PDF'),
                NxFilterOption('doc', 'เอกสาร'),
                NxFilterOption('sheet', 'ตาราง'),
                NxFilterOption('video', 'วิดีโอ'),
                NxFilterOption('other', 'อื่นๆ'),
              ]),
            ],
            sorts: const [
              NxSortOption('name', 'ชื่อ ก–ฮ'),
              NxSortOption('new', 'ใหม่ล่าสุด'),
              NxSortOption('size', 'ขนาดใหญ่สุด'),
            ],
            onChanged: (q) => setState(() {
              _query = q.q;
              _lq = q.copyWith(q: '');
            }),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(avatar: const Icon(NxI.hardDrives, size: 18), label: Text(tr('ไฟล์ทั้งหมด')), onPressed: () => _goTo(null)),
                for (final b in _breadcrumb) ...[
                  Icon(NxI.caretRight, size: 16, color: cs.onSurfaceVariant),
                  ActionChip(label: Text(tr(b['name']?.toString() ?? '')), onPressed: () => _goTo(b['id']?.toString())),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (folders.isEmpty && files.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 64),
              child: Column(
                children: [
                  Icon(NxI.folder, size: 56, color: cs.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Text(tr(needle.isEmpty ? 'โฟลเดอร์นี้ว่าง' : 'ไม่พบไฟล์'), style: theme.textTheme.titleMedium),
                  if (needle.isEmpty) Text(tr('แตะ + เพื่ออัปโหลดหรือสร้างโฟลเดอร์')),
                ],
              ),
            ),
          for (final f in folders)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: cs.primaryContainer, child: Icon(NxI.folder, color: cs.onPrimaryContainer)),
                title: Text(tr(f['name']?.toString() ?? '')),
                trailing: Builder(builder: (bc) => IconButton(icon: const Icon(NxI.dotsThreeVertical), onPressed: NxTapTracker.from(bc, () => _itemMenu(f, folder: true)))),
                onTap: () => _goTo(f['id']?.toString()),
                onLongPress: () => _itemMenu(f, folder: true),
              ),
            ),
          for (final f in files)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.surfaceContainerHighest,
                  child: _opening.contains(f['id']?.toString())
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(fileIconFor(f['mime_type']?.toString(), f['file_name']?.toString()), color: cs.onSurfaceVariant),
                ),
                title: Text(tr(f['file_name']?.toString() ?? 'ไฟล์'), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  tr([formatBytes(f['file_size']), (f['created_at']?.toString() ?? '').split('T').first]
                      .where((e) => e.isNotEmpty)
                      .join(' · ')),
                ),
                trailing: Builder(builder: (bc) => IconButton(icon: const Icon(NxI.dotsThreeVertical), onPressed: NxTapTracker.from(bc, () => _itemMenu(f, folder: false)))),
                onTap: () => _openFile(f),
                onLongPress: () => _itemMenu(f, folder: false),
              ),
            ),
        ],
      );
    }

    return PopScope(
      canPop: _folderId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back goes up one folder first.
        final parent = _breadcrumb.length >= 2 ? _breadcrumb[_breadcrumb.length - 2]['id']?.toString() : null;
        _goTo(parent);
      },
      child: NxScrollScaffold(
        header: NxAppHeader(
          title: _breadcrumb.isEmpty ? 'ไฟล์' : (_breadcrumb.last['name']?.toString() ?? 'ไฟล์'),
          actions: [
            if (NxBreakpoint.of(context).twoPane) NxAddButton(tooltip: tr('เพิ่ม'), onPressed: _busy ? () {} : _addMenu),
          ],
        ),
        floatingActionButton: NxCreateFab(label: 'เพิ่ม', onPressed: _busy ? () {} : _addMenu),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: NxRefresh(onRefresh: _load, child: body)),
          ],
        ),
      ),
    );
  }
}
