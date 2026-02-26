export 'src/rust/api/core.dart';
export 'src/rust/api/player.dart';
export 'src/rust/frb_generated.dart' show RustLib;
export 'src/texture/ruffle_texture.dart';
export 'src/backends/navigator.dart';

import 'src/rust/frb_generated.dart';

/// 初始化 Rust 侧运行环境，并可选设置 SharedObject 等落盘的基础目录（由 Flutter 的 path_provider 提供）。
Future<void> initRust({String? storageBaseDir}) async {
  await RustLib.init();
  final base = storageBaseDir;
  if (base != null && base.isNotEmpty) {
    RustLib.instance.api.crateApiInitSetStorageBaseDir(path: base);
  }
}
