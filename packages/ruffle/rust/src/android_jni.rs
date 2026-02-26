use jni::objects::{GlobalRef, JClass, JObject, JString, JValue};
use jni::sys::{jint, jlong, jobject};
use jni::{JNIEnv, JavaVM};
use std::ffi::c_void;
use std::path::PathBuf;
use std::sync::OnceLock;

static JVM_PTR: OnceLock<usize> = OnceLock::new();
static APP_CONTEXT: OnceLock<GlobalRef> = OnceLock::new();
static NDK_CONTEXT_INITIALIZED: OnceLock<()> = OnceLock::new();

#[no_mangle]
/// 初始化 Android 侧的 JNI/Context 环境，供 Rust 依赖（如 cpal/AAudio 等）读取 AndroidContext。
pub extern "system" fn Java_com_flutter_1rust_1bridge_ruffle_RuffleNative_init(
    env: JNIEnv,
    _class: JClass,
    context: JObject,
) {
    if context.is_null() {
        return;
    }
    let vm = match env.get_java_vm() {
        Ok(vm) => vm,
        Err(_) => return,
    };
    let vm_ptr = vm.get_java_vm_pointer();
    let global = match env.new_global_ref(context) {
        Ok(global) => global,
        Err(_) => return,
    };

    let _ = JVM_PTR.set(vm_ptr as usize);
    let _ = APP_CONTEXT.set(global);

    if NDK_CONTEXT_INITIALIZED.get().is_none() {
        if let Some(ctx) = APP_CONTEXT.get() {
            unsafe {
                ndk_context::initialize_android_context(
                    vm_ptr.cast::<c_void>(),
                    ctx.as_obj().as_raw().cast::<c_void>(),
                );
            }
            let _ = NDK_CONTEXT_INITIALIZED.set(());
        }
    }
}

/// 将 Java Surface 转换为 ANativeWindow 指针，并在 native 侧持有引用（需调用 releaseNativeWindow 释放）。
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_ruffle_RuffleNative_acquireNativeWindowFromSurface(
    env: JNIEnv,
    _class: JClass,
    surface: jobject,
) -> jlong {
    if surface.is_null() {
        return 0;
    }

    let env_ptr = env.get_native_interface();
    let window = unsafe { ndk_sys::ANativeWindow_fromSurface(env_ptr, surface) };
    window as jlong
}

/// 释放由 acquireNativeWindowFromSurface 获取的 ANativeWindow 引用。
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_ruffle_RuffleNative_releaseNativeWindow(
    _env: JNIEnv,
    _class: JClass,
    native_window_ptr: jlong,
) {
    if native_window_ptr == 0 {
        return;
    }

    unsafe { ndk_sys::ANativeWindow_release(native_window_ptr as *mut ndk_sys::ANativeWindow) };
}

#[allow(dead_code)]
fn with_attached_env<R>(f: impl FnOnce(&mut JNIEnv, &JObject) -> R) -> Option<R> {
    let vm_ptr = *JVM_PTR.get()? as *mut jni::sys::JavaVM;
    let vm = unsafe { JavaVM::from_raw(vm_ptr).ok()? };
    let ctx = APP_CONTEXT.get()?;
    let mut env = vm.attach_current_thread().ok()?;
    let ctx_obj = ctx.as_obj();
    Some(f(&mut env, ctx_obj))
}

#[allow(dead_code)]
pub fn files_dir_path() -> Option<PathBuf> {
    with_attached_env(|env, ctx| {
        let files_dir = env
            .call_method(ctx, "getFilesDir", "()Ljava/io/File;", &[])
            .ok()?
            .l()
            .ok()?;
        let abs_path = env
            .call_method(files_dir, "getAbsolutePath", "()Ljava/lang/String;", &[])
            .ok()?
            .l()
            .ok()?;
        let abs_path: JString = abs_path.into();
        let abs_path: String = env.get_string(&abs_path).ok()?.into();
        Some(PathBuf::from(abs_path))
    })?
}

#[allow(dead_code)]
pub fn open_url(url: &str) -> bool {
    with_attached_env(|env, ctx| {
        let action_view = env.new_string("android.intent.action.VIEW").ok()?;
        let intent = env
            .new_object(
                "android/content/Intent",
                "(Ljava/lang/String;)V",
                &[JValue::Object(&action_view)],
            )
            .ok()?;

        let url_j = env.new_string(url).ok()?;
        let uri = env
            .call_static_method(
                "android/net/Uri",
                "parse",
                "(Ljava/lang/String;)Landroid/net/Uri;",
                &[JValue::Object(&url_j)],
            )
            .ok()?
            .l()
            .ok()?;

        let _ = env.call_method(
            &intent,
            "setData",
            "(Landroid/net/Uri;)Landroid/content/Intent;",
            &[JValue::Object(&uri)],
        );

        const FLAG_ACTIVITY_NEW_TASK: jint = 0x10000000;
        let _ = env.call_method(
            &intent,
            "addFlags",
            "(I)Landroid/content/Intent;",
            &[JValue::Int(FLAG_ACTIVITY_NEW_TASK)],
        );

        let _ = env.call_method(
            ctx,
            "startActivity",
            "(Landroid/content/Intent;)V",
            &[JValue::Object(&intent)],
        );
        Some(())
    })
    .is_some()
}
