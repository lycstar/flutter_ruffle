use std::sync::OnceLock;
use std::{fs, path::PathBuf, sync::RwLock};

static TOKIO_RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
static STORAGE_BASE_DIR: OnceLock<RwLock<Option<PathBuf>>> = OnceLock::new();

#[flutter_rust_bridge::frb(init)]
/// 初始化 Rust 侧运行环境（包含 tokio runtime，供网络/Socket/Navigator 后端使用）。
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    let _ = TOKIO_RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("tokio runtime should be created")
    });
}

/// 进入全局 tokio runtime 上下文，使 tokio::spawn 等 API 可在当前线程使用。
pub(crate) fn enter_tokio() -> tokio::runtime::EnterGuard<'static> {
    let rt = TOKIO_RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("tokio runtime should be created")
    });
    rt.handle().enter()
}

#[flutter_rust_bridge::frb(sync)]
/// 设置 SharedObject 等落盘的基础目录（由 Flutter 的 path_provider 提供，避免权限问题）。
pub fn set_storage_base_dir(path: String) -> anyhow::Result<()> {
    let base = PathBuf::from(path);
    fs::create_dir_all(&base)?;
    let lock = STORAGE_BASE_DIR.get_or_init(|| RwLock::new(None));
    let mut guard = lock
        .write()
        .map_err(|_| anyhow::anyhow!("storage base dir lock poisoned"))?;
    *guard = Some(base);
    Ok(())
}

pub(crate) fn get_storage_base_dir() -> Option<PathBuf> {
    STORAGE_BASE_DIR
        .get()
        .and_then(|lock| lock.read().ok().and_then(|g| g.clone()))
}
