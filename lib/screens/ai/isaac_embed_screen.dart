import 'package:flutter/material.dart';

import '../../core/nx_page_route.dart' show nxLeavePage;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/isaac_menu.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';

enum _Phase { loading, ready, emailed, error }

/// AI Notebook / AI Minute Auto: the ISAAC web app, signed in with a one-time
/// launch from our backend (`POST /api/integrations/isaac/launch`) — same as
/// the web's iframe (`IsaacNotebookPage.jsx`). A fresh launch every time.
class IsaacEmbedScreen extends StatefulWidget {
  const IsaacEmbedScreen({super.key, required this.menu});

  /// `bot` (AI Notebook) or `minute_auto` (AI Minute Auto).
  final String menu;

  bool get isMinute => menu == 'minute_auto';
  String get title => isMinute ? 'AI Minute Auto' : 'AI Notebook';

  @override
  State<IsaacEmbedScreen> createState() => _IsaacEmbedScreenState();
}

class _IsaacEmbedScreenState extends State<IsaacEmbedScreen> {
  _Phase _phase = _Phase.loading;
  String _email = '';
  String _error = '';
  String _origin = '';
  int _progress = 0;
  WebViewController? _web;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  Future<void> _launch() async {
    final config = context.read<AppConfig>();
    setState(() {
      _phase = _Phase.loading;
      _error = '';
    });
    try {
      if (widget.isMinute) await Permission.microphone.request();
      final payload = await config.apiClient.isaacLaunch(widget.menu);
      if (!mounted) return;
      if ('${payload['next_step']}' == 'PASSWORD_SETUP_EMAILED') {
        setState(() {
          _email = '${payload['email'] ?? ''}';
          _phase = _Phase.emailed;
        });
        return;
      }
      var path = '/';
      if (widget.isMinute) {
        final access = await IsaacAccessCache.load(config.apiClient, config.session.businessId ?? '');
        path = isaacMinutePath(access.minuteAuto);
      }
      final url = buildIsaacLaunchUrl(payload, path: path, bust: '${DateTime.now().millisecondsSinceEpoch}');
      if (url.isEmpty) throw ApiEnvelopeException(503, 'ISAAC_503_NOT_CONFIGURED', '');
      _origin = Uri.tryParse(url)?.origin ?? '';
      _web = WebViewController(
        // Minute Auto records the meeting: let the page use the mic / camera.
        onPermissionRequest: (req) => req.grant(),
      )
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onNavigationRequest: (req) {
            final u = Uri.tryParse(req.url);
            // Links leaving ISAAC (downloads, other sites) open outside.
            if (u != null && (u.scheme == 'http' || u.scheme == 'https') && _origin.isNotEmpty && u.origin != _origin) {
              launchUrl(u, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ))
        ..loadRequest(Uri.parse(url));
      setState(() => _phase = _Phase.ready);
    } catch (e) {
      if (!mounted) return;
      final code = e is ApiEnvelopeException ? e.errorCode : (e is ApiException && e.statusCode == 429 ? 'RATE_LIMIT' : '');
      final msg = e is ApiEnvelopeException ? e.message : (e is ApiException ? e.userMessage : '');
      setState(() {
        _error = isaacLaunchErrorText(code, message: msg);
        _phase = _Phase.error;
      });
    }
  }

  Future<bool> _back() async {
    final w = _web;
    if (w != null && await w.canGoBack()) {
      await w.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget body;
    switch (_phase) {
      case _Phase.loading:
        body = Center(
          key: const ValueKey('isaac-loading'),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(tr(widget.isMinute ? 'กำลังเปิด ISAAC Minute Auto…' : 'กำลังเปิด ISAAC Notebook…')),
          ]),
        );
      case _Phase.ready:
        body = Column(children: [
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100, minHeight: 2),
          Expanded(child: WebViewWidget(key: const ValueKey('isaac-web'), controller: _web!)),
        ]);
      case _Phase.emailed:
        body = _Message(
          key: const ValueKey('isaac-emailed'),
          icon: NxI.envelope,
          color: cs.primary,
          badge: 'ตั้งรหัสผ่าน',
          text: 'ส่งอีเมลรหัสผ่านชั่วคราวไปที่ ${_email.isEmpty ? 'อีเมลของคุณ' : _email} แล้ว — ตั้งรหัสผ่านใหม่ตามอีเมล แล้วกลับมากดปุ่มด้านล่าง',
          action: 'ตั้งรหัสผ่านแล้ว เปิดอีกครั้ง',
          onAction: _launch,
        );
      case _Phase.error:
        body = _Message(
          key: const ValueKey('isaac-error'),
          icon: NxI.warningCircle,
          color: cs.error,
          badge: 'เปิดไม่สำเร็จ',
          text: _error,
          action: 'ลองอีกครั้ง',
          onAction: _launch,
        );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _back() && context.mounted) nxLeavePage(context);
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: SafeArea(
            bottom: false,
            child: NxAppHeader(
              title: widget.title,
              subtitle: 'ISAAC AI',
              actions: [
                IconButton(tooltip: tr('เปิดใหม่'), icon: const Icon(NxI.arrowsClockwise), onPressed: _phase == _Phase.loading ? null : _launch),
              ],
            ),
          ),
        ),
        body: body,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.icon, required this.color, required this.badge, required this.text, required this.action, required this.onAction});
  final IconData icon;
  final Color color;
  final String badge;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
            child: Text(tr(badge), style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          Text(tr(text), textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(height: 1.45)),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: onAction, icon: const Icon(NxI.arrowsClockwise, size: 18), label: Text(tr(action))),
        ]),
      ),
    );
  }
}
