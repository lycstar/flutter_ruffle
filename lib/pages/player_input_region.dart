import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef PlayerFire = void Function(Future<void> Function() op);

class PlayerInputRegion extends StatefulWidget {
  final Widget child;
  final FocusNode focusNode;
  final bool enabled;
  final double scaleFactor;
  final int viewportWidthPx;
  final int viewportHeightPx;
  final PlayerFire fire;
  final VoidCallback requestPumpSoon;
  final Future<void> Function() releaseAllPressedKeys;

  const PlayerInputRegion({
    super.key,
    required this.child,
    required this.focusNode,
    required this.enabled,
    required this.scaleFactor,
    required this.viewportWidthPx,
    required this.viewportHeightPx,
    required this.fire,
    required this.requestPumpSoon,
    required this.releaseAllPressedKeys,
  });

  @override
  /// 创建输入区域组件状态（负责键盘/鼠标/触控事件分发）。
  State<PlayerInputRegion> createState() => _PlayerInputRegionState();
}

class _PlayerInputRegionState extends State<PlayerInputRegion> {
  final Map<int, int> _pointerButtonById = {};

  bool _isDesktop() => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// 将 Flutter 的按键事件映射为 Ruffle 可识别的 logicalKey 字符串。
  String _logicalKeyToRuffle(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.backspace) return 'Backspace';
    if (key == LogicalKeyboardKey.delete) return 'Delete';
    if (key == LogicalKeyboardKey.escape) return 'Escape';
    if (key == LogicalKeyboardKey.arrowLeft) return 'ArrowLeft';
    if (key == LogicalKeyboardKey.arrowRight) return 'ArrowRight';
    if (key == LogicalKeyboardKey.arrowUp) return 'ArrowUp';
    if (key == LogicalKeyboardKey.arrowDown) return 'ArrowDown';
    if (key == LogicalKeyboardKey.home) return 'Home';
    if (key == LogicalKeyboardKey.end) return 'End';
    if (key == LogicalKeyboardKey.pageUp) return 'PageUp';
    if (key == LogicalKeyboardKey.pageDown) return 'PageDown';
    if (key == LogicalKeyboardKey.space) return ' ';
    if (key == LogicalKeyboardKey.shiftLeft) return 'ShiftLeft';
    if (key == LogicalKeyboardKey.shiftRight) return 'ShiftRight';
    if (key == LogicalKeyboardKey.controlLeft) return 'ControlLeft';
    if (key == LogicalKeyboardKey.controlRight) return 'ControlRight';
    if (key == LogicalKeyboardKey.altLeft) return 'AltLeft';
    if (key == LogicalKeyboardKey.altRight) return 'AltRight';
    if (key == LogicalKeyboardKey.metaLeft) return 'SuperLeft';
    if (key == LogicalKeyboardKey.metaRight) return 'SuperRight';

    final label = key.keyLabel;
    if (label.isNotEmpty && label.runes.length == 1) {
      final ch = label;
      final lower = ch.toLowerCase();
      return lower != ch.toUpperCase() ? lower : ch;
    }

    final ch = event.character;
    if (ch != null && ch.runes.length == 1) {
      final lower = ch.toLowerCase();
      return lower != ch.toUpperCase() ? lower : ch;
    }

