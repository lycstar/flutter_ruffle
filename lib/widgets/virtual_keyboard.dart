import 'package:flutter/material.dart';

typedef VirtualKeyDown = Future<void> Function(String logicalKey);
typedef VirtualKeyUp = Future<void> Function(String logicalKey);

class VirtualKeyboard extends StatelessWidget {
  final bool visible;
  final VoidCallback onToggleVisible;
  final VirtualKeyDown onKeyDown;
  final VirtualKeyUp onKeyUp;

  const VirtualKeyboard({
    super.key,
    required this.visible,
    required this.onToggleVisible,
    required this.onKeyDown,
    required this.onKeyUp,
  });

  @override
  /// 构建虚拟英文键盘：通过按下/抬起回调向播放器注入键盘事件。
  Widget build(BuildContext context) {
    final bg = Colors.black.withValues(alpha: 0.45);
    final panel = Material(
      color: bg,
      borderRadius: BorderRadius.zero,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(child: SizedBox()),
                  IconButton(
                    onPressed: onToggleVisible,
                    icon: const Icon(Icons.keyboard_hide, color: Colors.white),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildRow(context, const [
                _KeySpec('1', '1'),
                _KeySpec('2', '2'),
                _KeySpec('3', '3'),
                _KeySpec('4', '4'),
                _KeySpec('5', '5'),
                _KeySpec('6', '6'),
                _KeySpec('7', '7'),
                _KeySpec('8', '8'),
                _KeySpec('9', '9'),
                _KeySpec('0', '0'),
                _KeySpec('退格', 'Backspace', flex: 2),
              ]),
              const SizedBox(height: 6),
              _buildRow(context, const [
                _KeySpec('Q', 'q'),
                _KeySpec('W', 'w'),
                _KeySpec('E', 'e'),
                _KeySpec('R', 'r'),
                _KeySpec('T', 't'),
                _KeySpec('Y', 'y'),
                _KeySpec('U', 'u'),
                _KeySpec('I', 'i'),
                _KeySpec('O', 'o'),
                _KeySpec('P', 'p'),
              ]),
              const SizedBox(height: 6),
              _buildRow(context, const [
                _KeySpec('A', 'a'),
                _KeySpec('S', 's'),
                _KeySpec('D', 'd'),
                _KeySpec('F', 'f'),
                _KeySpec('G', 'g'),
                _KeySpec('H', 'h'),
                _KeySpec('J', 'j'),
                _KeySpec('K', 'k'),
                _KeySpec('L', 'l'),
                _KeySpec('回车', 'Enter', flex: 2),
              ]),
              const SizedBox(height: 6),
              _buildRow(context, const [
                _KeySpec('Z', 'z'),
                _KeySpec('X', 'x'),
                _KeySpec('C', 'c'),
                _KeySpec('V', 'v'),
                _KeySpec('B', 'b'),
                _KeySpec('N', 'n'),
                _KeySpec('M', 'm'),
                _KeySpec('返回', 'Escape', flex: 2),
              ]),
              const SizedBox(height: 6),
              _buildBottomRow(),
            ],
          ),
        ),
      ),
    );

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, 1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: visible ? 1 : 0,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) {},
            onPointerUp: (_) {},
            child: panel,
          ),
        ),
      ),
    );
  }

  /// 构建键盘行：使用等分的弹性布局。
  Widget _buildRow(BuildContext context, List<_KeySpec> keys) {
    return Row(
      children: [
        for (final k in keys)
          Expanded(
            flex: k.flex,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _VirtualKeyButton(
                label: k.label,
                logicalKey: k.logicalKey,
                onKeyDown: onKeyDown,
                onKeyUp: onKeyUp,
              ),
            ),
          ),
      ],
    );
  }

  /// 构建底部功能行：空格在左，方向键在右（更接近真实键盘的倒 T 布局）。
  Widget _buildBottomRow() {
    Widget key({required String label, required String logicalKey}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: _VirtualKeyButton(
          label: label,
          logicalKey: logicalKey,
          onKeyDown: onKeyDown,
          onKeyUp: onKeyUp,
        ),
      );
    }

    return Row(
      children: [
        Expanded(flex: 6, child: key(label: '空格', logicalKey: ' ')),
        const SizedBox(width: 6),
        SizedBox(
          width: 150,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(child: SizedBox()),
                  Expanded(child: key(label: '↑', logicalKey: 'ArrowUp')),
                  const Expanded(child: SizedBox()),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: key(label: '←', logicalKey: 'ArrowLeft')),
                  Expanded(child: key(label: '↓', logicalKey: 'ArrowDown')),
                  Expanded(child: key(label: '→', logicalKey: 'ArrowRight')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KeySpec {
  final String label;
  final String logicalKey;
  final int flex;

  const _KeySpec(this.label, this.logicalKey, {this.flex = 1});
}

class _VirtualKeyButton extends StatefulWidget {
  final String label;
  final String logicalKey;
  final VirtualKeyDown onKeyDown;
  final VirtualKeyUp onKeyUp;

  const _VirtualKeyButton({
    required this.label,
    required this.logicalKey,
    required this.onKeyDown,
    required this.onKeyUp,
  });

  @override
  State<_VirtualKeyButton> createState() => _VirtualKeyButtonState();
}

class _VirtualKeyButtonState extends State<_VirtualKeyButton> {
  bool _pressed = false;

  @override
  /// 构建单个虚拟按键按钮：支持按住不放并在抬起时发送 KeyUp。
  Widget build(BuildContext context) {
    final bg = _pressed ? Colors.white.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.18);
    final border = Colors.white.withValues(alpha: 0.22);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: border),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// 处理按下：避免重复触发，并向上层发送 KeyDown。
  Future<void> _down() async {
    if (_pressed) return;
    setState(() => _pressed = true);
    await widget.onKeyDown(widget.logicalKey);
  }

  /// 处理抬起/取消：保证 KeyUp 发送一次。
  Future<void> _up() async {
    if (!_pressed) return;
    setState(() => _pressed = false);
    await widget.onKeyUp(widget.logicalKey);
  }
}
