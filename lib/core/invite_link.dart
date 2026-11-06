import 'server_profile.dart';

/// A NEXTX "join business" link: `{web}/register?invite=TOKEN`
/// (backend businesses.js) or `moainext://app/register?invite=TOKEN`.
class InviteLink {
  const InviteLink({required this.token, this.server});

  final String token;

  /// `https://host` when the link came from the web; null for the app scheme.
  final String? server;
}

InviteLink? parseInviteLink(Uri uri) {
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty || segs.last != 'register') return null;
  final token = (uri.queryParameters['invite'] ?? uri.queryParameters['invite_token'] ?? '').trim();
  if (token.isEmpty) return null;
  final web = (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
  return InviteLink(
    token: token,
    server: web ? normalizeServerUrl('${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}') : null,
  );
}
