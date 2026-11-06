import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/api_client.dart';
import '../../services/file_open.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_create_fab.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_icons.dart';

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
  final Set<String> _opening = {};

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(NxI.uploadSimple), title: const Text('อัปโหลดไฟล์'), onTap: () => Navigator.pop(ctx, 'file')),
            ListTile(leading: const Icon(NxI.images), title: const Text('รูปจากคลัง'), onTap: () => Navigator.pop(ctx, 'gallery')),
            ListTile(leading: const Icon(NxI.camera), title: const Text('ถ่ายรูป'), onTap: () => Navigator.pop(ctx, 'camera')),
            ListTile(leading: const Icon(NxI.folder), title: const Text('สร้างโฟลเดอร์'), onTap: () => Navigator.pop(ctx, 'folder')),
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
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'ชื่อ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('บันทึก')),
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
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(name, style: Theme.of(ctx).textTheme.titleMedium)),
            if (!folder) ...[
              ListTile(leading: const Icon(NxI.arrowSquareOut), title: const Text('เปิด'), onTap: () => Navigator.pop(ctx, 'open')),
              ListTile(leading: const Icon(NxI.shareNetwork), title: const Text('แชร์'), onTap: () => Navigator.pop(ctx, 'share')),
            ],
            ListTile(leading: const Icon(NxI.pencilSimple), title: const Text('เปลี่ยนชื่อ'), onTap: () => Navigator.pop(ctx, 'rename')),
            ListTile(
              leading: Icon(NxI.trash, color: Theme.of(ctx).colorScheme.error),
              title: Text('ลบ', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
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
              title: Text('ลบ "$name"?'),
              content: Text(folder ? 'ไฟล์และโฟลเดอร์ย่อยข้างในจะถูกลบด้วย' : 'ลบแล้วกู้คืนไม่ได้'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
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
    final folders = needle.isEmpty
        ? _folders
        : _folders.where((f) => (f['name']?.toString() ?? '').toLowerCase().contains(needle)).toList();
    final files = needle.isEmpty
        ? _files
        : _files.where((f) => (f['file_name']?.toString() ?? '').toLowerCase().contains(needle)).toList();

    Widget body;
    if (_loading) {
      body = const NxSkeletonList();
    } else if (_error != null) {
      body = ListView(children: [
        const SizedBox(height: 80),
        Center(child: Text(formatApiError(_error!))),
        Center(child: TextButton(onPressed: _load, child: const Text('ลองใหม่'))),
      ]);
    } else {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'ค้นหาในโฟลเดอร์นี้',
              prefixIcon: const Icon(NxI.magnifyingGlass),
              filled: true,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(avatar: const Icon(NxI.hardDrives, size: 18), label: const Text('ไฟล์ทั้งหมด'), onPressed: () => _goTo(null)),
                for (final b in _breadcrumb) ...[
                  Icon(NxI.caretRight, size: 16, color: cs.onSurfaceVariant),
                  ActionChip(label: Text(b['name']?.toString() ?? ''), onPressed: () => _goTo(b['id']?.toString())),
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
                  Text(needle.isEmpty ? 'โฟลเดอร์นี้ว่าง' : 'ไม่พบไฟล์', style: theme.textTheme.titleMedium),
                  if (needle.isEmpty) const Text('แตะ + เพื่ออัปโหลดหรือสร้างโฟลเดอร์'),
                ],
              ),
            ),
          for (final f in folders)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: cs.primaryContainer, child: Icon(NxI.folder, color: cs.onPrimaryContainer)),
                title: Text(f['name']?.toString() ?? ''),
                trailing: IconButton(icon: const Icon(NxI.dotsThreeVertical), onPressed: () => _itemMenu(f, folder: true)),
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
                title: Text(f['file_name']?.toString() ?? 'ไฟล์', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [formatBytes(f['file_size']), (f['created_at']?.toString() ?? '').split('T').first]
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                ),
                trailing: IconButton(icon: const Icon(NxI.dotsThreeVertical), onPressed: () => _itemMenu(f, folder: false)),
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
      child: Scaffold(
        appBar: NxAppHeader(
          title: _breadcrumb.isEmpty ? 'ไฟล์' : (_breadcrumb.last['name']?.toString() ?? 'ไฟล์'),
          actions: [IconButton(onPressed: _load, icon: const Icon(NxI.arrowCounterClockwise))],
        ),
        floatingActionButton: NxCreateFab(label: 'เพิ่ม', onPressed: _busy ? () {} : _addMenu),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: RefreshIndicator(onRefresh: _load, child: body)),
          ],
        ),
      ),
    );
  }
}
