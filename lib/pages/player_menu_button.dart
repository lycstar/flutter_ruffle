import 'package:flutter/cupertino.dart';

enum PlayerMenuAction { reload, quality, scaleMode, exit }

class PlayerMenuButton extends StatelessWidget {
  final VoidCallback onReload;
  final VoidCallback onPickQuality;
  final VoidCallback onPickScaleMode;
  final VoidCallback onExit;

  const PlayerMenuButton({
    super.key,
    required this.onReload,
    required this.onPickQuality,
    required this.onPickScaleMode,
    required this.onExit,
  });

  @override
  /// 构建右上角菜单按钮（播放器功能入口）。
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () async {
        final action = await showCupertinoModalPopup<PlayerMenuAction>(
          context: context,
          builder: (context) {
            return CupertinoActionSheet(
              actions: [
                CupertinoActionSheetAction(
                  onPressed: () =>
                      Navigator.of(context).pop(PlayerMenuAction.reload),
                  child: const Text('重新加载'),
                ),
                CupertinoActionSheetAction(
                  onPressed: () =>
                      Navigator.of(context).pop(PlayerMenuAction.quality),
                  child: const Text('画质'),
                ),
                CupertinoActionSheetAction(
                  onPressed: () =>
                      Navigator.of(context).pop(PlayerMenuAction.scaleMode),
                  child: const Text('缩放模式'),
                ),
                CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(context).pop(PlayerMenuAction.exit),
                  isDestructiveAction: true,
                  child: const Text('退出'),
                ),
              ],
              cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            );
          },
        );
        switch (action) {
          case PlayerMenuAction.reload:
            onReload();
            return;
          case PlayerMenuAction.quality:
            onPickQuality();
            return;
          case PlayerMenuAction.scaleMode:
            onPickScaleMode();
            return;
          case PlayerMenuAction.exit:
            onExit();
            return;
          case null:
            return;
        }
      },
      child: const Icon(
        CupertinoIcons.ellipsis_vertical,
        color: CupertinoColors.white,
        size: 20,
      ),
    );
  }
}
