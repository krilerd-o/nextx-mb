import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/nx_page_route.dart' show nxLeavePage;
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
        onPageFinished: (url) async {
          final u = Uri.tryParse(url);
          if (u == null || _landed) return;
          // The web signs in on /login then moves on. The token carries the
          // business of the original sign-in, so point the web at the app's
          // current business / package first, then open the wanted page.
          if (!u.path.startsWith('/login')) {
            _landed = true;
            final s = config.session;
            try {
              await _web.runJavaScript(webSessionContextJs(businessId: s.businessId, businessName: s.businessName, packageCode: s.packageCode));
            } catch (_) {}
            await _web.loadRequest(Uri.parse('$_origin${widget.path}'));
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
        if (context.mounted) nxLeavePage(context);
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

/// Script that makes the web's saved session (`moai_next_auth`) use the
/// app's current business and package; no-op when not signed in there.
String webSessionContextJs({String? businessId, String? businessName, String? packageCode}) {
  if (businessId == null || businessId.isEmpty) return '';
  final bid = jsonEncode(int.tryParse(businessId) ?? businessId);
  final name = jsonEncode(businessName ?? '');
  final pkg = jsonEncode(packageCode);
  return "(function(){try{var k='moai_next_auth';var d=JSON.parse(localStorage.getItem(k)||'null');"
      "if(!d||!d.user)return;var bid=$bid,pkg=$pkg;"
      "if(!d.business||String(d.business.id)!==String(bid)){d.business={id:bid,name:$name};d.package=pkg?{code:pkg}:null;}"
      "else if(pkg&&(!d.package||d.package.code!==pkg)){d.package=Object.assign({},d.package||{},{code:pkg});}"
      "localStorage.setItem(k,JSON.stringify(d));}catch(e){}})();";
}
