use ruffle_core::backend::storage::StorageBackend;
use ruffle_frontend_utils::backends::storage::DiskStorageBackend;
use std::path::PathBuf;

/// 根据 SWF URL 生成 SharedObject 的落盘目录。
///
/// - 目录由 Dart 侧通过 path_provider 提供，避免触发存储权限问题（所有平台统一）。
/// - Rust 侧仅在该基础目录下拼接 `ruffle/shared_objects`。
pub fn storage_dir_from_swf_url(_swf_url: &str) -> PathBuf {
    let base = crate::api::init::get_storage_base_dir()
        .unwrap_or_else(|| std::env::temp_dir().join("flutter_ruffle"));
    base.join("ruffle").join("shared_objects")
}

/// 构建 StorageBackend：使用 DiskStorageBackend 落盘保存 SharedObject。
pub(crate) fn make_storage_backend(swf_url: &str) -> Box<dyn StorageBackend> {
    let dir = storage_dir_from_swf_url(swf_url);
    Box::new(DiskStorageBackend::new(dir))
}
