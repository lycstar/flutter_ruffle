import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

part 'virtual_gamepad/models.dart';
part 'virtual_gamepad/controls.dart';

typedef VirtualKeyDown = Future<void> Function(String logicalKey);
typedef VirtualKeyUp = Future<void> Function(String logicalKey);

enum VirtualGamepadButtonShape { circle, pill }

class VirtualGamepad extends StatefulWidget {
  final bool visible;
  final VoidCallback onToggleVisible;
  final VirtualKeyDown onKeyDown;
  final VirtualKeyUp onKeyUp;
  final VirtualGamepadConfigStore store;
  final GamepadPickKey onPickKey;
  final GamepadSaveStore onSaveStore;

  const VirtualGamepad({
    super.key,
    required this.visible,
    required this.onToggleVisible,
    required this.onKeyDown,
    required this.onKeyUp,
    required this.store,
    required this.onPickKey,
    required this.onSaveStore,
  });

  @override
  /// 创建虚拟手柄状态对象。
  State<VirtualGamepad> createState() => _VirtualGamepadState();
}

enum _GamepadAddType { joystick, button }

class _VirtualGamepadState extends State<VirtualGamepad> {
  bool _editing = false;
  VirtualGamepadUserConfig? _draft;
  _GamepadAddType _addType = _GamepadAddType.button;

  /// 获取当前生效配置（编辑态返回草稿，否则返回外部配置）。
  VirtualGamepadUserConfig _cfg() =>
      _draft ?? widget.store.currentPreset().config;

  /// 获取当前选中的配置预设（找不到则回退到默认）。
  VirtualGamepadConfigPreset _currentPreset() => widget.store.currentPreset();

  /// 将 logicalKey 显示为按钮文本（单字符显示为大写；空格显示为 ␠；方向键显示箭头）。
  String _labelForLogicalKey(String logicalKey) {
    if (logicalKey == 'ArrowUp') return '↑';
    if (logicalKey == 'ArrowDown') return '↓';
    if (logicalKey == 'ArrowLeft') return '←';
    if (logicalKey == 'ArrowRight') return '→';
    if (logicalKey == ' ') return '␠';
    if (logicalKey.length == 1) return logicalKey.toUpperCase();
    return logicalKey;
  }

  /// 进入编辑模式：复制当前配置作为草稿。
  void _enterEdit() {
    if (_editing) return;
    final cfg = _currentPreset().config;
    setState(() {
      _editing = true;
      _addType = cfg.joysticks.isEmpty
          ? _GamepadAddType.joystick
          : _GamepadAddType.button;
      _draft = VirtualGamepadUserConfig(
        joysticks: cfg.joysticks.toList(growable: true),
        buttons: cfg.buttons.toList(growable: true),
      );
    });
  }

