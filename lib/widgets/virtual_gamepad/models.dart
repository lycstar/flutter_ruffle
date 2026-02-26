part of '../virtual_gamepad.dart';

class VirtualGamepadConfigPreset {
  final String id;
  final String name;
  final VirtualGamepadUserConfig config;
  final bool isDefault;

  const VirtualGamepadConfigPreset({
    required this.id,
    required this.name,
    required this.config,
    required this.isDefault,
  });

  /// 从 JSON 反序列化配置预设（字段缺失时会抛异常，由上层兜底处理）。
  factory VirtualGamepadConfigPreset.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final cfgRaw = json['config'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('preset.id invalid');
    }
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('preset.name invalid');
    }
    if (cfgRaw is! Map) {
      throw const FormatException('preset.config invalid');
    }
    final cfg = VirtualGamepadUserConfig.fromJson(
      Map<String, Object?>.from(cfgRaw),
    );
    return VirtualGamepadConfigPreset(
      id: id,
      name: name.trim(),
      config: cfg,
      isDefault: false,
    );
  }

  /// 序列化为 JSON（用于本地持久化，不包含默认标记）。
  Map<String, Object?> toJson() {
    return <String, Object?>{'id': id, 'name': name, 'config': config.toJson()};
  }

  /// 派生一个新预设（修改名称或配置）。
  VirtualGamepadConfigPreset copyWith({
    String? name,
    VirtualGamepadUserConfig? config,
  }) {
    return VirtualGamepadConfigPreset(
      id: id,
      name: name ?? this.name,
      config: config ?? this.config,
      isDefault: isDefault,
    );
  }
}

class VirtualGamepadConfigStore {
  final String selectedId;
  final List<VirtualGamepadConfigPreset> presets;

  const VirtualGamepadConfigStore({
    required this.selectedId,
    required this.presets,
  });

  /// 创建默认配置集合：内置“默认”预设（不可删除）。
  factory VirtualGamepadConfigStore.defaults() {
    const defaultId = 'default';
    final defaultPreset = VirtualGamepadConfigPreset(
      id: defaultId,
      name: '默认',
      config: VirtualGamepadUserConfig.defaults(),
      isDefault: true,
    );
    return VirtualGamepadConfigStore(
      selectedId: defaultId,
      presets: [defaultPreset],
    );
  }

  /// 从 JSON 反序列化配置集合（字段缺失/解析失败会回退到默认集合）。
  factory VirtualGamepadConfigStore.fromJson(Map<String, Object?> json) {
    final defaults = VirtualGamepadConfigStore.defaults();
    final selectedRaw = json['selectedId'];
    final selectedId = selectedRaw is String && selectedRaw.isNotEmpty
        ? selectedRaw
        : defaults.selectedId;

    final seen = <String>{defaults.presets.first.id};
    final loaded = <VirtualGamepadConfigPreset>[];
    final presetsRaw = json['presets'];
    if (presetsRaw is List) {
      for (final item in presetsRaw) {
        if (item is! Map) continue;
        try {
          final preset = VirtualGamepadConfigPreset.fromJson(
            Map<String, Object?>.from(item),
          );
          if (preset.id == 'default') continue;
          if (!seen.add(preset.id)) continue;
          loaded.add(preset);
        } catch (_) {}
      }
    }

    final all = [defaults.presets.first, ...loaded];
    final effectiveSelected = all.any((e) => e.id == selectedId)
        ? selectedId
        : defaults.selectedId;
    return VirtualGamepadConfigStore(
      selectedId: effectiveSelected,
      presets: all,
    );
  }

  /// 序列化为 JSON（用于本地持久化，仅保存用户预设）。
  Map<String, Object?> toJson() {
    final userPresets = presets
        .where((e) => !e.isDefault)
        .map((e) => e.toJson())
        .toList();
    return <String, Object?>{'selectedId': selectedId, 'presets': userPresets};
  }

  /// 获取当前选中的预设（找不到则回退到默认）。
  VirtualGamepadConfigPreset currentPreset() {
    for (final p in presets) {
      if (p.id == selectedId) return p;
    }
    return presets.first;
  }

  /// 派生一个新集合（用于保存选择/增删改）。
  VirtualGamepadConfigStore copyWith({
    String? selectedId,
    List<VirtualGamepadConfigPreset>? presets,
  }) {
    final nextSelected = selectedId ?? this.selectedId;
    final nextPresets = presets ?? this.presets;
    final effectiveSelected = nextPresets.any((e) => e.id == nextSelected)
        ? nextSelected
        : nextPresets.first.id;
    return VirtualGamepadConfigStore(
      selectedId: effectiveSelected,
      presets: nextPresets,
    );
  }
}

