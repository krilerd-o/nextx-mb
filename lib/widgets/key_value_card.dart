import 'package:flutter/material.dart';

/// แสดงฟิลด์ entity แบบ key/value ในการ์ด
class KeyValueCard extends StatelessWidget {
  const KeyValueCard({
    super.key,
    required this.entries,
  });

  final List<MapEntry<String, String>> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      entries[i].key,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      entries[i].value,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              if (i < entries.length - 1) const Divider(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}
