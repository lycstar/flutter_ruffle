#ifndef FLUTTER_PLUGIN_RUFFLE_PLUGIN_H_
#define FLUTTER_PLUGIN_RUFFLE_PLUGIN_H_

#ifdef _WIN32
#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif
#else
typedef void* FlutterDesktopPluginRegistrarRef;
#define FLUTTER_PLUGIN_EXPORT
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void RufflePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_RUFFLE_PLUGIN_H_
