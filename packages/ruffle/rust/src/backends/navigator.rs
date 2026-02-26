use ruffle_core::backend::navigator::{NavigatorBackend, NullExecutor, NullSpawner};
use ruffle_core::loader::Error;
use ruffle_frontend_utils::backends::navigator::{
    ExternalNavigatorBackend, FutureSpawner, NavigatorInterface,
};
use ruffle_frontend_utils::content::{ContentDescriptor, PlayingContent};
use std::collections::HashMap;
use std::collections::HashSet;
use std::fs::File;
use std::io;
use std::path::Path;
use std::rc::Rc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use tokio::sync::oneshot;
use url::Url;

static PENDING_EXTERNAL_URLS: OnceLock<Mutex<Vec<String>>> = OnceLock::new();
static PENDING_SOCKET_REQUESTS: OnceLock<Mutex<Vec<PendingSocketRequest>>> = OnceLock::new();
static SOCKET_CONFIRM_WAITERS: OnceLock<Mutex<HashMap<u64, oneshot::Sender<bool>>>> =
    OnceLock::new();
static SOCKET_REQUEST_ID_ALLOC: AtomicU64 = AtomicU64::new(1);

#[derive(Clone, Debug)]
pub(crate) struct PendingSocketRequest {
    pub request_id: u64,
    pub host: String,
    pub port: u16,
}

/// 将 SWF 触发的外部链接打开请求加入队列，等待 Flutter 侧弹窗确认后再处理。
fn push_pending_external_url(url: Url) {
    let lock = PENDING_EXTERNAL_URLS.get_or_init(|| Mutex::new(Vec::new()));
    if let Ok(mut guard) = lock.lock() {
        guard.push(url.to_string());
    }
}

/// 取出（并清空）等待处理的外部链接打开请求。
pub(crate) fn drain_pending_external_urls() -> Vec<String> {
    let lock = PENDING_EXTERNAL_URLS.get_or_init(|| Mutex::new(Vec::new()));
    let mut guard = lock.lock().unwrap();
    std::mem::take(&mut *guard)
}

fn alloc_socket_request_id() -> u64 {
    SOCKET_REQUEST_ID_ALLOC.fetch_add(1, Ordering::Relaxed)
}

fn push_pending_socket_request(host: &str, port: u16) -> (u64, oneshot::Receiver<bool>) {
    let request_id = alloc_socket_request_id();
    let lock = PENDING_SOCKET_REQUESTS.get_or_init(|| Mutex::new(Vec::new()));
    {
        let mut guard = lock.lock().unwrap();
        guard.push(PendingSocketRequest {
            request_id,
            host: host.to_string(),
            port,
        });
    }

    let (tx, rx) = oneshot::channel();
    let waiters = SOCKET_CONFIRM_WAITERS.get_or_init(|| Mutex::new(HashMap::new()));
    {
        let mut guard = waiters.lock().unwrap();
        guard.insert(request_id, tx);
    }
    (request_id, rx)
}

/// 取出（并清空）等待处理的 Socket 连接确认请求。
pub(crate) fn drain_pending_socket_requests() -> Vec<PendingSocketRequest> {
    let lock = PENDING_SOCKET_REQUESTS.get_or_init(|| Mutex::new(Vec::new()));
    let mut guard = lock.lock().unwrap();
    std::mem::take(&mut *guard)
}

/// 对指定的 Socket 连接确认请求进行应答（allow/deny），并返回是否成功找到该请求。
pub(crate) fn resolve_pending_socket_request(request_id: u64, allow: bool) -> bool {
    let waiters = SOCKET_CONFIRM_WAITERS.get_or_init(|| Mutex::new(HashMap::new()));
    let tx = {
        let mut guard = waiters.lock().unwrap();
        guard.remove(&request_id)
    };
    let Some(tx) = tx else {
        return false;
    };
    let _ = tx.send(allow);
    true
}

struct NullExecutorFutureSpawner {
    spawner: NullSpawner,
}

impl NullExecutorFutureSpawner {
    fn new(spawner: NullSpawner) -> Self {
        Self { spawner }
    }
}

impl FutureSpawner<Error> for NullExecutorFutureSpawner {
    fn spawn(&self, future: ruffle_core::backend::navigator::OwnedFuture<(), Error>) {
        self.spawner.spawn_local(future);
    }
}

#[derive(Clone)]
struct DefaultNavigatorInterface {}

impl NavigatorInterface for DefaultNavigatorInterface {
    fn navigate_to_website(&self, url: Url) {
        push_pending_external_url(url);
    }

    async fn open_file(&self, path: &Path) -> io::Result<File> {
        File::open(path)
    }

    async fn confirm_socket(&self, host: &str, port: u16) -> bool {
        let (_, rx) = push_pending_socket_request(host, port);
        rx.await.unwrap_or(false)
    }
}

/// 构建对齐 ruffle-android 的 ExternalNavigatorBackend（支持网络 fetch、Socket、打开 URL）。
pub(crate) fn make_navigator_backend(
    swf_url: &str,
    executor: &NullExecutor,
) -> impl NavigatorBackend {
    let base_url = Url::parse(swf_url).unwrap_or_else(|_| Url::parse("file://movie.swf").unwrap());
    let playing_content = Rc::new(PlayingContent::DirectFile(content_descriptor_from_url(
        &base_url,
    )));
    ExternalNavigatorBackend::new(
        base_url,
        None,
        None,
        NullExecutorFutureSpawner::new(executor.spawner()),
        None,
        true,
        HashSet::new(),
        ruffle_core::backend::navigator::SocketMode::Ask,
        playing_content,
        DefaultNavigatorInterface {},
    )
}

fn content_descriptor_from_url(url: &Url) -> ContentDescriptor {
    if url.scheme() == "file" {
        if let Ok(path) = url.to_file_path() {
            let root = path.parent().map(|p| p.to_path_buf());
            if let Some(desc) = ContentDescriptor::new_local(&path, root) {
                return desc;
            }
        }
    }
    ContentDescriptor::new_remote(url.clone())
}