class VirtualGamepadButtonConfig {
  final String id;
  final VirtualGamepadButtonShape shape;
  final String logicalKey;
  final Offset position01;

  const VirtualGamepadButtonConfig({
    required this.id,
    required this.shape,
    required this.logicalKey,
    required this.position01,
  });

  /// 从 JSON 反序列化按钮配置（字段缺失时会抛异常，由上层兜底处理）。
  factory VirtualGamepadButtonConfig.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final logicalKey = json['logicalKey'];
    final shapeRaw = json['shape'];
    final posRaw = json['position'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('button.id invalid');
    }
    if (logicalKey is! String || logicalKey.isEmpty) {
      throw const FormatException('button.logicalKey invalid');
    }
    if (shapeRaw is! String) {
      throw const FormatException('button.shape invalid');
    }
    final shape = switch (shapeRaw) {
      'circle' => VirtualGamepadButtonShape.circle,
      'pill' => VirtualGamepadButtonShape.pill,
      _ => throw const FormatException('button.shape unknown'),
    };
    if (posRaw is! Map) {
      throw const FormatException('button.position invalid');
    }
    final x = posRaw['x'];
    final y = posRaw['y'];
    if (x is! num || y is! num) {
      throw const FormatException('button.position invalid');
    }
    final dx = x.toDouble();
    final dy = y.toDouble();
    return VirtualGamepadButtonConfig(
      id: id,
      shape: shape,
      logicalKey: logicalKey,
      position01: Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0)),
    );
  }

  /// 序列化为 JSON（用于本地持久化）。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'shape': shape == VirtualGamepadButtonShape.circle ? 'circle' : 'pill',
      'logicalKey': logicalKey,
      'position': <String, double>{'x': position01.dx, 'y': position01.dy},
    };
  }

  /// 派生一个新配置（编辑态修改位置/键位/形状）。
  VirtualGamepadButtonConfig copyWith({
    VirtualGamepadButtonShape? shape,
    String? logicalKey,
    Offset? position01,
  }) {
    return VirtualGamepadButtonConfig(
      id: id,
      shape: shape ?? this.shape,
      logicalKey: logicalKey ?? this.logicalKey,
      position01: position01 ?? this.position01,
    );
  }
}

class VirtualGamepadJoystickConfig {
  final String id;
  final String up;
  final String down;
  final String left;
  final String right;
  final Offset position01;
  final double sizePx;

  const VirtualGamepadJoystickConfig({
    required this.id,
    required this.up,
    required this.down,
    required this.left,
    required this.right,
    required this.position01,
    required this.sizePx,
  });

  /// 从 JSON 反序列化摇杆配置（字段缺失时会抛异常，由上层兜底处理）。
  factory VirtualGamepadJoystickConfig.fromJson(Map<String, Object?> json) {
    String readKey(String key) {
      final v = json[key];
      if (v is! String || v.isEmpty) {
        throw FormatException('joystick.$key invalid');
      }
      return v;
    }

    final idRaw = json['id'];
    final id = idRaw is String && idRaw.trim().isNotEmpty ? idRaw.trim() : '';
    final posRaw = json['position'];
    if (posRaw is! Map) {
      throw const FormatException('joystick.position invalid');
    }
    final x = posRaw['x'];
    final y = posRaw['y'];
    if (x is! num || y is! num) {
      throw const FormatException('joystick.position invalid');
    }
    final size = json['sizePx'];
    final sizePx = (size is num ? size.toDouble() : 120.0).clamp(80.0, 220.0);
    return VirtualGamepadJoystickConfig(
      id: id,
      up: readKey('up'),
      down: readKey('down'),
      left: readKey('left'),
      right: readKey('right'),
      position01: Offset(
        x.toDouble().clamp(0.0, 1.0),
        y.toDouble().clamp(0.0, 1.0),
      ),
      sizePx: sizePx,
    );
  }

