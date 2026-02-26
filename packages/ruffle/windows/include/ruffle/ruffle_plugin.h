#ifndef FLUTTER_PLUGIN_RUFFLE_PLUGIN_H_
#define FLUTTER_PLUGIN_RUFFLE_PLUGIN_H_

namespace ruffle {
struct FlutterDesktopPluginRegistrar;
using FlutterDesktopPluginRegistrarRef = FlutterDesktopPluginRegistrar*;

void RufflePluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar);

}  // namespace ruffle

#endif  // FLUTTER_PLUGIN_RUFFLE_PLUGIN_H_
