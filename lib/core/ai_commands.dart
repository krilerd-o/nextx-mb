import 'package:flutter/widgets.dart';

/// Slash commands for the ISAAC composer: built-in ones, the business's quick
/// prompts (`/api/ai/quick-prompts`) and the user's own (`/api/ai/my-prompts`).
///
/// A command's [template] goes into the input; the first `[…]` in it is the
/// part to fill in and gets selected so the user can just type over it.
class AiCommand {
  const AiCommand({
    required this.command,
    required this.title,
    required this.template,
    this.description = '',
    this.icon = 'sparkle',
    this.source = AiCommandSource.builtin,
    this.id,
    this.deep = false,
    this.create,
    this.kind,
  });

  /// Without the slash, e.g. `lead`, `สรุป`.
  final String command;
  final String title;
  final String description;
  final String template;

  /// Icon key (see the composer's icon map).
  final String icon;
  final AiCommandSource source;

  /// Server id for business / user prompts.
  final String? id;

  /// Sends that one message in "คิดลึก" mode.
  final bool deep;

  /// Create commands open a real form (filled by Isaac) instead of a prompt:
  /// lead / contact / account / case / activity / quotation / workspace_item.
  final String? create;

  /// workspace_item: `task` or `epic`.
  final String? kind;

  bool get isCreate => create != null;

  factory AiCommand.fromQuickPrompt(Map<String, dynamic> m, {bool en = false}) {
    final name = '${(en ? m['name_en'] : m['name_th']) ?? m['name_th'] ?? m['name'] ?? ''}';
    final prompt = '${(en ? m['prompt_en'] : m['prompt_th']) ?? m['prompt_th'] ?? m['prompt'] ?? ''}';
    return AiCommand(
      command: aiCommandSlug('${m['code'] ?? ''}'.isNotEmpty ? '${m['code']}' : name),
      title: name,
      description: prompt.length > 60 ? '${prompt.substring(0, 60)}…' : prompt,
      template: prompt,
      icon: 'building',
      source: AiCommandSource.business,
      id: m['id']?.toString(),
    );
  }

  factory AiCommand.fromMine(Map<String, dynamic> m) {
    final prompt = '${m['prompt'] ?? ''}';
    final title = '${m['title'] ?? ''}';
    return AiCommand(
      command: '${m['command'] ?? ''}'.isNotEmpty ? '${m['command']}' : aiCommandSlug(title),
      title: title,
      description: prompt.length > 60 ? '${prompt.substring(0, 60)}…' : prompt,
      template: prompt,
      icon: 'user',
      source: AiCommandSource.mine,
      id: m['id']?.toString(),
    );
  }
}

enum AiCommandSource { builtin, business, mine }

String aiCommandSourceLabel(AiCommandSource s) => switch (s) {
  AiCommandSource.builtin => 'คำสั่งระบบ',
  AiCommandSource.business => 'คำสั่งของธุรกิจ',
  AiCommandSource.mine => 'คำสั่งของฉัน',
};

/// Same rule as the server: no slash, lower case, spaces → `-`, Thai kept.
String aiCommandSlug(String v) {
  final s = v.trim().replaceFirst(RegExp(r'^/+'), '').toLowerCase().replaceAll(RegExp(r'\s+'), '-');
  final out = s.replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}_-]', unicode: true), '');
  return out.length > 40 ? out.substring(0, 40) : out;
}

