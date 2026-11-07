import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_config.dart';
import '../../core/auth_redirect.dart';
import '../../core/i18n.dart';

/// LINE login inside an in-app WebView. NEXTX redirects the browser to
/// `{frontend}/login?token=…`; we stop that navigation and keep the JWT.
/// Pops with the JWT, or with an error code prefixed `error:`.
class LineLoginScreen extends StatefulWidget {
  const LineLoginScreen({super.key});

  @override
  State<LineLoginScreen> createState() => _LineLoginScreenState();
}

class _LineLoginScreenState extends State<LineLoginScreen> {
  late final WebViewController _web;
  var _progress = 0;
  var _done = false;

  @override
  void initState() {
    super.initState();
    final url = context.read<AppConfig>().apiClient.lineLoginUrl;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onNavigationRequest: (req) => _handle(req.url) ? NavigationDecision.prevent : NavigationDecision.navigate,
        onUrlChange: (change) {
          final u = change.url;
          if (u != null) _handle(u);
        },
        onPageStarted: _handle,
      ));
    // Fresh LINE session each time so the user can switch accounts.
    WebViewCookieManager().clearCookies().whenComplete(() => _web.loadRequest(Uri.parse(url)));
  }

  /// True when [url] is the NEXTX callback landing (token or error).
  bool _handle(String url) {
    if (_done) return true;
    final r = parseAuthRedirect(url);
    if (r == null) return false;
    _done = true;
    final result = r.token ?? 'error:${r.error ?? 'line_failed'}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('เข้าสู่ระบบด้วย LINE')),
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100, minHeight: 2),
              )
            : null,
      ),
      body: WebViewWidget(controller: _web),
    );
  }
}
