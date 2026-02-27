#ifndef FLUTTER_PLUGIN_RUFFLE_PLUGIN_H_
#define FLUTTER_PLUGIN_RUFFLE_PLUGIN_H_

#ifdef __linux__
#include <flutter_linux/flutter_linux.h>
#include <glib-object.h>
#else
typedef struct _FlPluginRegistrar FlPluginRegistrar;
#define G_BEGIN_DECLS
#define G_END_DECLS
#endif

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

G_BEGIN_DECLS

/// 注册 Linux 平台插件：提供 PixelBufferTexture 的创建/更新/销毁能力。
FLUTTER_PLUGIN_EXPORT void ruffle_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_RUFFLE_PLUGIN_H_