/// Built-in commands — common CRM jobs as one tap.
const kAiBuiltinCommands = <AiCommand>[
  AiCommand(
    command: 'ค้นหา',
    title: 'ค้นหาในระบบ',
    description: 'ลูกค้า สัญญา เคส บอร์ด',
    template: 'ค้นหา [ชื่อลูกค้า / เลขที่ / คำค้น] ในระบบ',
    icon: 'search',
  ),
  AiCommand(
    command: 'lead',
    create: 'lead',
    title: 'สร้าง Lead',
    description: 'ลูกค้าเป้าหมายใหม่',
    template: 'สร้าง Lead ใหม่: [ชื่อ บริษัท เบอร์โทร อีเมล]',
    icon: 'userPlus',
  ),
  AiCommand(
    command: 'contact',
    create: 'contact',
    title: 'สร้าง Contact',
    description: 'ผู้ติดต่อใหม่',
    template: 'สร้าง Contact ใหม่: [ชื่อ บริษัท เบอร์โทร อีเมล]',
    icon: 'contact',
  ),
  AiCommand(
    command: 'account',
    create: 'account',
    title: 'สร้างบัญชีลูกค้า',
    description: 'บริษัท / ลูกค้าใหม่',
    template: 'สร้างบัญชีลูกค้า: [ชื่อบริษัท เบอร์ อีเมล]',
    icon: 'building',
  ),
  AiCommand(
    command: 'quotation',
    create: 'quotation',
    title: 'สร้างใบเสนอราคา',
    description: 'ใบเสนอราคาให้ลูกค้า',
    template: 'ทำใบเสนอราคาให้ [ลูกค้า] รายการ [สินค้า จำนวน ราคา]',
    icon: 'doc',
  ),
  AiCommand(
    command: 'case',
    create: 'case',
    title: 'เปิดเคส',
    description: 'เคสบริการ / ปัญหาลูกค้า',
    template: 'เปิดเคสใหม่ให้ลูกค้า [ชื่อลูกค้า] เรื่อง [รายละเอียด]',
    icon: 'case',
  ),
  AiCommand(
    command: 'นัด',
    create: 'activity',
    title: 'นัดหมาย',
    description: 'สร้างนัดในปฏิทิน',
    template: 'นัด [ลูกค้า] วัน [วัน เวลา] เรื่อง [หัวข้อ]',
    icon: 'calendar',
  ),
  AiCommand(
    command: 'สรุป',
    title: 'สรุป',
    description: 'สรุปเรคคอร์ด / งาน / แชทนี้',
    template: 'สรุป [ลูกค้า / เคส / งานของฉันวันนี้] ให้หน่อย และควรทำอะไรต่อ',
    icon: 'summary',
  ),
  AiCommand(
    command: 'อีเมล',
    title: 'ร่างอีเมล',
    description: 'ร่างอีเมลติดตามลูกค้า',
    template: 'ร่างอีเมลติดตามถึง [ลูกค้า] เรื่อง [หัวข้อ] น้ำเสียงสุภาพ',
    icon: 'mail',
  ),
  AiCommand(
    command: 'excel',
    title: 'ส่งออก Excel',
    description: 'ข้อมูล CRM เป็นไฟล์ Excel',
    template: 'ส่งออก [Lead / Contact / เคส ...] ที่ [เงื่อนไข] เป็นไฟล์ Excel',
    icon: 'excel',
  ),
  AiCommand(
    command: 'pdf',
    title: 'ทำเอกสาร PDF',
    description: 'รายงาน / เอกสารเป็น PDF',
    template: 'ทำเอกสาร PDF เรื่อง [หัวข้อ] จากข้อมูลในระบบ',
    icon: 'pdf',
  ),
  AiCommand(
    command: 'word',
    title: 'ทำเอกสาร Word',
    description: 'ข้อเสนอ / รายงานเป็น Word',
    template: 'ทำเอกสาร Word เรื่อง [หัวข้อ] จากข้อมูลในระบบ',
    icon: 'doc',
  ),
  AiCommand(
    command: 'งาน',
    create: 'workspace_item',
    kind: 'task',
    title: 'งานบนบอร์ด',
    description: 'สร้าง Task บน Workspace',
    template: 'สร้างงานบนบอร์ด [ชื่อบอร์ด]: [ชื่องาน] กำหนดส่ง [วัน]',
    icon: 'board',
  ),
  AiCommand(
    command: 'epic',
    create: 'workspace_item',
    kind: 'epic',
    title: 'วางแผนเป็น Epic',
    description: 'แตกงานเป็น Epic / Task',
    template: 'วางแผนงาน [โครงการ] แตกเป็น Epic และ Task บนบอร์ด',
    icon: 'board',
  ),
  AiCommand(
    command: 'รายงาน',
    title: 'รายงาน / แดชบอร์ด',
    description: 'ยอดขาย ดีล กิจกรรม',
    template: 'ทำรายงาน [ยอดขาย / ดีล / กิจกรรม] ของ [ช่วงเวลา]',
    icon: 'chart',
  ),
  AiCommand(command: 'แปล', title: 'แปลภาษา', description: 'ไทย ↔ อังกฤษ', template: 'แปลเป็นภาษา [อังกฤษ / ไทย]: [ข้อความ]', icon: 'translate'),
  AiCommand(
    command: 'วิเคราะห์',
    title: 'วิเคราะห์เชิงลึก',
    description: 'ใช้โหมดคิดลึกกับข้อความนี้',
    template: 'วิเคราะห์ [เรื่อง] พร้อมข้อดีข้อเสีย และแนะนำสิ่งที่ควรทำ',
    icon: 'deep',
    deep: true,
  ),
];

/// Commands matching [query] (command or title, case-insensitive): exact /
/// prefix command matches first, then the rest in their original order.
List<AiCommand> aiFilterCommands(List<AiCommand> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  final starts = <AiCommand>[];
  final contains = <AiCommand>[];
  for (final c in all) {
    final cmd = c.command.toLowerCase();
    if (cmd.startsWith(q)) {
      starts.add(c);
    } else if (cmd.contains(q) || c.title.toLowerCase().contains(q)) {
      contains.add(c);
    }
  }
  return [...starts, ...contains];
}

/// The text after `/` while the user is typing a command: the input starts
/// with `/` and has no space or new line yet. Null otherwise.
String? aiSlashQuery(String text, [int? cursor]) {
  final upTo = cursor == null || cursor < 0 || cursor > text.length ? text : text.substring(0, cursor);
  final m = RegExp(r'^/([^\s/]*)$').firstMatch(upTo);
  return m?.group(1);
}

/// The text after `@` while the user is mentioning a record: `@` at the start
/// or after a space, up to the cursor, at most 3 words. Null otherwise.
String? aiMentionQuery(String text, [int? cursor]) {
  final upTo = cursor == null || cursor < 0 || cursor > text.length ? text : text.substring(0, cursor);
  final m = RegExp(r'(?:^|\s)@([^\s@]*(?: [^\s@]+){0,2})$').firstMatch(upTo);
  return m?.group(1);
}

/// [text] with the `@query` before [cursor] removed (the record becomes a chip).
({String text, int cursor}) aiStripMention(String text, int cursor) {
  final c = cursor < 0 || cursor > text.length ? text.length : cursor;
  final upTo = text.substring(0, c);
  final i = upTo.lastIndexOf('@');
  if (i < 0) return (text: text, cursor: c);
  final before = text.substring(0, i);
  final after = text.substring(c);
  return (text: '$before$after', cursor: before.length);
}

/// Where the first `[…]` placeholder is, to select it after inserting a template.
TextSelection aiTemplateSelection(String template) {
  final m = RegExp(r'\[[^\]]*\]').firstMatch(template);
  if (m == null) return TextSelection.collapsed(offset: template.length);
  return TextSelection(baseOffset: m.start, extentOffset: m.end);
}
