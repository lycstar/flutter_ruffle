#include "include/ruffle/ruffle_plugin.h"

#ifdef __linux__
#include <flutter_linux/flutter_linux.h>

#include <cstdint>
#include <cstring>

namespace {

typedef struct _RufflePixelBufferTexture RufflePixelBufferTexture;
typedef struct _RufflePixelBufferTextureClass RufflePixelBufferTextureClass;

struct _RufflePixelBufferTexture {
  FlPixelBufferTexture parent_instance;

  GMutex mutex;
  GByteArray* rgba;
  uint32_t width;
  uint32_t height;
  gboolean has_frame;
};

struct _RufflePixelBufferTextureClass {
  FlPixelBufferTextureClass parent_class;
};

G_DEFINE_TYPE(RufflePixelBufferTexture,
              ruffle_pixel_buffer_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean ruffle_pixel_buffer_texture_copy_pixels(
    FlPixelBufferTexture* texture,
    const uint8_t** out_buffer,
    uint32_t* width,
    uint32_t* height,
    GError** /*error*/) {
  auto* self = reinterpret_cast<RufflePixelBufferTexture*>(texture);

  static const uint8_t kTransparent1x1[4] = {0, 0, 0, 0};

  g_mutex_lock(&self->mutex);
  if (!self->has_frame || self->rgba == nullptr || self->rgba->len == 0 ||
      self->width == 0 || self->height == 0) {
    *out_buffer = kTransparent1x1;
    *width = 1;
    *height = 1;
    g_mutex_unlock(&self->mutex);
    return TRUE;
  }

  *out_buffer = self->rgba->data;
  *width = self->width;
  *height = self->height;
  g_mutex_unlock(&self->mutex);
  return TRUE;
}

static void ruffle_pixel_buffer_texture_dispose(GObject* object) {
  auto* self = reinterpret_cast<RufflePixelBufferTexture*>(object);
  g_mutex_lock(&self->mutex);
  if (self->rgba != nullptr) {
    g_byte_array_unref(self->rgba);
    self->rgba = nullptr;
  }
  g_mutex_unlock(&self->mutex);
  g_mutex_clear(&self->mutex);
  G_OBJECT_CLASS(ruffle_pixel_buffer_texture_parent_class)->dispose(object);
}

static void ruffle_pixel_buffer_texture_class_init(
    RufflePixelBufferTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      ruffle_pixel_buffer_texture_copy_pixels;
  G_OBJECT_CLASS(klass)->dispose = ruffle_pixel_buffer_texture_dispose;
}

static void ruffle_pixel_buffer_texture_init(RufflePixelBufferTexture* self) {
  g_mutex_init(&self->mutex);
  self->rgba = g_byte_array_new();
  self->width = 0;
  self->height = 0;
  self->has_frame = FALSE;
}

static RufflePixelBufferTexture* ruffle_pixel_buffer_texture_new() {
  return reinterpret_cast<RufflePixelBufferTexture*>(
      g_object_new(ruffle_pixel_buffer_texture_get_type(), nullptr));
}

typedef struct _RuffleTexturePlugin {
  GObject parent_instance;

  FlPluginRegistrar* registrar;
  FlTextureRegistrar* texture_registrar;
  FlMethodChannel* channel;
  GHashTable* textures;
} RuffleTexturePlugin;

typedef struct _RuffleTexturePluginClass {
  GObjectClass parent_class;
} RuffleTexturePluginClass;

G_DEFINE_TYPE(RuffleTexturePlugin,
              ruffle_texture_plugin,
              g_object_get_type())

static RufflePixelBufferTexture* lookup_texture(RuffleTexturePlugin* self,
                                                int64_t texture_id) {
  return reinterpret_cast<RufflePixelBufferTexture*>(
      g_hash_table_lookup(self->textures, GINT_TO_POINTER(texture_id)));
}

static FlMethodResponse* handle_create(RuffleTexturePlugin* self) {
  auto* texture = ruffle_pixel_buffer_texture_new();
  const gboolean ok = fl_texture_registrar_register_texture(
      self->texture_registrar, FL_TEXTURE(texture));
  if (!ok) {
    g_object_unref(texture);
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("register_failed", "register_texture 失败",
                                     nullptr));
  }
  const int64_t id = fl_texture_get_id(FL_TEXTURE(texture));
  g_hash_table_insert(self->textures, GINT_TO_POINTER(id),
                      g_object_ref(texture));
  g_object_unref(texture);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_int(id)));
}

