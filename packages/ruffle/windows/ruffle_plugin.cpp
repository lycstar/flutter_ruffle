#include "include/ruffle/ruffle_plugin.h"

#ifdef _WIN32

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

namespace {

class RufflePixelBufferTexture : public flutter::PixelBufferTexture {
 public:
  /// 更新当前纹理帧（输入像素格式：RGBA8888；平台纹理格式：BGRA8888）。
  void UpdateRgba(const uint8_t* rgba, size_t byte_length, int width, int height) {
    if (width <= 0 || height <= 0) return;
    const size_t expected = static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
    if (byte_length != expected) return;

    std::lock_guard<std::mutex> guard(mutex_);
    bgra_.resize(expected);
    for (size_t i = 0; i < expected; i += 4) {
      const uint8_t r = rgba[i + 0];
      const uint8_t g = rgba[i + 1];
      const uint8_t b = rgba[i + 2];
      const uint8_t a = rgba[i + 3];
      bgra_[i + 0] = b;
      bgra_[i + 1] = g;
      bgra_[i + 2] = r;
      bgra_[i + 3] = a;
    }
    buffer_.buffer = bgra_.data();
    buffer_.width = static_cast<size_t>(width);
    buffer_.height = static_cast<size_t>(height);
  }

  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t /*width*/, size_t /*height*/) override {
    std::lock_guard<std::mutex> guard(mutex_);
    if (buffer_.buffer == nullptr) return nullptr;
    return &buffer_;
  }

 private:
  std::mutex mutex_;
  std::vector<uint8_t> bgra_;
  FlutterDesktopPixelBuffer buffer_ = {};
};

class TexturePluginState {
 public:
  explicit TexturePluginState(flutter::TextureRegistrar* registrar) : texture_registrar_(registrar) {}

  /// 创建纹理并返回 textureId。
  int64_t Create() {
    auto texture = std::make_unique<RufflePixelBufferTexture>();
    auto variant = flutter::TextureVariant(*texture);
    const int64_t id = texture_registrar_->RegisterTexture(&variant);

    std::lock_guard<std::mutex> guard(mutex_);
    textures_.emplace(id, std::move(texture));
    variants_.emplace(id, std::move(variant));
    return id;
  }

  /// 更新纹理帧并通知 Flutter 可用新帧。
  void UpdateRgba(int64_t texture_id, const uint8_t* rgba, size_t len, int width, int height) {
    RufflePixelBufferTexture* texture = nullptr;
    {
      std::lock_guard<std::mutex> guard(mutex_);
      auto it = textures_.find(texture_id);
      if (it == textures_.end()) return;
      texture = it->second.get();
    }
    texture->UpdateRgba(rgba, len, width, height);
    texture_registrar_->MarkTextureFrameAvailable(texture_id);
  }

  /// 释放纹理。
  void Dispose(int64_t texture_id) {
    {
      std::lock_guard<std::mutex> guard(mutex_);
      textures_.erase(texture_id);
      variants_.erase(texture_id);
    }
    texture_registrar_->UnregisterTexture(texture_id);
  }

 private:
  flutter::TextureRegistrar* texture_registrar_;
  std::mutex mutex_;
  std::unordered_map<int64_t, std::unique_ptr<RufflePixelBufferTexture>> textures_;
  std::unordered_map<int64_t, flutter::TextureVariant> variants_;
};

class RuffleTexturePlugin : public flutter::Plugin {
 public:
  RuffleTexturePlugin(flutter::PluginRegistrarWindows* registrar, flutter::TextureRegistrar* texture_registrar)
      : state_(std::make_unique<TexturePluginState>(texture_registrar)),
        channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "ruffle/texture", &flutter::StandardMethodCodec::GetInstance())) {
    channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
          HandleMethodCall(call, std::move(result));
        });
  }

  virtual ~RuffleTexturePlugin() = default;

 private:
  /// 处理纹理相关 MethodChannel 调用。
  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const auto& method = call.method_name();
    if (method == "create") {
      result->Success(flutter::EncodableValue(state_->Create()));
      return;
    }
    if (method == "update_rgba") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (!args) {
        result->Error("bad_args", "update_rgba 参数错误");
        return;
      }

      auto read_i64 = [&](const char* key, int64_t* out) -> bool {
        auto it = args->find(flutter::EncodableValue(key));
        if (it == args->end()) return false;
        if (const auto* v = std::get_if<int64_t>(&it->second)) {
          *out = *v;
          return true;
        }
        if (const auto* v = std::get_if<int32_t>(&it->second)) {
          *out = *v;
          return true;
        }
        return false;
      };

      int64_t texture_id = 0;
      int64_t width = 0;
      int64_t height = 0;
      if (!read_i64("textureId", &texture_id) || !read_i64("width", &width) || !read_i64("height", &height)) {
        result->Error("bad_args", "update_rgba 参数缺失");
        return;
      }
      auto it = args->find(flutter::EncodableValue("rgba"));
      if (it == args->end()) {
        result->Error("bad_args", "update_rgba rgba 缺失");
        return;
      }
      const auto* bytes = std::get_if<std::vector<uint8_t>>(&it->second);
      if (!bytes) {
        result->Error("bad_args", "update_rgba rgba 类型错误");
        return;
      }
      state_->UpdateRgba(texture_id, bytes->data(), bytes->size(), static_cast<int>(width),
                         static_cast<int>(height));
      result->Success();
      return;
    }
    if (method == "dispose") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (!args) {
        result->Error("bad_args", "dispose 参数错误");
        return;
      }
      int64_t texture_id = 0;
      auto it = args->find(flutter::EncodableValue("textureId"));
      if (it == args->end()) {
        result->Error("bad_args", "dispose textureId 缺失");
        return;
      }
      if (const auto* v = std::get_if<int64_t>(&it->second)) {
        texture_id = *v;
      } else if (const auto* v = std::get_if<int32_t>(&it->second)) {
        texture_id = *v;
      } else {
        result->Error("bad_args", "dispose textureId 类型错误");
        return;
      }
      state_->Dispose(texture_id);
      result->Success();
      return;
    }
    result->NotImplemented();
  }

  std::unique_ptr<TexturePluginState> state_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace

namespace ruffle {

void RufflePluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar_ref) {
  auto registrar = flutter::PluginRegistrarManager::GetInstance()
                       ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar_ref);
  auto* texture_registrar = registrar->texture_registrar();
  registrar->AddPlugin(std::make_unique<RuffleTexturePlugin>(registrar, texture_registrar));
}

}  // namespace ruffle

#else

namespace ruffle {
void RufflePluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef /*registrar*/) {}
}  // namespace ruffle

#endif
