import 'package:flutter/widgets.dart';

/// Where the tab menu sits on a tablet / wide screen (phones keep the bottom bar).
enum NxNavDock {
  left('left', 'ซ้าย', Alignment.centerLeft),
  right('right', 'ขวา', Alignment.centerRight),
  topLeft('top_left', 'บนซ้าย', Alignment.topLeft),
  topCenter('top_center', 'บนกลาง', Alignment.topCenter),
  topRight('top_right', 'บนขวา', Alignment.topRight),
  bottomLeft('bottom_left', 'ล่างซ้าย', Alignment.bottomLeft),
  bottomCenter('bottom_center', 'ล่างกลาง', Alignment.bottomCenter),
  bottomRight('bottom_right', 'ล่างขวา', Alignment.bottomRight);

  const NxNavDock(this.id, this.label, this.alignment);
  final String id;
  final String label;
  final Alignment alignment;

  /// Left / right = vertical rail; the others = horizontal bar.
  bool get vertical => this == left || this == right;
  bool get isTop => this == topLeft || this == topCenter || this == topRight;
  bool get isBottom => this == bottomLeft || this == bottomCenter || this == bottomRight;
}

const NxNavDock kDefaultNavDock = NxNavDock.left;

NxNavDock resolveNavDock(String? id) {
  for (final d in NxNavDock.values) {
    if (d.id == id) return d;
  }
  return kDefaultNavDock;
}
