import '../services/api_client.dart';
import 'session_state.dart';

/// ISAAC AI menu group — same items, order and visibility rules as the web
/// (`frontend/src/constants/layoutMenuItems.js` + `utils/visibleMenuItems.js`).
class IsaacMenuItem {
  const IsaacMenuItem(this.key, this.route, this.label, this.subtitle);
  final String key;
  final String route;
  final String label;
  final String subtitle;
}

class IsaacMenu {
  IsaacMenu._();

  static const assistant = IsaacMenuItem('ai-assistant', '/ai', 'AI Assistant', 'ผู้ช่วย AI ถามตอบงาน CRM');
  static const notebook = IsaacMenuItem('isaac-notebook', '/isaac', 'AI Notebook', 'สมุดโน้ต AI จาก ISAAC');
  static const minuteAuto = IsaacMenuItem('ai-minute-auto', '/ai-minute-auto', 'AI Minute Auto', 'จดบันทึกการประชุมอัตโนมัติ');
  static const agent = IsaacMenuItem('isaac-ai-agent', '/isaac-ai-agent', 'AI Agent', 'เร็วๆ นี้');
  static const socialWatch = IsaacMenuItem('isaac-social-watch', '/isaac-social-watch', 'AI Social Watch', 'เร็วๆ นี้');

  static const all = [assistant, notebook, minuteAuto, agent, socialWatch];
}

/// What the web reads before drawing the ISAAC AI group:
/// `GET /api/ai/settings` → `settings.ai_chat`, and
/// `GET /api/settings/isaac-plugin/effective` → plugin `config`.
class IsaacAccess {
  const IsaacAccess({this.aiChat = false, this.plugin, this.pluginLoaded = false});

  final bool aiChat;

  /// Plugin config (`enabled`, `audience`, `menus{...}`, `minute_auto{...}`).
  final Map<String, dynamic>? plugin;
  final bool pluginLoaded;

  static IsaacAccess fromResponses({Map<String, dynamic>? aiSettings, Map<String, dynamic>? pluginEffective}) {
    final s = aiSettings?['settings'];
    final cfg = pluginEffective?['config'];
    return IsaacAccess(
      aiChat: s is Map && s['ai_chat'] == true,
      plugin: cfg is Map ? Map<String, dynamic>.from(cfg) : null,
      pluginLoaded: cfg is Map,
    );
  }

  Map<String, dynamic> get _menus {
    final m = plugin?['menus'];
    return m is Map ? Map<String, dynamic>.from(m) : const {};
  }

  bool get pluginEnabled => plugin?['enabled'] == true;

  /// Minute Auto options (`default_language`, `show_transcript`, ...).
  Map<String, dynamic> get minuteAuto {
    final m = plugin?['minute_auto'];
    return m is Map ? Map<String, dynamic>.from(m) : const {};
  }

  bool visible(IsaacMenuItem item, SessionState session) {
    switch (item.key) {
      case 'ai-assistant':
        if (!aiChat) return false;
        if (pluginLoaded && _menus['assistant'] == false) return false;
        if (session.isSuperadmin) return true;
        // Package lists may leave it out — ai_chat already passed (like the web).
        return true;
      case 'isaac-notebook':
      case 'ai-minute-auto':
        if (!pluginLoaded || !pluginEnabled) return false;
        final hasMenus = plugin?['menus'] is Map;
        final on = item.key == 'isaac-notebook'
            ? (hasMenus ? _menus['notebook'] != false : plugin?['menu_bot'] != false)
            : (hasMenus ? _menus['minute_auto'] != false : plugin?['menu_minute_auto'] != false);
        if (!on) return false;
        if (session.isSuperadmin || plugin?['audience'] != 'menu_permission') return true;
        return session.canAccess(item.key);
      case 'isaac-ai-agent':
      case 'isaac-social-watch':
        if (!pluginLoaded) return false;
        if (item.key == 'isaac-ai-agent' && _menus['agent'] == false) return false;
        if (item.key == 'isaac-social-watch' && _menus['social_watch'] == false) return false;
        return aiChat || pluginEnabled;
    }
    return false;
  }

  List<IsaacMenuItem> visibleItems(SessionState session) => [
        for (final i in IsaacMenu.all)
          if (visible(i, session)) i,
      ];
}