    return 'Unidentified';
  }

  /// 将 PointerEvent 的 buttons 位掩码映射为 Ruffle 的按钮编码（0=Left,1=Right,2=Middle）。
  int _mouseButtonToRuffle(int buttons) {
    if ((buttons & kSecondaryMouseButton) != 0) return 1;
    if ((buttons & kMiddleMouseButton) != 0) return 2;
    return 0;
  }

  /// 将 Flutter 本地逻辑像素坐标转换为 viewport 物理像素坐标，并做边界裁剪。
  Offset _localToViewportPixels({required Offset local}) {
    final x =
        (local.dx * widget.scaleFactor).clamp(0.0, widget.viewportWidthPx.toDouble()).toDouble();
    final y =
        (local.dy * widget.scaleFactor).clamp(0.0, widget.viewportHeightPx.toDouble()).toDouble();
    return Offset(x, y);
  }

  @override
  /// 构建输入区域：Focus/Keyboard + MouseRegion + Listener 组合。
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          if (widget.enabled) {
            widget.fire(_sendFocusGained);
          }
        } else {
          unawaited(widget.releaseAllPressedKeys());
          if (widget.enabled) {
            widget.fire(_sendFocusLost);
          }
        }
        widget.requestPumpSoon();
      },
      onKeyEvent: (node, event) {
        if (!widget.enabled) return KeyEventResult.ignored;

        final logicalKey = _logicalKeyToRuffle(event);
        if (logicalKey == 'Unidentified') return KeyEventResult.ignored;
        if (event is KeyDownEvent) {
          widget.fire(() => _sendKeyDown(logicalKey: logicalKey));
          final ch = event.character;
          if (ch != null && ch.runes.length == 1) {
            widget.fire(() => _sendTextInput(codepoint: ch));
          }
          widget.requestPumpSoon();
          return KeyEventResult.handled;
        }
        if (event is KeyRepeatEvent) {
          final ch = event.character;
          if (ch != null && ch.runes.length == 1) {
            widget.fire(() => _sendTextInput(codepoint: ch));
            widget.requestPumpSoon();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }
        if (event is KeyUpEvent) {
          widget.fire(() => _sendKeyUp(logicalKey: logicalKey));
          widget.requestPumpSoon();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          if (!widget.enabled) return;
          widget.fire(() => _setMouseInStage(isInStage: true));
          widget.requestPumpSoon();
        },
        onExit: (_) {
          if (!widget.enabled) return;
          widget.fire(() => _setMouseInStage(isInStage: false));
          widget.fire(_sendMouseLeave);
          widget.requestPumpSoon();
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (!widget.enabled) return;
            widget.focusNode.requestFocus();
            final p = _localToViewportPixels(local: event.localPosition);
            final button = _mouseButtonToRuffle(event.buttons);
            _pointerButtonById[event.pointer] = button;
            widget.fire(() => _sendMouseDown(x: p.dx, y: p.dy, button: button));
            widget.requestPumpSoon();
          },
          onPointerUp: (event) {
            if (!widget.enabled) return;
            final p = _localToViewportPixels(local: event.localPosition);
            final button = _pointerButtonById.remove(event.pointer) ?? _mouseButtonToRuffle(event.buttons);
            widget.fire(() => _sendMouseUp(x: p.dx, y: p.dy, button: button));
            widget.requestPumpSoon();
          },
          onPointerCancel: (event) {
            if (!widget.enabled) return;
            _pointerButtonById.remove(event.pointer);
            widget.fire(() => _setMouseInStage(isInStage: false));
            widget.fire(_sendMouseLeave);
            widget.requestPumpSoon();
          },
          onPointerMove: (event) {
            if (!widget.enabled) return;
            final p = _localToViewportPixels(local: event.localPosition);
            widget.fire(() => _sendMouseMove(x: p.dx, y: p.dy));
          },
          onPointerHover: (event) {
            if (!widget.enabled) return;
            final p = _localToViewportPixels(local: event.localPosition);
            widget.fire(() => _sendMouseMove(x: p.dx, y: p.dy));
          },
          onPointerSignal: (signal) {
            if (!widget.enabled) return;
            if (signal is PointerScrollEvent) {
              widget.fire(() => _sendMouseWheel(deltaPixels: signal.scrollDelta.dy));
              widget.requestPumpSoon();
            }
          },
          child: widget.child,
        ),
      ),
    );
  }

  /// 发送键盘按下到 player（由上层通过 fire 分发具体实现）。
  Future<void> _sendKeyDown({required String logicalKey}) async {
    final f = PlayerInputBindings.of(context);
    await f.sendKeyDown(logicalKey: logicalKey);
  }

  /// 发送键盘抬起到 player（由上层通过 fire 分发具体实现）。
  Future<void> _sendKeyUp({required String logicalKey}) async {
    final f = PlayerInputBindings.of(context);
    await f.sendKeyUp(logicalKey: logicalKey);
  }

  /// 发送文本输入到 player（由上层通过 fire 分发具体实现）。
  Future<void> _sendTextInput({required String codepoint}) async {
    final f = PlayerInputBindings.of(context);
    await f.sendTextInput(codepoint: codepoint);
  }

  /// 发送鼠标移动到 player（由上层通过 fire 分发具体实现）。
  Future<void> _sendMouseMove({required double x, required double y}) async {
    final f = PlayerInputBindings.of(context);
    await f.sendMouseMove(x: x, y: y);
  }

  /// 发送鼠标按下到 player（由上层通过 fire 分发具体实现）。
  Future<void> _sendMouseDown({required double x, required double y, required int button}) async {
    final f = PlayerInputBindings.of(context);
    await f.sendMouseDown(x: x, y: y, button: button);
  }

  /// 发送鼠标抬起到 player（由上层通过 fire 分发具体实现）。
  Future<void> _sendMouseUp({required double x, required double y, required int button}) async {
    final f = PlayerInputBindings.of(context);
    await f.sendMouseUp(x: x, y: y, button: button);
  }

  /// 发送鼠标离开到 player（由上层通过 fire 分发具体实现）。
  Future<void> _sendMouseLeave() async {
    final f = PlayerInputBindings.of(context);
    await f.sendMouseLeave();
  }

  /// 设置鼠标是否在舞台内（由上层通过 fire 分发具体实现）。
  Future<void> _setMouseInStage({required bool isInStage}) async {
    final f = PlayerInputBindings.of(context);
    await f.setMouseInStage(isInStage: isInStage);
  }

  /// 发送鼠标滚轮到 player（由上层通过 fire 分发具体实现）。
  Future<void> _sendMouseWheel({required double deltaPixels}) async {
    if (!_isDesktop()) return;
    final f = PlayerInputBindings.of(context);
    await f.sendMouseWheel(deltaPixels: deltaPixels);
  }

  /// 通知 player 获得焦点（由上层通过 fire 分发具体实现）。
  Future<void> _sendFocusGained() async {
    final f = PlayerInputBindings.of(context);
    await f.sendFocusGained();
  }

  /// 通知 player 失去焦点（由上层通过 fire 分发具体实现）。
  Future<void> _sendFocusLost() async {
    final f = PlayerInputBindings.of(context);
    await f.sendFocusLost();
  }
}

