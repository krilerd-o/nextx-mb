import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/nx_page_route.dart';
import '../../core/entity_display.dart';
import '../../services/api_client.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/fields/field_ui_type.dart';
import '../../widgets/fields/nx_form_field.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_split_view.dart';
import '../../core/nx_breakpoint.dart';
import '../../widgets/nx_icons.dart';

class CallLogScreen extends StatefulWidget {
  const CallLogScreen({super.key});

  @override
  State<CallLogScreen> createState() => _CallLogScreenState();
}

class _CallLogScreenState extends State<CallLogScreen> {
  var _revision = 0;
  Map<String, dynamic>? _selected;

  @override
  Widget build(BuildContext context) {
    final twoPane = NxBreakpoint.of(context).twoPane;
    return Scaffold(
      appBar: NxAppHeader(
        title: 'บันทึกการโทร',
        actions: [
          IconButton(
            icon: const Icon(NxI.arrowCounterClockwise),
            onPressed: () => setState(() => _revision++),
          ),
        ],
      ),
      body: NxCachedFuture<List<Map<String, dynamic>>>(
        revision: _revision,
        load: () => context.read<AppConfig>().apiClient.getCallLogWork(),
        skeleton: const NxSkeletonList(),
        isEmpty: (list) => list.isEmpty,
        empty: const Center(child: Text('ไม่มีรายการโทร')),
        builder: (context, list) {
          final items = ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final row = list[i];
              return DenseCardTile(
                leading: const Icon(NxI.phone),
                title: entityTitle(row, module: 'call_log'),
                subtitle: entitySubtitle(row) ?? row['status']?.toString(),
                onTap: () {
                  if (twoPane) {
                    setState(() => _selected = row);
                    return;
                  }
                  nxPush<void>(context, CallLogResultScreen(row: row)).then((_) {
                    if (mounted) setState(() => _revision++);
                  });
                },
              );
            },
          );
          return NxSplitView(
            list: items,
            detail: _selected == null
                ? null
                : CallLogResultScreen(
                    key: ValueKey(_selected!['id']),
                    row: _selected!,
                    embedded: true,
                  ),
          );
        },
      ),
    );
  }
}

class CallLogResultScreen extends StatefulWidget {
  const CallLogResultScreen({super.key, required this.row, this.embedded = false});
  final Map<String, dynamic> row;
  final bool embedded;

  @override
  State<CallLogResultScreen> createState() => _CallLogResultScreenState();
}

class _CallLogResultScreenState extends State<CallLogResultScreen> {
  String? _outcome = 'connected';
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppConfig>().apiClient.postCallLogResult(
            strId(widget.row['id']),
            outcome: _outcome,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (mounted) {
        if (widget.embedded) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกแล้ว')));
        } else {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NxAppHeader(
        title: entityTitle(widget.row, module: 'call_log'),
        automaticallyImplyLeading: !widget.embedded,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NxFormField(
            uiType: FieldUiType.enumeration,
            label: 'ผลสาย',
            value: _outcome,
            options: const [
              NxPickOption(value: 'connected', label: 'ติดต่อได้'),
              NxPickOption(value: 'no_answer', label: 'ไม่รับสาย'),
              NxPickOption(value: 'busy', label: 'สายไม่ว่าง'),
              NxPickOption(value: 'voicemail', label: 'ข้อความเสียง'),
            ],
            onChanged: (v) => setState(() => _outcome = v?.toString()),
          ),
          const SizedBox(height: 16),
          NxFormField(
            uiType: FieldUiType.longText,
            label: 'บันทึก',
            value: _notes.text,
            onChanged: (v) => _notes.text = v?.toString() ?? '',
          ),
          const SizedBox(height: 16),
          Builder(
            builder: (context) {
              final phone = (widget.row['phone'] ??
                      widget.row['mobile'] ??
                      widget.row['tel'] ??
                      widget.row['contact_phone'])
                  ?.toString()
                  .trim();
              if (phone == null || phone.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final uri = Uri(scheme: 'tel', path: phone);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                        icon: const Icon(NxI.phone),
                        label: Text('โทร $phone'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'คัดลอกเบอร์',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: phone));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('คัดลอกเบอร์แล้ว')),
                          );
                        }
                      },
                      icon: const Icon(NxI.clipboard),
                    ),
                  ],
                ),
              );
            },
          ),
          FilledButton(onPressed: _saving ? null : _save, child: const Text('บันทึกผล')),
        ],
      ),
    );
  }
}
