mod runtime;
mod smoke;

use tauri::Manager;

#[derive(Clone, serde::Serialize)]
struct RuntimeConnection {
    #[serde(rename = "apiUrl")]
    api_url: String,
    #[serde(rename = "appToken")]
    app_token: String,
}

#[derive(Clone, serde::Serialize)]
struct RuntimeError {
    code: String,
    message: String,
}

#[derive(Clone, serde::Serialize)]
struct RuntimeSnapshot {
    generation: u64,
    state: runtime::RuntimeState,
    #[serde(skip_serializing_if = "Option::is_none")]
    connection: Option<RuntimeConnection>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<RuntimeError>,
}

#[tauri::command]
fn get_runtime_snapshot(runtime: tauri::State<'_, runtime::RuntimeHandle>) -> RuntimeSnapshot {
    snapshot_from_runtime(&runtime)
}

#[tauri::command]
fn open_logs() -> Result<(), String> {
    Ok(())
}

fn main() {
    let runtime = runtime::RuntimeHandle::new();
    let builder = tauri::Builder::default()
        .manage(runtime)
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.unminimize();
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![get_runtime_snapshot, open_logs])
        .setup(|app| {
            runtime::self_test().map_err(|err| err.to_string())?;
            smoke::self_test().map_err(|err| err.to_string())?;
            app.state::<runtime::RuntimeHandle>()
                .start(app.handle().clone())
                .map_err(|err| err.to_string())?;
            if let Some(window) = app.get_webview_window("main") {
                window.show()?;
                window.set_focus()?;
            }
            Ok(())
        });

    builder
        .run(tauri::generate_context!())
        .expect("failed to run Voyage VII");
}

fn snapshot_from_runtime(runtime: &runtime::RuntimeHandle) -> RuntimeSnapshot {
    runtime.snapshot()
}

#[cfg(test)]
mod tests {
    #[test]
    fn static_seams_are_registered() {
        super::runtime::self_test().expect("runtime seam");
        super::smoke::self_test().expect("smoke seam");
        let runtime = super::runtime::RuntimeHandle::new();
        let snapshot = super::snapshot_from_runtime(&runtime);
        assert_eq!(snapshot.generation, 0);
    }
}
