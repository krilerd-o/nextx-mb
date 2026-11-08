import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';

/// A page of the NEXTX web, signed in as the app's user: open
/// `{web}/login?token=…` (the web's own token login), then go to [path].
/// Used for AI Assistant parts that stay on the web (Agent, Notebook).
class WebSessionScreen extends StatefulWidget {
  const WebSessionScreen({super.key, required this.path, required this.title, this.subtitle});
  final String path;
  final String title;
  final String? subtitle;

  /// Web origin of the current server (the API and the web share it).
  static String webOrigin(String apiBaseUrl) {
    final u = Uri.tryParse(apiBaseUrl.trim());
    if (u == null || u.host.isEmpty) return apiBaseUrl;
    return u.origin;
  }

  @override
  State<WebSessionScreen> createState() => _WebSessionScreenState();
}

class _WebSessionScreenState extends State<WebSessionScreen> {
  late final WebViewController _web;
  int _progress = 0;
  bool _landed = false;
  late final String _origin;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    _origin = WebSessionScreen.webOrigin(config.apiBaseUrl);
    final token = config.session.accessToken ?? '';
    final login = Uri.parse('$_origin/login').replace(queryParameters: {'token': token});
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageFinished: (url) {
          final u = Uri.tryParse(url);
          if (u == null || _landed) return;
          // The web signs in on /login then moves on; then open the wanted page.
          if (!u.path.startsWith('/login')) {
            _landed = true;
            if (u.path != widget.path) _web.loadRequest(Uri.parse('$_origin${widget.path}'));
          }
        },
        onNavigationRequest: (req) {
          final u = Uri.tryParse(req.url);
          if (u != null && (u.scheme == 'http' || u.scheme == 'https') && u.origin != _origin) {
            launchUrl(u, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(login);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _web.canGoBack()) {
          final cur = await _web.currentUrl();
          if (cur != null && Uri.tryParse(cur)?.path != widget.path) {
            await _web.goBack();
            return;
          }
        }
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: SafeArea(
            bottom: false,
            child: NxAppHeader(
              title: widget.title,
              subtitle: widget.subtitle,
              actions: [
                IconButton(tooltip: tr('โหลดใหม่'), icon: const Icon(NxI.arrowsClockwise), onPressed: () => _web.reload()),
              ],
            ),
          ),
        ),
        body: Column(children: [
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100, minHeight: 2),
          Expanded(child: WebViewWidget(controller: _web)),
        ]),
      ),
    );
  }
}