  /// 序列化为 JSON（用于本地持久化）。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'up': up,
      'down': down,
      'left': left,
      'right': right,
      'sizePx': sizePx,
      'position': <String, double>{'x': position01.dx, 'y': position01.dy},
    };
  }

  /// 派生一个新配置（编辑态修改位置/键位/尺寸）。
  VirtualGamepadJoystickConfig copyWith({
    String? id,
    String? up,
    String? down,
    String? left,
    String? right,
    Offset? position01,
    double? sizePx,
  }) {
    return VirtualGamepadJoystickConfig(
      id: id ?? this.id,
      up: up ?? this.up,
      down: down ?? this.down,
      left: left ?? this.left,
      right: right ?? this.right,
      position01: position01 ?? this.position01,
      sizePx: sizePx ?? this.sizePx,
    );
  }
}

class VirtualGamepadUserConfig {
  final List<VirtualGamepadJoystickConfig> joysticks;
  final List<VirtualGamepadButtonConfig> buttons;
  static const Object _noChange = Object();

  const VirtualGamepadUserConfig({
    required this.joysticks,
    required this.buttons,
  });

  /// 创建默认配置：仅包含摇杆（更简洁，避免与底部工具条或游戏内容重叠）。
  factory VirtualGamepadUserConfig.defaults() {
    return VirtualGamepadUserConfig(
      joysticks: const [
        VirtualGamepadJoystickConfig(
          id: 'j0',
          up: 'ArrowUp',
          down: 'ArrowDown',
          left: 'ArrowLeft',
          right: 'ArrowRight',
          position01: Offset(0.18, 0.82),
          sizePx: 120,
        ),
      ],
      buttons: const [],
    );
  }

  /// 从 JSON 反序列化配置（字段缺失/解析失败会回退到默认配置）。
  factory VirtualGamepadUserConfig.fromJson(Map<String, Object?> json) {
    final defaults = VirtualGamepadUserConfig.defaults();

    List<VirtualGamepadJoystickConfig> joysticks;
    if (json.containsKey('joysticks')) {
      joysticks = <VirtualGamepadJoystickConfig>[];
      final seen = <String>{};
      final raw = json['joysticks'];
      if (raw is List) {
        for (var i = 0; i < raw.length; i++) {
          final item = raw[i];
          if (item is! Map) continue;
          try {
            final parsed = VirtualGamepadJoystickConfig.fromJson(
              Map<String, Object?>.from(item),
            );
            final id = parsed.id.isEmpty ? 'j$i' : parsed.id;
            if (!seen.add(id)) continue;
            joysticks.add(parsed.copyWith(id: id));
          } catch (_) {}
        }
      }
    } else if (json.containsKey('joystick')) {
      final raw = json['joystick'];
      if (raw is Map<String, Object?>) {
        try {
          final parsed = VirtualGamepadJoystickConfig.fromJson(raw);
          joysticks = [
            parsed.copyWith(id: parsed.id.isEmpty ? 'j0' : parsed.id),
          ];
        } catch (_) {
          joysticks = defaults.joysticks;
        }
      } else {
        joysticks = const [];
      }
    } else {
      joysticks = defaults.joysticks;
    }

    List<VirtualGamepadButtonConfig> buttons;
    if (json.containsKey('buttons')) {
      buttons = <VirtualGamepadButtonConfig>[];
      final buttonsRaw = json['buttons'];
      if (buttonsRaw is List) {
        for (final item in buttonsRaw) {
          if (item is! Map) continue;
          final typed = Map<String, Object?>.from(item);
          try {
            buttons.add(VirtualGamepadButtonConfig.fromJson(typed));
          } catch (_) {}
        }
      }
    } else {
      buttons = defaults.buttons;
    }

    return VirtualGamepadUserConfig(joysticks: joysticks, buttons: buttons);
  }

  /// 序列化为 JSON（用于本地持久化）。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'joysticks': joysticks.map((e) => e.toJson()).toList(growable: false),
      'buttons': buttons.map((e) => e.toJson()).toList(growable: false),
    };
  }

  /// 派生一个新配置（编辑态保存）。
  VirtualGamepadUserConfig copyWith({
    Object? joysticks = _noChange,
    List<VirtualGamepadButtonConfig>? buttons,
  }) {
    return VirtualGamepadUserConfig(
      joysticks: identical(joysticks, _noChange)
          ? this.joysticks
          : joysticks as List<VirtualGamepadJoystickConfig>,
      buttons: buttons ?? this.buttons,
    );
  }
}

typedef GamepadPickKey = Future<String?> Function(
  BuildContext context, {
  required String controlId,
  required String current,
});

typedef GamepadSaveStore = Future<void> Function(VirtualGamepadConfigStore store);
