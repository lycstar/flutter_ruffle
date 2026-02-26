import 'package:flutter/material.dart';

class PlayerHud extends StatelessWidget {
  final double? fps;

  const PlayerHud({
    super.key,
    required this.fps,
  });

  @override
  /// 构建 FPS 浮层（默认显示）。
  Widget build(BuildContext context) {
    final label = fps == null || fps! <= 0 ? '帧率：--' : '帧率：${fps!.toStringAsFixed(1)}';

    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment.topLeft,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.25,
                  ),
                  child: Text(label),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
