import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports its child's laid-out size after each layout that changes it.
class NxMeasureSize extends SingleChildRenderObjectWidget {
  const NxMeasureSize({super.key, required this.onChange, super.child});
  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasure(onChange);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasure renderObject) => renderObject.onChange = onChange;
}

class _RenderMeasure extends RenderProxyBox {
  _RenderMeasure(this.onChange);
  ValueChanged<Size> onChange;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final s = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(s));
  }
}
