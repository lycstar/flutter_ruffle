use crate::backends::navigator as navigator_backend;

#[derive(Clone, Debug)]
pub struct PendingSocketRequestInfo {
    pub request_id: u64,
    pub host: String,
    pub port: u16,
}

#[flutter_rust_bridge::frb(sync)]
/// 取出（并清空）等待处理的外部链接打开请求。
pub fn navigator_drain_pending_external_urls() -> Vec<String> {
    navigator_backend::drain_pending_external_urls()
}

#[flutter_rust_bridge::frb(sync)]
/// 取出（并清空）等待处理的 Socket 连接确认请求。
pub fn navigator_drain_pending_socket_requests() -> Vec<PendingSocketRequestInfo> {
    navigator_backend::drain_pending_socket_requests()
        .into_iter()
        .map(|r| PendingSocketRequestInfo {
            request_id: r.request_id,
            host: r.host,
            port: r.port,
        })
        .collect()
}

#[flutter_rust_bridge::frb(sync)]
/// 对指定的 Socket 连接确认请求进行应答（allow/deny），并返回是否成功找到该请求。
pub fn navigator_resolve_pending_socket_request(request_id: u64, allow: bool) -> bool {
    navigator_backend::resolve_pending_socket_request(request_id, allow)
}
