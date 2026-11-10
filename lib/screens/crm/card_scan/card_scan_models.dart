import 'dart:typed_data';

/// Modules that can be created from a business card.
const kCardScanModules = {'lead', 'contact', 'account'};

/// Front (and optional back) of a card, ready to send (JPEG).
class CardImages {
  const CardImages({required this.front, this.back});
  final Uint8List front;
  final Uint8List? back;
}

/// One value the server read and mapped onto a field.
class CardField {
  CardField({
    required this.name,
    required this.value,
    required this.label,
    required this.confidence,
    this.source,
    this.kind,
  });

  final String name;
  String value;
  final String label;

  /// high | medium | low
  final String confidence;
  final String? source;
  final String? kind;

  bool get sure => confidence == 'high';

  factory CardField.from(String name, Map m) => CardField(
        name: name,
        value: '${m['value'] ?? ''}',
        label: '${m['label'] ?? name}',
        confidence: '${m['confidence'] ?? 'medium'}',
        source: m['source']?.toString(),
        kind: m['kind']?.toString(),
      );
}

/// Read but without a field of its own (fax, LINE, other language…).
class CardExtra {
  const CardExtra({required this.kind, required this.value, required this.label});
  final String kind;
  final String value;
  final String label;
}

class CardDuplicate {
  const CardDuplicate({required this.module, required this.id, required this.name, required this.reason});
  final String module;
  final String id;
  final String name;
  final String reason;
}

class CardScanResult {
  CardScanResult({
    required this.status,
    required this.engine,
    required this.rawText,
    required this.fields,
    required this.extras,
    required this.duplicates,
    this.accountSuggestion,
    this.dropped = 0,
  });

  /// ok | no_ai | unreadable
  final String status;

  /// gemini | openai | claude | device_ocr | none
  final String engine;
  final String rawText;
  final List<CardField> fields;
  final List<CardExtra> extras;
  final List<CardDuplicate> duplicates;
  final ({String id, String name})? accountSuggestion;
  final int dropped;

  bool get offline => engine == 'device_ocr';

  factory CardScanResult.from(Map<String, dynamic> d) {
    final f = d['fields'] is Map ? d['fields'] as Map : const {};
    final acc = d['account_suggestion'];
    return CardScanResult(
      status: '${d['status'] ?? 'ok'}',
      engine: '${d['engine'] ?? 'none'}',
      rawText: '${d['raw_text'] ?? ''}',
      fields: [
        for (final e in f.entries)
          if (e.value is Map) CardField.from('${e.key}', e.value as Map),
      ],
      extras: [
        for (final u in (d['unmapped'] as List? ?? const []))
          if (u is Map) CardExtra(kind: '${u['kind']}', value: '${u['value']}', label: '${u['label'] ?? u['kind']}'),
      ],
      duplicates: [
        for (final u in (d['duplicates'] as List? ?? const []))
          if (u is Map) CardDuplicate(module: '${u['module']}', id: '${u['id']}', name: '${u['name'] ?? ''}', reason: '${u['reason'] ?? ''}'),
      ],
      accountSuggestion: acc is Map && acc['id'] != null ? (id: '${acc['id']}', name: '${acc['name'] ?? ''}') : null,
      dropped: (d['dropped'] as num?)?.toInt() ?? 0,
    );
  }
}

/// What the review screen hands back to the form.
class CardScanApply {
  const CardScanApply({required this.values, required this.attach, required this.images, this.note});

  /// field name → value to put in the form (only the ones the user kept).
  final Map<String, dynamic> values;

  /// Attach the card photo(s) to the record after it is saved.
  final bool attach;
  final CardImages images;

  /// Extra lines the user chose to keep (added to "รายละเอียด").
  final String? note;
}
