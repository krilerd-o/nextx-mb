import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/i18n.dart';
import 'nx_app_header.dart';

/// Mermaid script (pinned version on cdnjs, like the web).
const kMermaidScript = 'https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.1/mermaid.min.js';

String _escapeHtml(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Page that draws a mermaid diagram in the app's light/dark colours.
String mermaidHtml(String code, {bool dark = false}) => '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=4">
<style>html,body{margin:0;padding:12px;background:${dark ? '#111114' : '#ffffff'};}
.mermaid{display:flex;justify-content:center}</style></head>
<body><pre class="mermaid">${_escapeHtml(code)}</pre>
<script src="$kMermaidScript"></script>
<script>mermaid.initialize({startOnLoad:true,securityLevel:'strict',theme:'${dark ? 'dark' : 'default'}'});</script>
</body></html>''';

/// Full-screen diagram viewer (pinch to zoom).
class NxMermaidView extends StatefulWidget {
  const NxMermaidView({super.key, required this.code});
  final String code;

  @override
  State<NxMermaidView> createState() => _NxMermaidViewState();
}

class _NxMermaidViewState extends State<NxMermaidView> {
  WebViewController? _web;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _web ??= WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (req) {
        final u = Uri.tryParse(req.url);
        if (u != null && (u.scheme == 'http' || u.scheme == 'https') && !req.url.startsWith(kMermaidScript)) {
          launchUrl(u, mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      }))
      ..loadHtmlString(mermaidHtml(widget.code, dark: Theme.of(context).brightness == Brightness.dark));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(bottom: false, child: NxAppHeader(title: tr('ไดอะแกรม'))),
      ),
      body: WebViewWidget(controller: _web!),
    );
  }
}