class PlayerInputBindings extends InheritedWidget {
  final Future<void> Function({required String logicalKey}) sendKeyDown;
  final Future<void> Function({required String logicalKey}) sendKeyUp;
  final Future<void> Function({required String codepoint}) sendTextInput;
  final Future<void> Function({required double x, required double y}) sendMouseMove;
  final Future<void> Function({required double x, required double y, required int button}) sendMouseDown;
  final Future<void> Function({required double x, required double y, required int button}) sendMouseUp;
  final Future<void> Function() sendMouseLeave;
  final Future<void> Function({required bool isInStage}) setMouseInStage;
  final Future<void> Function({required double deltaPixels}) sendMouseWheel;
  final Future<void> Function() sendFocusGained;
  final Future<void> Function() sendFocusLost;

  const PlayerInputBindings({
    super.key,
    required super.child,
    required this.sendKeyDown,
    required this.sendKeyUp,
    required this.sendTextInput,
    required this.sendMouseMove,
    required this.sendMouseDown,
    required this.sendMouseUp,
    required this.sendMouseLeave,
    required this.setMouseInStage,
    required this.sendMouseWheel,
    required this.sendFocusGained,
    required this.sendFocusLost,
  });

  /// 获取输入绑定（由 PlayerPage 提供 worker 调用实现）。
  static PlayerInputBindings of(BuildContext context) {
    final v = context.dependOnInheritedWidgetOfExactType<PlayerInputBindings>();
    if (v == null) {
      throw StateError('PlayerInputBindings 未注入');
    }
    return v;
  }

  @override
  /// 判断是否需要通知子树更新。
  bool updateShouldNotify(PlayerInputBindings oldWidget) {
    return sendKeyDown != oldWidget.sendKeyDown ||
        sendKeyUp != oldWidget.sendKeyUp ||
        sendTextInput != oldWidget.sendTextInput ||
        sendMouseMove != oldWidget.sendMouseMove ||
        sendMouseDown != oldWidget.sendMouseDown ||
        sendMouseUp != oldWidget.sendMouseUp ||
        sendMouseLeave != oldWidget.sendMouseLeave ||
        setMouseInStage != oldWidget.setMouseInStage ||
        sendMouseWheel != oldWidget.sendMouseWheel ||
        sendFocusGained != oldWidget.sendFocusGained ||
        sendFocusLost != oldWidget.sendFocusLost;
  }
}