static FlMethodResponse* handle_update_rgba(RuffleTexturePlugin* self,
                                            FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("bad_args", "update_rgba 参数错误", nullptr));
  }

  auto* id_value = fl_value_lookup_string(args, "textureId");
  auto* width_value = fl_value_lookup_string(args, "width");
  auto* height_value = fl_value_lookup_string(args, "height");
  auto* rgba_value = fl_value_lookup_string(args, "rgba");
  if (id_value == nullptr || width_value == nullptr || height_value == nullptr ||
      rgba_value == nullptr) {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("bad_args", "update_rgba 参数缺失", nullptr));
  }

  const int64_t texture_id = fl_value_get_int(id_value);
  const int64_t width64 = fl_value_get_int(width_value);
  const int64_t height64 = fl_value_get_int(height_value);
  if (width64 <= 0 || height64 <= 0) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  const uint32_t width = static_cast<uint32_t>(width64);
  const uint32_t height = static_cast<uint32_t>(height64);

  if (fl_value_get_type(rgba_value) != FL_VALUE_TYPE_UINT8_LIST) {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("bad_args", "rgba 类型错误", nullptr));
  }
  const auto* rgba = fl_value_get_uint8_list(rgba_value);
  const size_t rgba_len = fl_value_get_length(rgba_value);
  const size_t expected = static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
  if (rgba == nullptr || rgba_len != expected) {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("bad_args", "rgba 长度不匹配", nullptr));
  }

  auto* texture = lookup_texture(self, texture_id);
  if (texture == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  g_mutex_lock(&texture->mutex);
  g_byte_array_set_size(texture->rgba, expected);
  std::memcpy(texture->rgba->data, rgba, expected);
  texture->width = width;
  texture->height = height;
  texture->has_frame = TRUE;
  g_mutex_unlock(&texture->mutex);

  fl_texture_registrar_mark_texture_frame_available(self->texture_registrar,
                                                    FL_TEXTURE(texture));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* handle_dispose(RuffleTexturePlugin* self, FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("bad_args", "dispose 参数错误", nullptr));
  }
  auto* id_value = fl_value_lookup_string(args, "textureId");
  if (id_value == nullptr) {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("bad_args", "dispose textureId 缺失", nullptr));
  }
  const int64_t texture_id = fl_value_get_int(id_value);
  auto* texture = lookup_texture(self, texture_id);
  if (texture == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  fl_texture_registrar_unregister_texture(self->texture_registrar,
                                          FL_TEXTURE(texture));
  g_hash_table_remove(self->textures, GINT_TO_POINTER(texture_id));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static void method_call_cb(FlMethodChannel* /*channel*/,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  auto* self = reinterpret_cast<RuffleTexturePlugin*>(user_data);

  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (std::strcmp(method, "create") == 0) {
    response = handle_create(self);
  } else if (std::strcmp(method, "update_rgba") == 0) {
    response = handle_update_rgba(self, args);
  } else if (std::strcmp(method, "dispose") == 0) {
    response = handle_dispose(self, args);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void ruffle_texture_plugin_dispose(GObject* object) {
  auto* self = reinterpret_cast<RuffleTexturePlugin*>(object);
  if (self->channel != nullptr) {
    fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                              nullptr);
    g_clear_object(&self->channel);
  }
  if (self->textures != nullptr) {
    g_hash_table_unref(self->textures);
    self->textures = nullptr;
  }
  g_clear_object(&self->texture_registrar);
  g_clear_object(&self->registrar);
  G_OBJECT_CLASS(ruffle_texture_plugin_parent_class)->dispose(object);
}

static void ruffle_texture_plugin_class_init(RuffleTexturePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = ruffle_texture_plugin_dispose;
}

static void ruffle_texture_plugin_init(RuffleTexturePlugin* /*self*/) {}

static RuffleTexturePlugin* ruffle_texture_plugin_new(FlPluginRegistrar* registrar) {
  auto* self = reinterpret_cast<RuffleTexturePlugin*>(
      g_object_new(ruffle_texture_plugin_get_type(), nullptr));

  self->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));
  self->texture_registrar = FL_TEXTURE_REGISTRAR(
      g_object_ref(fl_plugin_registrar_get_texture_registrar(registrar)));
  self->textures =
      g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr, g_object_unref);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                                        "ruffle/texture",
                                        FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb,
                                            g_object_ref(self), g_object_unref);
  return self;
}

}  // namespace

void ruffle_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  auto* plugin = ruffle_texture_plugin_new(registrar);
  g_object_unref(plugin);
}
#else
typedef struct _FlPluginRegistrar FlPluginRegistrar;

void ruffle_plugin_register_with_registrar(FlPluginRegistrar* /*registrar*/) {}
#endif