  /// 打开“配置管理”弹窗：选择/新建/重命名/删除（默认配置不可删除）。
  Future<void> _openConfigManager() async {
    if (_editing) return;
    final store = widget.store;
    final selected = store.selectedId;
    final result = await showCupertinoDialog<VirtualGamepadConfigStore>(
      context: context,
      builder: (context) {
        var temp = store;
        String newId() =>
            'cfg_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1 << 20)}';

        Future<String?> askName({
          required String title,
          required String initial,
        }) async {
          final controller = TextEditingController(text: initial);
          final name = await showCupertinoModalPopup<String>(
            context: context,
            builder: (context) {
              final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: Center(
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: CupertinoPopupSurface(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            CupertinoTextField(
                              controller: controller,
                              placeholder: '名称',
                              autofocus: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => Navigator.of(context)
                                  .pop(controller.text),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: CupertinoButton(
                                    color: CupertinoColors.systemGrey5,
                                    borderRadius: BorderRadius.circular(12),
                                    onPressed: () =>
                                        Navigator.of(context).pop(''),
                                    child: const Text(
                                      '取消',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: CupertinoButton.filled(
                                    borderRadius: BorderRadius.circular(12),
                                    onPressed: () => Navigator.of(context)
                                        .pop(controller.text),
                                    child: const Text(
                                      '确定',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
          controller.dispose();
          final trimmed = (name ?? '').trim();
          return trimmed.isEmpty ? null : trimmed;
        }

        return StatefulBuilder(
          builder: (context, setLocalState) {
            final current = temp.currentPreset();
            final screen = MediaQuery.sizeOf(context);
            final maxListHeight =
                math.min(420.0, (screen.height * 0.40).clamp(180.0, 560.0));

            Widget presetTile(VirtualGamepadConfigPreset p) {
              final isSelected = temp.selectedId == p.id;
              final tileBg = isSelected
                  ? CupertinoColors.systemBlue.withValues(alpha: 0.10)
                  : CupertinoColors.systemGrey6;
              final tileBorder = isSelected
                  ? CupertinoColors.systemBlue.withValues(alpha: 0.35)
                  : CupertinoColors.systemGrey4;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tileBorder),
                  ),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    onPressed: () {
                      setLocalState(() {
                        temp = temp.copyWith(selectedId: p.id);
                      });
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CupertinoColors.label,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (isSelected)
                          const Icon(
                            CupertinoIcons.check_mark,
                            size: 18,
                            color: CupertinoColors.systemBlue,
                          )
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 10),
                        if (p.isDefault)
                          const Icon(
                            CupertinoIcons.lock_fill,
                            size: 18,
                            color: CupertinoColors.secondaryLabel,
                          )
                        else
                          SizedBox(
                            width: 34,
                            height: 34,
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () async {
                                final action =
                                    await showCupertinoModalPopup<String>(
                                  context: context,
                                  builder: (context) {
                                    return CupertinoActionSheet(
                                      actions: [
                                        CupertinoActionSheetAction(
                                          onPressed: () => Navigator.of(context)
                                              .pop('rename'),
                                          child: const Text('重命名'),
                                        ),
                                        CupertinoActionSheetAction(
                                          onPressed: () => Navigator.of(context)
                                              .pop('delete'),
                                          isDestructiveAction: true,
                                          child: const Text('删除'),
                                        ),
                                      ],
                                      cancelButton: CupertinoActionSheetAction(
                                        onPressed: () => Navigator.of(context)
                                            .pop('cancel'),
                                        child: const Text('取消'),
                                      ),
                                    );
                                  },
                                );
                                if (action == null || action == 'cancel') return;
                                if (action == 'rename') {
                                  final name = await askName(
                                    title: '重命名',
                                    initial: p.name,
                                  );
                                  if (name == null) return;
                                  if (!context.mounted) return;
                                  await Future<void>.delayed(Duration.zero);
                                  if (!context.mounted) return;
                                  setLocalState(() {
                                    final next = temp.presets
                                        .map(
                                          (e) => e.id == p.id
                                              ? e.copyWith(name: name)
                                              : e,
                                        )
                                        .toList(growable: false);
                                    temp = temp.copyWith(presets: next);
                                  });
                                }
                                if (action == 'delete') {
                                  await Future<void>.delayed(Duration.zero);
                                  if (!context.mounted) return;
                                  setLocalState(() {
                                    final next = temp.presets
                                        .where((e) => e.id != p.id)
                                        .toList(growable: false);
                                    temp = temp.copyWith(presets: next);
                                  });
                                }
                              },
                              child: const Icon(
                                CupertinoIcons.ellipsis_circle,
                                size: 22,
                                color: CupertinoColors.secondaryLabel,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return CupertinoAlertDialog(
              title: const Text('虚拟手柄配置'),
              content: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxListHeight),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final p in temp.presets) presetTile(p),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        color: CupertinoColors.systemGrey5,
                        borderRadius: BorderRadius.circular(12),
                        onPressed: () async {
                          final name = await askName(
                            title: '新建配置',
                            initial: '${current.name}（副本）',
                          );
                          if (name == null) return;
                          if (!context.mounted) return;
                          setLocalState(() {
                            final id = newId();
                            final next = [
                              ...temp.presets,
                              VirtualGamepadConfigPreset(
                                id: id,
                                name: name,
                                config: current.config,
                                isDefault: false,
                              ),
                            ];
                            temp = temp.copyWith(selectedId: id, presets: next);
                          });
                        },
                        child: const Text(
                          '新建配置',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: CupertinoColors.label,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(temp),
                  isDefaultAction: true,
                  child: const Text('加载'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || !mounted) return;
    if (result.selectedId == selected &&
        result.presets.length == store.presets.length) {
      var same = true;
      for (var i = 0; i < store.presets.length; i++) {
        final a = store.presets[i];
        final b = result.presets[i];
        if (a.id != b.id || a.name != b.name) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    await widget.onSaveStore(result);
  }

  /// 保存草稿到外部，并退出编辑模式。
  Future<void> _saveEdit() async {
    final draft = _draft;
    if (!_editing || draft == null) return;
    final preset = _currentPreset();
    if (preset.isDefault) {
      final result = await showCupertinoDialog<_SaveResult>(
        context: context,
        builder: (context) {
          final controller = TextEditingController(text: '');
          return CupertinoAlertDialog(
            title: const Text('保存为新配置'),
            content: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: CupertinoTextField(
                controller: controller,
                placeholder: '请输入新配置名称',
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  final name = controller.text.trim();
                  Navigator.of(context).pop(_SaveResult(name: name));
                },
              ),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              CupertinoDialogAction(
                onPressed: () {
                  final name = controller.text.trim();
                  Navigator.of(context).pop(_SaveResult(name: name));
                },
                isDefaultAction: true,
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
      if (result == null || !mounted) return;
      final name = result.name.trim();
      if (name.isEmpty) return;
      final id =
          'cfg_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1 << 20)}';
      final nextPresets = [
        ...widget.store.presets,
        VirtualGamepadConfigPreset(
          id: id,
          name: name,
          config: draft,
          isDefault: false,
        ),
      ];
      await widget.onSaveStore(
        widget.store.copyWith(selectedId: id, presets: nextPresets),
      );
    } else {
      final nextPresets = widget.store.presets
          .map((e) => e.id == preset.id ? e.copyWith(config: draft) : e)
          .toList(growable: false);
      await widget.onSaveStore(widget.store.copyWith(presets: nextPresets));
    }
    if (!mounted) return;
    setState(() {
      _editing = false;
      _draft = null;
    });
  }

  /// 编辑普通按钮的映射键位（编辑态）。
  Future<void> _editButtonKey(String buttonId) async {
    if (!_editing) return;
    final cfg = _cfg();
    final idx = cfg.buttons.indexWhere((e) => e.id == buttonId);
    if (idx < 0) return;
    final current = cfg.buttons[idx].logicalKey;
    final picked = await widget.onPickKey(
      context,
      controlId: 'button:$buttonId',
      current: current,
    );
    if (picked == null || picked.isEmpty) return;
    if (!mounted) return;
    final nextButtons = cfg.buttons.toList(growable: true);
    nextButtons[idx] = nextButtons[idx].copyWith(logicalKey: picked);
    setState(() {
      _draft = cfg.copyWith(joysticks: cfg.joysticks, buttons: nextButtons);
    });
  }

  /// 编辑摇杆的四向映射键位（编辑态）。
  Future<void> _editJoystickKeys(String joystickId) async {
    if (!_editing) return;
    final cfg = _cfg();
    final idx = cfg.joysticks.indexWhere((e) => e.id == joystickId);
    if (idx < 0) return;
    final joy = cfg.joysticks[idx];

    var draftUp = joy.up;
    var draftDown = joy.down;
    var draftLeft = joy.left;
    var draftRight = joy.right;

    Future<void> pickDir(String dir) async {
      final current = switch (dir) {
        'up' => draftUp,
        'down' => draftDown,
        'left' => draftLeft,
        'right' => draftRight,
        _ => '',
      };
      final picked = await widget.onPickKey(
        context,
        controlId: 'joystick:$joystickId:$dir',
        current: current,
      );
      if (picked == null || picked.isEmpty) return;
      switch (dir) {
        case 'up':
          draftUp = picked;
          break;
        case 'down':
          draftDown = picked;
          break;
        case 'left':
          draftLeft = picked;
          break;
        case 'right':
          draftRight = picked;
          break;
      }
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Widget row(String label, String dir, String value) {
              final display = value.isEmpty
                  ? '未设置'
                  : _labelForLogicalKey(value);
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CupertinoColors.systemGrey4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: CupertinoColors.secondaryLabel,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CupertinoColors.label,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 30,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          color: CupertinoColors.systemGrey5,
                          borderRadius: BorderRadius.circular(10),
                          onPressed: () async {
                            await pickDir(dir);
                            if (!context.mounted) return;
                            setLocalState(() {});
                          },
                          child: const Text(
                            '选择',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: CupertinoColors.label,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return CupertinoAlertDialog(
              title: const Text('设置摇杆按键'),
              content: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    row('上', 'up', draftUp),
                    const SizedBox(height: 10),
                    row('下', 'down', draftDown),
                    const SizedBox(height: 10),
                    row('左', 'left', draftLeft),
                    const SizedBox(height: 10),
                    row('右', 'right', draftRight),
                  ],
                ),
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(true),
                  isDefaultAction: true,
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;
    final nextJoy = joy.copyWith(
      up: draftUp,
      down: draftDown,
      left: draftLeft,
      right: draftRight,
    );
    final nextJoysticks = cfg.joysticks.toList(growable: true);
    nextJoysticks[idx] = nextJoy;
    setState(() {
      _draft = cfg.copyWith(joysticks: nextJoysticks, buttons: cfg.buttons);
    });
  }

  /// 新增一个普通按钮（编辑态），并立即打开改键。
  Future<void> _addButton(Size size) async {
    if (!_editing) return;
    final cfg = _cfg();
    final id = 'btn_${DateTime.now().millisecondsSinceEpoch}';
    final next = VirtualGamepadButtonConfig(
      id: id,
      shape: VirtualGamepadButtonShape.circle,
      logicalKey: 'z',
      position01: const Offset(0.80, 0.52),
    );
    setState(() {
      _draft = cfg.copyWith(
        joysticks: cfg.joysticks,
        buttons: [...cfg.buttons, next],
      );
    });
    await _editButtonKey(id);
  }

  String _newJoystickId() =>
      'joy_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1 << 20)}';

  Offset _suggestJoystickPosition01(int index) {
    return switch (index % 4) {
      0 => const Offset(0.18, 0.82),
      1 => const Offset(0.82, 0.82),
      2 => const Offset(0.18, 0.62),
      _ => const Offset(0.82, 0.62),
    };
  }

  /// 新增一个摇杆（编辑态）。
  void _addJoystick() {
    if (!_editing) return;
    final cfg = _cfg();
    final base = VirtualGamepadUserConfig.defaults().joysticks.first;
    final idx = cfg.joysticks.length;
    final next = base.copyWith(
      id: _newJoystickId(),
      position01: _suggestJoystickPosition01(idx),
    );
    setState(() {
      _draft = cfg.copyWith(
        joysticks: [...cfg.joysticks, next],
        buttons: cfg.buttons,
      );
    });
  }

  /// 删除一个普通按钮（编辑态）。
  void _removeButton(String buttonId) {
    if (!_editing) return;
    final cfg = _cfg();
    setState(() {
      _draft = cfg.copyWith(
        joysticks: cfg.joysticks,
        buttons: cfg.buttons
            .where((e) => e.id != buttonId)
            .toList(growable: true),
      );
    });
  }

  /// 删除摇杆（编辑态）。
  void _removeJoystick(String joystickId) {
    if (!_editing) return;
    final cfg = _cfg();
    if (cfg.joysticks.isEmpty) return;
    setState(() {
      _draft = cfg.copyWith(
        joysticks: cfg.joysticks
            .where((e) => e.id != joystickId)
            .toList(growable: true),
        buttons: cfg.buttons,
      );
    });
  }

  /// 在编辑态移动控件的归一化位置。
  void _movePosition01({
    required Offset current01,
    required Offset deltaPx,
    required Size size,
    required Offset halfSizePx,
    required void Function(Offset next01) commit,
  }) {
    final currentPx = _centerPx(current01, size);
    final nextPx = Offset(currentPx.dx + deltaPx.dx, currentPx.dy + deltaPx.dy);
    final clampedPx = Offset(
      nextPx.dx.clamp(halfSizePx.dx, size.width - halfSizePx.dx),
      nextPx.dy.clamp(halfSizePx.dy, size.height - halfSizePx.dy),
    );
    commit(Offset(clampedPx.dx / size.width, clampedPx.dy / size.height));
  }

  /// 将归一化位置转换为像素中心点。
  Offset _centerPx(Offset p01, Size size) =>
      Offset(p01.dx * size.width, p01.dy * size.height);

  /// 构建底部工具条：普通态显示“编辑/收起”，编辑态显示“添加摇杆/添加按键/完成”。
  Widget _buildBottomBar(Size size) {
    if (!_editing) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: '配置',
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => unawaited(_openConfigManager()),
                    child: Icon(
                      CupertinoIcons.square_stack_3d_down_right,
                      size: 20,
                      color: CupertinoColors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: '编辑',
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _enterEdit,
                    child: Icon(
                      CupertinoIcons.slider_horizontal_3,
                      size: 20,
                      color: CupertinoColors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: '收起',
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: widget.onToggleVisible,
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 20,
                      color: CupertinoColors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF101010),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _addType = _GamepadAddType.joystick),
                      child: ColoredBox(
                        color: _addType == _GamepadAddType.joystick
                            ? const Color(0xFF2C2C2C)
                            : const Color(0x00000000),
                        child: SizedBox(
                          width: 70,
                          height: 32,
                          child: Center(
                            child: Text(
                              '摇杆',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: CupertinoColors.white.withValues(
                                  alpha: _addType == _GamepadAddType.joystick
                                      ? 0.92
                                      : 0.72,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 1,
                      height: 32,
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _addType = _GamepadAddType.button),
                      child: ColoredBox(
                        color: _addType == _GamepadAddType.button
                            ? const Color(0xFF2C2C2C)
                            : const Color(0x00000000),
                        child: SizedBox(
                          width: 70,
                          height: 32,
                          child: Center(
                            child: Text(
                              '按键',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: CupertinoColors.white.withValues(
                                  alpha: _addType == _GamepadAddType.button
                                      ? 0.92
                                      : 0.72,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              height: 32,
              child: CupertinoButton(
                onPressed: _addType == _GamepadAddType.joystick
                    ? _addJoystick
                    : () => unawaited(_addButton(size)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                color: const Color(0xFF2C2C2C),
                borderRadius: BorderRadius.circular(10),
                child: const Text(
                  '添加',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              height: 32,
              child: CupertinoButton(
                onPressed: () => unawaited(_saveEdit()),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                color: const Color(0xFF3E6BFF),
                borderRadius: BorderRadius.circular(10),
                child: const Text(
                  '完成',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  /// 构建虚拟手柄：底部悬浮层，支持编辑态（拖拽、右上角编辑/删除、添加摇杆/按键）。
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        offset: widget.visible ? Offset.zero : const Offset(0, 1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: widget.visible ? 1 : 0,
          child: SizedBox.expand(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final cfg = _cfg();
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final joy in cfg.joysticks)
                      _positionedSquare(
                        center: _centerPx(joy.position01, size),
                        size: joy.sizePx,
                        child: _editing
                            ? _EditControlsOverlay(
                                onEdit: () =>
                                    unawaited(_editJoystickKeys(joy.id)),
                                onDelete: () => _removeJoystick(joy.id),
                                child: _GamepadStick(
                                  enabled: false,
                                  onMoveControl: (delta) {
                                    final cfgNow = _cfg();
                                    final idx = cfgNow.joysticks.indexWhere(
                                      (e) => e.id == joy.id,
                                    );
                                    if (idx < 0) return;
                                    final currentJoy = cfgNow.joysticks[idx];
                                    _movePosition01(
                                      current01: currentJoy.position01,
                                      deltaPx: delta,
                                      size: size,
                                      halfSizePx: Offset(
                                        currentJoy.sizePx / 2,
                                        currentJoy.sizePx / 2,
                                      ),
                                      commit: (next01) {
                                        final nextJoysticks = cfgNow.joysticks
                                            .toList(growable: true);
                                        nextJoysticks[idx] = currentJoy
                                            .copyWith(position01: next01);
                                        setState(() {
                                          _draft = cfgNow.copyWith(
                                            joysticks: nextJoysticks,
                                            buttons: cfgNow.buttons,
                                          );
                                        });
                                      },
                                    );
                                  },
                                  onKeyDown: widget.onKeyDown,
                                  onKeyUp: widget.onKeyUp,
                                  up: joy.up,
                                  down: joy.down,
                                  left: joy.left,
                                  right: joy.right,
                                  sizePx: joy.sizePx,
                                ),
                              )
                            : _GamepadStick(
                                enabled: true,
                                onMoveControl: null,
                                onKeyDown: widget.onKeyDown,
                                onKeyUp: widget.onKeyUp,
                                up: joy.up,
                                down: joy.down,
                                left: joy.left,
                                right: joy.right,
                                sizePx: joy.sizePx,
                              ),
                      ),
                    for (final btn in cfg.buttons)
                      _buildButton(btn: btn, size: size),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: SafeArea(
                        top: false,
                        left: false,
                        child: _buildBottomBar(size),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 构建一个按钮控件：普通态发送 KeyDown/KeyUp；编辑态支持拖拽与右上角“编辑/删除”。
  Widget _buildButton({
    required VirtualGamepadButtonConfig btn,
    required Size size,
  }) {
    final center = _centerPx(btn.position01, size);
    final base = btn.shape == VirtualGamepadButtonShape.pill
        ? _HoldablePillButton(
            label: _labelForLogicalKey(btn.logicalKey),
            logicalKey: btn.logicalKey,
            enabled: !_editing,
            onKeyDown: widget.onKeyDown,
            onKeyUp: widget.onKeyUp,
            onPan: _editing
                ? (delta) {
                    _movePosition01(
                      current01: btn.position01,
                      deltaPx: delta,
                      size: size,
                      halfSizePx: const Offset(52, 17),
                      commit: (next01) {
                        final cfg = _cfg();
                        final nextButtons = cfg.buttons
                            .map(
                              (e) => e.id == btn.id
                                  ? e.copyWith(position01: next01)
                                  : e,
                            )
                            .toList(growable: true);
                        setState(() {
                          _draft = cfg.copyWith(
                            joysticks: cfg.joysticks,
                            buttons: nextButtons,
                          );
                        });
                      },
                    );
                  }
                : null,
          )
        : _HoldableCircleButton(
            label: _labelForLogicalKey(btn.logicalKey),
            logicalKey: btn.logicalKey,
            enabled: !_editing,
            onKeyDown: widget.onKeyDown,
            onKeyUp: widget.onKeyUp,
            onPan: _editing
                ? (delta) {
                    _movePosition01(
                      current01: btn.position01,
                      deltaPx: delta,
                      size: size,
                      halfSizePx: const Offset(29, 29),
                      commit: (next01) {
                        final cfg = _cfg();
                        final nextButtons = cfg.buttons
                            .map(
                              (e) => e.id == btn.id
                                  ? e.copyWith(position01: next01)
                                  : e,
                            )
                            .toList(growable: true);
                        setState(() {
                          _draft = cfg.copyWith(
                            joysticks: cfg.joysticks,
                            buttons: nextButtons,
                          );
                        });
                      },
                    );
                  }
                : null,
          );
    final child = _editing
        ? _EditControlsOverlay(
            onEdit: () => unawaited(_editButtonKey(btn.id)),
            onDelete: () => _removeButton(btn.id),
            child: base,
          )
        : base;

    if (btn.shape == VirtualGamepadButtonShape.pill) {
      return _positionedPill(center: center, child: child);
    }
    return _positionedSquare(center: center, size: 58, child: child);
  }

  /// 以中心点定位一个正方形控件。
  Widget _positionedSquare({
    required Offset center,
    required double size,
    required Widget child,
  }) {
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      height: size,
      child: child,
    );
  }

  /// 以中心点定位胶囊控件（宽度由子组件决定）。
  Widget _positionedPill({required Offset center, required Widget child}) {
    return Positioned(left: center.dx - 52, top: center.dy - 17, child: child);
  }
}

class _SaveResult {
  final String name;

  const _SaveResult({required this.name});
}