/// Text for an ISAAC launch error. The server already sends a Thai message
/// (`isaacLaunchService.js`, `isaacAccess.js`); codes are the fallback.
String isaacLaunchErrorText(String code, {String? message}) {
  if (message != null && message.trim().isNotEmpty) return message.trim();
  final c = code.toUpperCase();
  if (c.contains('NOT_CONFIGURED') || c.contains('NOT_READY')) {
    return 'ยังไม่ได้ตั้งค่าหรือ Activate ISAAC — ให้ผู้ดูแลระบบตั้งค่าที่ Plugin Settings';
  }
  if (c.contains('PLUGIN_DISABLED')) return 'ธุรกิจนี้ยังไม่ได้เปิดใช้ ISAAC AI';
  if (c.contains('MENU_DISABLED')) return 'เมนูนี้ถูกปิดในการตั้งค่า ISAAC AI';
  if (c.contains('NO_ACCESS') || c.contains('FORBIDDEN') || c.contains('NOT_ALLOWED')) return 'คุณยังไม่มีสิทธิ์ใช้เมนูนี้';
  if (c.contains('429') || c.contains('RATE_LIMIT')) return 'เปิดบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่';
  return 'เปิด ISAAC ไม่สำเร็จ กรุณาลองใหม่';
}

/// Last ISAAC access per business (60 s, like the web hook).
class IsaacAccessCache {
  IsaacAccessCache._();
  static final Map<String, ({DateTime at, IsaacAccess access})> _cache = {};

  static IsaacAccess? peek(String businessId) => _cache[businessId]?.access;

  static Future<IsaacAccess> load(ApiClient api, String businessId, {bool fresh = false}) async {
    final hit = _cache[businessId];
    if (!fresh && hit != null && DateTime.now().difference(hit.at) < const Duration(seconds: 60)) return hit.access;
    Map<String, dynamic>? settings;
    Map<String, dynamic>? plugin;
    await Future.wait([
      api.getAiSettings().then((v) => settings = v).catchError((_) => <String, dynamic>{}),
      api.getIsaacPluginEffective().then((v) => plugin = v).catchError((_) => <String, dynamic>{}),
    ]);
    final access = IsaacAccess.fromResponses(aiSettings: settings, pluginEffective: plugin);
    _cache[businessId] = (at: DateTime.now(), access: access);
    return access;
  }

  static void clear() => _cache.clear();
}

/// Minute Auto route from plugin `minute_auto` (web `AiMinuteAutoPage.jsx`).
String isaacMinutePath(Map<String, dynamic> cfg) {
  final q = <String, String>{
    if ('${cfg['default_language'] ?? ''}'.isNotEmpty) 'lang': '${cfg['default_language']}',
    if (cfg['show_transcript'] == false) 'transcript': '0',
    if (cfg['allow_export'] == false) 'export': '0',
    if (cfg['notify_owner'] == false) 'notify': '0',
    if (cfg['auto_open_after_meeting'] == true) 'auto_open': '1',
  };
  if (q.isEmpty) return '/minute-auto';
  return '/minute-auto?${Uri(queryParameters: q).query}';
}

/// ISAAC URL signed in (web `buildIsaacLaunchUrl`): origin + route +
/// `_moai`/`embed=moai` + `#auth_token=` (the token stays in the hash, never
/// sent to the ISAAC server).
String buildIsaacLaunchUrl(Map<String, dynamic> payload, {String path = '/', String? bust}) {
  final origin = '${payload['app_origin'] ?? ''}'.trim().replaceAll(RegExp(r'/$'), '');
  final launch = '${payload['launch_url'] ?? ''}'.trim();
  final base = origin.isNotEmpty ? origin : launch.replaceAll(RegExp(r'#.*$'), '').replaceAll(RegExp(r'/$'), '');
  if (base.isEmpty) return '';
  final token = '${payload['isaac_token'] ?? ''}'.trim();
  var route = path.trim().isEmpty ? '/' : path.trim();
  if (!route.startsWith('/')) route = '/$route';
  // Keep an existing query on the route (Minute Auto options).
  final qi = route.indexOf('?');
  final routePath = (qi >= 0 ? route.substring(0, qi) : route).replaceAll(RegExp(r'/+$'), '');
  final params = <String, String>{
    if (qi >= 0) ...Uri.splitQueryString(route.substring(qi + 1)),
    if (bust != null && bust.isNotEmpty) '_moai': bust,
    'embed': 'moai',
  };
  final q = Uri(queryParameters: params).query;
  final url = '$base${routePath.isEmpty ? '/' : routePath}?$q';
  if (token.isEmpty) return launch.isNotEmpty && routePath.isEmpty ? launch : url;
  return '$url#auth_token=${Uri.encodeComponent(token)}';
}
