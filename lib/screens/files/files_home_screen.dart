import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../services/file_open.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_split_view.dart';
import '../../widgets/nx_icons.dart';

class FilesHomeScreen extends StatefulWidget {
  const FilesHomeScreen({super.key});

  @override
  State<FilesHomeScreen> createState() => _FilesHomeScreenState();
}

class _FilesHomeScreenState extends State<FilesHomeScreen> {
  var _revision = 0;
  Map<String, dynamic>? _selected;

  Future<void> _upload({required bool camera}) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    try {
      final bytes = await file.readAsBytes();
      await context.read<AppConfig>().apiClient.uploadFiles([
        MultipartFile.fromBytes(bytes, filename: file.name),
      ]);
      if (mounted) setState(() => _revision++);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  Future<void> _open(Map<String, dynamic> file, {required bool twoPane}) async {
    final launched = await openFileRecord(file);
    if (launched) return;
    if (twoPane) {
      setState(() => _selected = file);
      return;
    }
    if (!mounted) return;
    await nxPush<void>(context, _FilePreview(file: file));
  }

  @override
  Widget build(BuildContext context) {
    final twoPane = NxBreakpoint.of(context).twoPane;
    return Scaffold(
      appBar: NxAppHeader(
        title: 'ไฟล์',
        actions: [
          IconButton(onPressed: () => _upload(camera: true), icon: const Icon(NxI.camera)),
          IconButton(onPressed: () => _upload(camera: false), icon: const Icon(NxI.uploadSimple)),
        ],
      ),
      body: NxCachedFuture<List<Map<String, dynamic>>>(
        revision: _revision,
        load: () => context.read<AppConfig>().apiClient.getFiles(),
        skeleton: const NxSkeletonList(),
        isEmpty: (list) => list.isEmpty,
        empty: const Center(child: Text('ยังไม่มีไฟล์')),
        builder: (context, list) {
          final items = ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final f in list)
                DenseCardTile(
                  title: f['file_name']?.toString() ?? 'ไฟล์',
                  subtitle: f['mime_type']?.toString(),
                  leading: const Icon(NxI.file),
                  onTap: () {
                    _open(f, twoPane: twoPane);
                  },
                ),
            ],
          );
          return NxSplitView(
            list: items,
            detail: _selected == null ? null : _FilePreview(file: _selected!, embedded: true),
          );
        },
      ),
    );
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.file, this.embedded = false});
  final Map<String, dynamic> file;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: NxAppHeader(
        title: file['file_name']?.toString() ?? 'ไฟล์',
        automaticallyImplyLeading: !embedded,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file['mime_type']?.toString() ?? '', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(file['path']?.toString() ?? file['url']?.toString() ?? '', style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => openFileRecord(file),
              child: const Text('เปิดไฟล์'),
            ),
          ],
        ),
      ),
    );
  }
}
