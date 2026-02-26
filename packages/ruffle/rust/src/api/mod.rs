pub mod backends;
pub mod core;
pub mod init;
pub mod player;

use ruffle_core::backend::navigator::NullExecutor;
use std::collections::HashMap;
use std::sync::mpsc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::OnceLock;

struct PlayerEntry {
    player: std::sync::Arc<std::sync::Mutex<ruffle_core::Player>>,
    header: player::SwfHeaderInfo,
    navigator_executor: NullExecutor,
}

static PLAYER_ID_ALLOC: AtomicU64 = AtomicU64::new(1);
static PLAYER_THREAD_SENDER: OnceLock<mpsc::Sender<_PlayerThreadTask>> = OnceLock::new();

fn alloc_player_id() -> u64 {
    PLAYER_ID_ALLOC.fetch_add(1, Ordering::Relaxed)
}

fn with_players<R>(f: impl FnOnce(&mut HashMap<u64, PlayerEntry>) -> R + Send + 'static) -> R
where
    R: Send + 'static,
{
    let sender = PLAYER_THREAD_SENDER.get_or_init(|| {
        let (tx, rx) = mpsc::channel::<_PlayerThreadTask>();
        std::thread::Builder::new()
            .name("ruffle-player-thread".to_string())
            .spawn(move || {
                let mut players: HashMap<u64, PlayerEntry> = HashMap::new();
                while let Ok(task) = rx.recv() {
                    let result = (task.f)(&mut players);
                    let _ = task.reply.send(result);
                }
            })
            .expect("ruffle player thread should be spawned");
        tx
    });

    let (reply_tx, reply_rx) = mpsc::channel::<Box<dyn std::any::Any + Send>>();
    sender
        .send(_PlayerThreadTask {
            f: Box::new(move |players| -> Box<dyn std::any::Any + Send> { Box::new(f(players)) }),
            reply: reply_tx,
        })
        .expect("ruffle player thread should accept task");

    let boxed = reply_rx
        .recv()
        .expect("ruffle player thread should reply");
    *boxed
        .downcast::<R>()
        .expect("ruffle player thread reply type mismatch")
}

struct _PlayerThreadTask {
    f: Box<dyn FnOnce(&mut HashMap<u64, PlayerEntry>) -> Box<dyn std::any::Any + Send> + Send>,
    reply: mpsc::Sender<Box<dyn std::any::Any + Send>>,
}
