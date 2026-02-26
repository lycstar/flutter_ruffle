part of '../virtual_gamepad.dart';

class _EditControlsOverlay extends StatelessWidget {
  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EditControlsOverlay({
    required this.child,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  /// 构建编辑模式控件外壳：右上角提供“编辑/删除”按钮，不改变子控件的拖拽逻辑。
  Widget build(BuildContext context) {
    final iconColor = Colors.white.withValues(alpha: 0.92);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -12,
          right: -12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: onEdit,
                    child: Icon(
                      CupertinoIcons.pencil,
                      size: 20,
                      color: iconColor,
                    ),
                  ),
                ),
                SizedBox(
                  width: 1,
                  height: 44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: onDelete,
                    child: Icon(
                      CupertinoIcons.delete,
                      size: 20,
                      color: iconColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HoldableCircleButton extends StatefulWidget {
  final String label;
  final String logicalKey;
  final bool enabled;
  final VirtualKeyDown onKeyDown;
  final VirtualKeyUp onKeyUp;
  final void Function(Offset deltaPx)? onPan;

  const _HoldableCircleButton({
    required this.label,
    required this.logicalKey,
    required this.enabled,
    required this.onKeyDown,
    required this.onKeyUp,
    required this.onPan,
  });

  @override
  State<_HoldableCircleButton> createState() => _HoldableCircleButtonState();
}

class _HoldableCircleButtonState extends State<_HoldableCircleButton> {
  bool _pressed = false;

  @override
  /// 构建圆形按键：普通态支持按住输入；编辑态由外层负责编辑/删除，仅保留拖拽移动。
  Widget build(BuildContext context) {
    final bg = _pressed
        ? Colors.black.withValues(alpha: 0.30)
        : Colors.black.withValues(alpha: 0.18);
    final border = Colors.white.withValues(alpha: 0.22);
    final text = Colors.white.withValues(alpha: 0.90);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => widget.onPan?.call(d.delta),
      onTapDown: widget.enabled ? (_) => _down() : null,
      onTapUp: widget.enabled ? (_) => _up() : null,
      onTapCancel: widget.enabled ? _up : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: 58,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: text,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _down() async {
    if (_pressed) return;
    setState(() => _pressed = true);
    await widget.onKeyDown(widget.logicalKey);
  }

  Future<void> _up() async {
    if (!_pressed) return;
    setState(() => _pressed = false);
    await widget.onKeyUp(widget.logicalKey);
  }
}

class _HoldablePillButton extends StatefulWidget {
  final String label;
  final String logicalKey;
  final bool enabled;
  final VirtualKeyDown onKeyDown;
  final VirtualKeyUp onKeyUp;
  final void Function(Offset deltaPx)? onPan;

  const _HoldablePillButton({
    required this.label,
    required this.logicalKey,
    required this.enabled,
    required this.onKeyDown,
    required this.onKeyUp,
    required this.onPan,
  });

  @override
  State<_HoldablePillButton> createState() => _HoldablePillButtonState();
}

class _HoldablePillButtonState extends State<_HoldablePillButton> {
  bool _pressed = false;

  @override
  /// 构建胶囊按键：普通态支持按住输入；编辑态由外层负责编辑/删除，仅保留拖拽移动。
  Widget build(BuildContext context) {
    final bg = _pressed
        ? Colors.black.withValues(alpha: 0.30)
        : Colors.black.withValues(alpha: 0.18);
    final border = Colors.white.withValues(alpha: 0.18);
    final text = Colors.white.withValues(alpha: 0.82);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => widget.onPan?.call(d.delta),
      onTapDown: widget.enabled ? (_) => _down() : null,
      onTapUp: widget.enabled ? (_) => _up() : null,
      onTapCancel: widget.enabled ? _up : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: text,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _down() async {
    if (_pressed) return;
    setState(() => _pressed = true);
    await widget.onKeyDown(widget.logicalKey);
  }

  Future<void> _up() async {
    if (!_pressed) return;
    setState(() => _pressed = false);
    await widget.onKeyUp(widget.logicalKey);
  }
}

class _GamepadStick extends StatefulWidget {
  final bool enabled;
  final void Function(Offset deltaPx)? onMoveControl;
  final VirtualKeyDown onKeyDown;
  final VirtualKeyUp onKeyUp;
  final String up;
  final String down;
  final String left;
  final String right;
  final double sizePx;

  const _GamepadStick({
    required this.enabled,
    required this.onMoveControl,
    required this.onKeyDown,
    required this.onKeyUp,
    required this.up,
    required this.down,
    required this.left,
    required this.right,
    required this.sizePx,
  });

  @override
  State<_GamepadStick> createState() => _GamepadStickState();
}

class _GamepadStickState extends State<_GamepadStick> {
  Offset _knob = Offset.zero;
  String? _heldUp;
  String? _heldDown;
  String? _heldLeft;
  String? _heldRight;

  /// 将 logicalKey 转成便于识别的短标签，用于摇杆四方向叠加显示。
  String _shortKeyLabel(String logicalKey) {
    if (logicalKey == 'ArrowUp') return '↑';
    if (logicalKey == 'ArrowDown') return '↓';
    if (logicalKey == 'ArrowLeft') return '←';
    if (logicalKey == 'ArrowRight') return '→';
    if (logicalKey == ' ') return '␠';
    if (logicalKey == 'Enter') return '↵';
    if (logicalKey == 'Escape') return 'Esc';
    if (logicalKey.length == 1) return logicalKey.toUpperCase();
    return logicalKey;
  }

  @override
  /// 构建虚拟摇杆：普通态拖动触发方向键按住；编辑态由外层负责编辑/删除，仅保留拖拽移动位置。
  Widget build(BuildContext context) {
    Widget dirLabel(Alignment alignment, String text) {
      return Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: widget.enabled
          ? _onPanUpdate
          : (d) => widget.onMoveControl?.call(d.delta),
      onPanEnd: widget.enabled ? (_) => unawaited(_releaseAll()) : null,
      onPanCancel: widget.enabled ? () => unawaited(_releaseAll()) : null,
      child: SizedBox(
        width: widget.sizePx,
        height: widget.sizePx,
        child: Stack(
          children: [
            IgnorePointer(
              child: Stack(
                children: [
                  dirLabel(Alignment.topCenter, _shortKeyLabel(widget.up)),
                  dirLabel(Alignment.bottomCenter, _shortKeyLabel(widget.down)),
                  dirLabel(Alignment.centerLeft, _shortKeyLabel(widget.left)),
                  dirLabel(Alignment.centerRight, _shortKeyLabel(widget.right)),
                ],
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Container(
                width: widget.sizePx,
                height: widget.sizePx,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Transform.translate(
                offset: _knob,
                child: Container(
                  width: math.max(48.0, widget.sizePx * 0.45),
                  height: math.max(48.0, widget.sizePx * 0.45),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.26),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final radius = widget.sizePx * 0.22;
    final next = Offset(
      (_knob.dx + details.delta.dx).clamp(-radius, radius),
      (_knob.dy + details.delta.dy).clamp(-radius, radius),
    );
    setState(() => _knob = next);
    unawaited(_updateHeldKeysFromKnob(next));
  }

  Future<void> _updateHeldKeysFromKnob(Offset knob) async {
    final deadZone = widget.sizePx * 0.09;
    final wantUp = knob.dy < -deadZone;
    final wantDown = knob.dy > deadZone;
    final wantLeft = knob.dx < -deadZone;
    final wantRight = knob.dx > deadZone;

    await _syncHold(wantUp, widget.up, _heldUp, (v) => _heldUp = v);
    await _syncHold(wantDown, widget.down, _heldDown, (v) => _heldDown = v);
    await _syncHold(wantLeft, widget.left, _heldLeft, (v) => _heldLeft = v);
    await _syncHold(wantRight, widget.right, _heldRight, (v) => _heldRight = v);
  }

  Future<void> _syncHold(
    bool want,
    String key,
    String? held,
    void Function(String? v) setHeld,
  ) async {
    if (want) {
      if (held != null) return;
      setHeld(key);
      await widget.onKeyDown(key);
      return;
    }

    if (held == null) return;
    setHeld(null);
    await widget.onKeyUp(key);
  }

  Future<void> _releaseAll() async {
    final keys = <String>[
      if (_heldUp != null) _heldUp!,
      if (_heldDown != null) _heldDown!,
      if (_heldLeft != null) _heldLeft!,
      if (_heldRight != null) _heldRight!,
    ];
    _heldUp = null;
    _heldDown = null;
    _heldLeft = null;
    _heldRight = null;
    if (mounted) {
      setState(() => _knob = Offset.zero);
    } else {
      _knob = Offset.zero;
    }
    for (final k in keys) {
      await widget.onKeyUp(k);
    }
  }
}
