import 'package:flutter/material.dart';

import '../core/i18n.dart';

/// Emoji grid by category (no extra package). Used for reactions and the chat composer.
const nxEmojiCategories = <(String, String, List<String>)>[
  ('😀', 'หน้ายิ้ม', [
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😋', '😛',
    '😜', '🤪', '😝', '🤗', '🤭', '🤫', '🤔', '🤐', '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '😌', '😔', '😪', '😴',
    '😷', '🤒', '🤕', '🤢', '🤧', '🥵', '🥶', '😵', '🤯', '🤠', '🥳', '😎', '🤓', '🧐', '😕', '😟', '🙁', '😮', '😯', '😲',
    '😳', '🥺', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '😠',
  ]),
  ('👍', 'มือ & คน', [
    '👍', '👎', '👌', '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉', '👆', '👇', '☝️', '✋', '🤚', '🖐️', '🖖', '👋', '👏', '🙌',
    '👐', '🤲', '🤝', '🙏', '✍️', '💪', '🫶', '🫡', '🙋', '🙆', '🙅', '🤷', '🤦', '💁', '🙇', '🧑‍💻', '👨‍💼', '👩‍💼', '🧑‍🔧', '🏃',
  ]),
  ('❤️', 'หัวใจ & สัญลักษณ์', [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💯', '✅', '☑️',
    '✔️', '❌', '⭕', '❗', '❓', '⚠️', '🚫', '🔥', '✨', '⭐', '🌟', '💫', '⚡', '💥', '🎉', '🎊', '🎁', '🏆', '🥇', '🎯',
  ]),
  ('🐶', 'สัตว์ & อาหาร', [
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🦄', '🐝',
    '🍎', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍒', '🍑', '🥭', '🍍', '🥥', '🍔', '🍟', '🍕', '🍜', '🍣', '🍰', '☕', '🍺',
  ]),
  ('💼', 'งาน & ของ', [
    '💼', '📁', '📂', '🗂️', '📅', '📆', '🗓️', '📇', '📈', '📉', '📊', '📋', '📌', '📍', '📎', '🖇️', '✂️', '🖊️', '📝', '✏️',
    '🔍', '🔒', '🔓', '🔑', '💡', '🔔', '📢', '📣', '📞', '☎️', '📱', '💻', '🖥️', '⌨️', '🖨️', '📷', '🎥', '🚗', '🏠', '⏰',
  ]),
];

/// Bottom sheet with every category; returns the chosen emoji.
Future<String?> showNxEmojiPicker(BuildContext context, {List<String> quick = const []}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.55,
        child: NxEmojiGrid(quick: quick, onPick: (e) => Navigator.pop(ctx, e)),
      ),
    ),
  );
}

class NxEmojiGrid extends StatefulWidget {
  const NxEmojiGrid({super.key, required this.onPick, this.quick = const []});
  final ValueChanged<String> onPick;
  final List<String> quick;

  @override
  State<NxEmojiGrid> createState() => _NxEmojiGridState();
}

class _NxEmojiGridState extends State<NxEmojiGrid> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final emojis = nxEmojiCategories[_tab].$3;
    return Column(
      children: [
        if (widget.quick.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final e in widget.quick)
                  InkResponse(
                    onTap: () => widget.onPick(e),
                    radius: 24,
                    child: Padding(padding: const EdgeInsets.all(4), child: Text(e, style: const TextStyle(fontSize: 28))),
                  ),
              ],
            ),
          ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (var i = 0; i < nxEmojiCategories.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    key: ValueKey('emoji-tab-$i'),
                    label: Text('${nxEmojiCategories[i].$1} ${tr(nxEmojiCategories[i].$2)}'),
                    selected: _tab == i,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _tab = i),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 8, color: cs.outlineVariant),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 46, mainAxisSpacing: 2, crossAxisSpacing: 2),
            itemCount: emojis.length,
            itemBuilder: (_, i) => InkWell(
              key: ValueKey('emoji-${emojis[i]}'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => widget.onPick(emojis[i]),
              child: Center(child: Text(emojis[i], style: const TextStyle(fontSize: 26))),
            ),
          ),
        ),
      ],
    );
  }
}
