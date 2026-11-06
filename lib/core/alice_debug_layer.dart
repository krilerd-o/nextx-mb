import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_alice.dart';
import '../widgets/nx_icons.dart';

/// ครอบ [MaterialApp] เพื่อขอสิทธิ์แจ้งเตือน (Alice ใช้แจ้งเตือนเมื่อมี HTTP) + ปุ่มเปิด Inspector
class AliceDebugLayer extends StatefulWidget {
  const AliceDebugLayer({super.key, required this.child});

  final Widget? child;

  @override
  State<AliceDebugLayer> createState() => _AliceDebugLayerState();
}

class _AliceDebugLayerState extends State<AliceDebugLayer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestNotification());
  }

  Future<void> _requestNotification() async {
    if (!appAliceActive) return;
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited) return;
    await Permission.notification.request();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child ?? const SizedBox.shrink();
    if (!appAliceActive) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const Positioned(
          right: 8,
          bottom: 8,
          child: SafeArea(
            child: FloatingActionButton.small(
              heroTag: 'moai_alice_http_inspector',
              tooltip: 'Alice — ดู HTTP API',
              onPressed: showAliceInspector,
              child: Icon(NxI.globe),
            ),
          ),
        ),
      ],
    );
  }
}
