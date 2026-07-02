use base64::Engine;
use serde::{Deserialize, Serialize};
use std::{
    collections::VecDeque,
    env,
    ffi::OsString,
    fmt,
    io::{BufRead, BufReader, Read, Write},
    net::TcpStream,
    path::{Path, PathBuf},
    process::{Child, Command, ExitStatus, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};
use tauri::{Emitter, Manager};
use url::Url;
use zeroize::Zeroize;

const HANDSHAKE_PREFIX: &str = "VOYAGE_VII_HANDSHAKE ";
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(15);
const HANDSHAKE_MAX_BYTES: usize = 16 * 1024;
const SHUTDOWN_GRACEFUL: Duration = Duration::from_secs(20);
const SHUTDOWN_TERMINATE_WAIT: Duration = Duration::from_secs(5);
const RESTART_LIMIT: usize = 3;
const RESTART_WINDOW: Duration = Duration::from_secs(5 * 60);
const PACKAGED_ORIGIN: &str = "http://tauri.localhost";

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum RuntimeState {
    Launching,
    Connected,
    Restarting,
    Failed,
    Stopping,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeChangedEvent {
    generation: u64,
    state: RuntimeState,
}

#[derive(Clone, Eq, PartialEq)]
struct RuntimeConnectionInternal {
    api_url: String,
    app_token: String,
    supervisor_token: SecretString,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct RuntimeErrorInternal {
    code: String,
    message: String,
}

#[derive(Clone)]
struct SharedState {
    generation: u64,
    state: RuntimeState,
    connection: Option<RuntimeConnectionInternal>,
    error: Option<RuntimeErrorInternal>,
    logs: Vec<String>,
    events: Vec<RuntimeChangedEvent>,
}

#[derive(Clone, Debug)]
pub struct RuntimeHandle {
    shared: Arc<Mutex<SharedState>>,
    stop: Arc<AtomicBool>,
    thread: Arc<Mutex<Option<thread::JoinHandle<()>>>>,
}

#[derive(Clone, Debug)]
pub struct SupervisorConfig {
    launcher: Launcher,
    runtime_root: PathBuf,
    data_root: PathBuf,
    allowed_origin: String,
    handshake_timeout: Duration,
    shutdown_graceful: Duration,
    shutdown_terminate_wait: Duration,
    restart_limit: usize,
    restart_window: Duration,
}

#[derive(Clone, Debug)]
pub struct Launcher {
    program: PathBuf,
    prefix_args: Vec<OsString>,
}

#[derive(Clone, Eq, PartialEq)]
struct SecretString(String);

impl SecretString {
    fn new(value: String) -> Self {
        Self(value)
    }

    fn expose(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for SecretString {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("SecretString([redacted])")
    }
}

impl fmt::Debug for RuntimeConnectionInternal {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RuntimeConnectionInternal")
            .field("api_url", &self.api_url)
            .field("app_token", &"[redacted]")
            .field("supervisor_token", &self.supervisor_token)
            .finish()
    }
}

impl fmt::Debug for SharedState {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("SharedState")
            .field("generation", &self.generation)
            .field("state", &self.state)
            .field("connection", &self.connection)
            .field("error", &self.error)
            .field("logs", &self.logs)
            .field("events", &self.events)
            .finish()
    }
}

impl Drop for SecretString {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

impl RuntimeHandle {
    pub fn new() -> Self {
        Self {
            shared: Arc::new(Mutex::new(SharedState {
                generation: 0,
                state: RuntimeState::Launching,
                connection: None,
                error: None,
                logs: Vec::new(),
                events: Vec::new(),
            })),
            stop: Arc::new(AtomicBool::new(false)),
            thread: Arc::new(Mutex::new(None)),
        }
    }

    pub fn start(&self, app: tauri::AppHandle) -> anyhow::Result<()> {
        let config = SupervisorConfig::packaged(&app)?;
        self.start_with_config(config, TauriEventSink { app })
    }

    fn start_with_config<S>(&self, config: SupervisorConfig, event_sink: S) -> anyhow::Result<()>
    where
        S: EventSink,
    {
        let mut slot = self.thread.lock().expect("runtime supervisor thread mutex");
        anyhow::ensure!(slot.is_none(), "runtime supervisor already started");
        self.stop.store(false, Ordering::SeqCst);
        let shared = Arc::clone(&self.shared);
        let stop = Arc::clone(&self.stop);
        *slot = Some(thread::spawn(move || {
            run_supervisor(config, shared, stop, Box::new(event_sink));
        }));
        Ok(())
    }

    pub fn snapshot(&self) -> crate::RuntimeSnapshot {
        snapshot_from_shared(&self.shared.lock().expect("runtime snapshot mutex"))
    }

    #[cfg(test)]
    fn logs(&self) -> Vec<String> {
        self.shared.lock().expect("runtime logs mutex").logs.clone()
    }

    #[cfg(test)]
    fn events(&self) -> Vec<RuntimeChangedEvent> {
        self.shared
            .lock()
            .expect("runtime events mutex")
            .events
            .clone()
    }

    #[cfg(test)]
    fn stop_for_test(&self) {
        self.stop.store(true, Ordering::SeqCst);
        if let Some(handle) = self.thread.lock().expect("runtime thread mutex").take() {
            handle.join().expect("runtime supervisor thread joined");
        }
    }
}

impl Default for RuntimeHandle {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for RuntimeHandle {
    fn drop(&mut self) {
        if Arc::strong_count(&self.thread) == 1 {
            self.stop.store(true, Ordering::SeqCst);
            if let Some(handle) = self.thread.lock().expect("runtime thread mutex").take() {
                let _ = handle.join();
            }
        }
    }
}

impl SupervisorConfig {
    fn packaged(app: &tauri::AppHandle) -> anyhow::Result<Self> {
        let runtime_root = packaged_runtime_root(app)?;
        let data_root = app.path().app_data_dir()?;
        Ok(Self::new(
            Launcher {
                program: runtime_root.join("api").join("voyage-vii-api.exe"),
                prefix_args: Vec::new(),
            },
            runtime_root,
            data_root,
            PACKAGED_ORIGIN.to_string(),
        ))
    }

    fn new(
        launcher: Launcher,
        runtime_root: PathBuf,
        data_root: PathBuf,
        allowed_origin: String,
    ) -> Self {
        Self {
            launcher,
            runtime_root,
            data_root,
            allowed_origin,
            handshake_timeout: HANDSHAKE_TIMEOUT,
            shutdown_graceful: SHUTDOWN_GRACEFUL,
            shutdown_terminate_wait: SHUTDOWN_TERMINATE_WAIT,
            restart_limit: RESTART_LIMIT,
            restart_window: RESTART_WINDOW,
        }
    }
}

fn packaged_runtime_root(app: &tauri::AppHandle) -> anyhow::Result<PathBuf> {
    let app_dir = env::current_exe()
        .ok()
        .and_then(|current_exe| current_exe.parent().map(Path::to_path_buf));
    if let Ok(runtime_root) = select_packaged_runtime_root(app_dir.as_deref(), None) {
        return Ok(runtime_root);
    }

    let resource_dir = app.path().resource_dir()?;
    select_packaged_runtime_root(None, Some(&resource_dir))
}

fn select_packaged_runtime_root(
    app_dir: Option<&Path>,
    resource_dir: Option<&Path>,
) -> anyhow::Result<PathBuf> {
    if let Some(runtime_root) = app_dir
        .map(portable_runtime_root)
        .filter(|candidate| is_packaged_runtime_root(candidate))
    {
        return Ok(runtime_root);
    }

    if let Some(runtime_root) = resource_dir
        .map(|root| root.join("runtime"))
        .filter(|candidate| is_packaged_runtime_root(candidate))
    {
        return Ok(runtime_root);
    }

    anyhow::bail!("packaged runtime was not found beside the app executable or in Tauri resources")
}

fn portable_runtime_root(app_dir: &Path) -> PathBuf {
    app_dir.join("resources").join("runtime")
}

fn is_packaged_runtime_root(root: &Path) -> bool {
    root.join("manifest.json").is_file() && root.join("api").join("voyage-vii-api.exe").is_file()
}

trait EventSink: Send + 'static {
    fn emit(&self, event: RuntimeChangedEvent);
}

struct TauriEventSink {
    app: tauri::AppHandle,
}

impl EventSink for TauriEventSink {
    fn emit(&self, event: RuntimeChangedEvent) {
        let _ = self.app.emit("voyage-vii://runtime-changed", event);
    }
}

fn run_supervisor(
    config: SupervisorConfig,
    shared: Arc<Mutex<SharedState>>,
    stop: Arc<AtomicBool>,
    event_sink: Box<dyn EventSink>,
) {
    let mut restart_times = VecDeque::new();
    let mut first = true;

    while !stop.load(Ordering::SeqCst) {
        publish(
            &shared,
            event_sink.as_ref(),
            if first {
                RuntimeState::Launching
            } else {
                RuntimeState::Restarting
            },
            None,
            None,
        );
        first = false;

        let mut child = match spawn_api(&config, Arc::clone(&shared)) {
            Ok(child) => child,
            Err(err) => {
                publish_error(
                    &shared,
                    event_sink.as_ref(),
                    "api_spawn_failed",
                    err.to_string(),
                );
                return;
            }
        };

        match read_handshake(&mut child, config.handshake_timeout) {
            Ok(connection) => {
                publish(
                    &shared,
                    event_sink.as_ref(),
                    RuntimeState::Connected,
                    Some(connection.clone()),
                    None,
                );
                match wait_until_exit_or_stop(&mut child, &stop) {
                    ChildObservation::StopRequested => {
                        publish(
                            &shared,
                            event_sink.as_ref(),
                            RuntimeState::Stopping,
                            None,
                            None,
                        );
                        if let Err(err) = shutdown_child(&mut child, &connection, &config) {
                            publish_error(
                                &shared,
                                event_sink.as_ref(),
                                "process_tree_cleanup_failed",
                                err.to_string(),
                            );
                        }
                        return;
                    }
                    ChildObservation::Exited(status) => {
                        append_log(&shared, format!("api exited: {}", status_text(status)));
                    }
                    ChildObservation::StdoutViolation => {
                        append_log(&shared, "unexpected stdout after handshake".to_string());
                        let _ = terminate_child(&mut child, config.shutdown_terminate_wait);
                    }
                }
            }
            Err(err) => {
                append_log(&shared, format!("handshake failed: {}", err));
                let _ = terminate_child(&mut child, config.shutdown_terminate_wait);
            }
        }

        let now = Instant::now();
        restart_times.push_back(now);
        while restart_times
            .front()
            .is_some_and(|started| now.duration_since(*started) > config.restart_window)
        {
            restart_times.pop_front();
        }
        if restart_times.len() > config.restart_limit {
            publish_error(
                &shared,
                event_sink.as_ref(),
                "restart_budget_exhausted",
                "The API exited too many times in the restart window.",
            );
            return;
        }
    }
}

fn spawn_api(
    config: &SupervisorConfig,
    shared: Arc<Mutex<SharedState>>,
) -> anyhow::Result<ContainedChild> {
    let mut args = config.launcher.prefix_args.clone();
    args.extend([
        OsString::from("serve"),
        OsString::from("--runtime"),
        OsString::from("managed"),
        OsString::from("--runtime-root"),
        config.runtime_root.as_os_str().to_os_string(),
        OsString::from("--data-root"),
        config.data_root.as_os_str().to_os_string(),
        OsString::from("--allowed-origin"),
        OsString::from(config.allowed_origin.clone()),
        OsString::from("--handshake"),
        OsString::from("stdout-v1"),
    ]);

    let mut command = Command::new(&config.launcher.program);
    command
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    for (key, _) in
        env::vars_os().filter(|(key, _)| key.to_string_lossy().starts_with("VOYAGE_VII_"))
    {
        command.env_remove(key);
    }

    let mut child = command.spawn()?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| anyhow::anyhow!("stdout pipe missing"))?;
    let job = platform::contain(&mut child)?;
    let stderr = child.stderr.take();
    if let Some(stderr) = stderr {
        thread::spawn(move || read_logs(stderr, shared));
    }
    let (handshake_tx, handshake_rx) = mpsc::channel();
    let (stdout_violation_tx, stdout_violation_rx) = mpsc::channel();
    thread::spawn(move || read_stdout(stdout, handshake_tx, stdout_violation_tx));
    Ok(ContainedChild {
        child,
        job,
        handshake_rx,
        stdout_violation_rx,
    })
}

fn read_stdout(
    stdout: impl Read + Send + 'static,
    handshake_tx: mpsc::Sender<anyhow::Result<String>>,
    stdout_violation_tx: mpsc::Sender<()>,
) {
    let mut reader = BufReader::new(stdout);
    let first = read_bounded_line(&mut reader);
    let _ = handshake_tx.send(first);
    for line in reader.lines().map_while(Result::ok) {
        if !line.trim().is_empty() {
            let _ = stdout_violation_tx.send(());
            break;
        }
    }
}

fn read_logs(stderr: impl Read + Send + 'static, shared: Arc<Mutex<SharedState>>) {
    let reader = BufReader::new(stderr);
    for line in reader.lines().map_while(Result::ok) {
        if !line.contains(HANDSHAKE_PREFIX) {
            append_log(&shared, line);
        }
    }
}

fn read_handshake(
    child: &mut ContainedChild,
    timeout: Duration,
) -> anyhow::Result<RuntimeConnectionInternal> {
    let line = child.handshake_rx.recv_timeout(timeout)??;
    validate_handshake(&line)
}

fn read_bounded_line(reader: &mut impl BufRead) -> anyhow::Result<String> {
    let mut bytes = Vec::new();
    let mut one = [0_u8; 1];
    loop {
        let read = reader.read(&mut one)?;
        if read == 0 {
            anyhow::bail!("stdout closed before handshake");
        }
        bytes.push(one[0]);
        if bytes.len() > HANDSHAKE_MAX_BYTES {
            anyhow::bail!("handshake exceeded byte limit");
        }
        if one[0] == b'\n' {
            break;
        }
    }
    Ok(String::from_utf8(bytes)?
        .trim_end_matches(['\r', '\n'])
        .to_string())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Handshake {
    protocol_version: u8,
    api_url: String,
    app_token: String,
    supervisor_token: String,
}

fn validate_handshake(line: &str) -> anyhow::Result<RuntimeConnectionInternal> {
    let payload = line
        .strip_prefix(HANDSHAKE_PREFIX)
        .ok_or_else(|| anyhow::anyhow!("missing handshake prefix"))?;
    let handshake: Handshake = serde_json::from_str(payload)?;
    anyhow::ensure!(handshake.protocol_version == 1, "invalid protocol version");
    validate_loopback_url(&handshake.api_url)?;
    validate_token("app token", &handshake.app_token)?;
    validate_token("supervisor token", &handshake.supervisor_token)?;
    anyhow::ensure!(
        handshake.app_token != handshake.supervisor_token,
        "tokens must be distinct"
    );
    Ok(RuntimeConnectionInternal {
        api_url: handshake.api_url,
        app_token: handshake.app_token,
        supervisor_token: SecretString::new(handshake.supervisor_token),
    })
}

fn validate_loopback_url(raw: &str) -> anyhow::Result<()> {
    let parsed = Url::parse(raw)?;
    anyhow::ensure!(parsed.scheme() == "http", "API URL must be HTTP");
    anyhow::ensure!(
        parsed
            .host_str()
            .is_some_and(|host| host == "127.0.0.1" || host == "localhost"),
        "API URL must be loopback"
    );
    anyhow::ensure!(parsed.port().is_some(), "API URL must include a port");
    anyhow::ensure!(
        parsed.username().is_empty(),
        "API URL must not contain credentials"
    );
    anyhow::ensure!(
        parsed.password().is_none(),
        "API URL must not contain credentials"
    );
    anyhow::ensure!(parsed.path() == "/", "API URL must not contain a path");
    anyhow::ensure!(parsed.query().is_none(), "API URL must not contain a query");
    anyhow::ensure!(
        parsed.fragment().is_none(),
        "API URL must not contain a fragment"
    );
    Ok(())
}

fn validate_token(name: &str, value: &str) -> anyhow::Result<()> {
    anyhow::ensure!(value.len() == 43, "{name} length is invalid");
    anyhow::ensure!(
        value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_'),
        "{name} is not unpadded base64url"
    );
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(value)?;
    anyhow::ensure!(decoded.len() == 32, "{name} must decode to 32 bytes");
    Ok(())
}

fn wait_until_exit_or_stop(child: &mut ContainedChild, stop: &AtomicBool) -> ChildObservation {
    loop {
        if stop.load(Ordering::SeqCst) {
            return ChildObservation::StopRequested;
        }
        if child.stdout_violation_rx.try_recv().is_ok() {
            return ChildObservation::StdoutViolation;
        }
        if let Ok(Some(status)) = child.child.try_wait() {
            return ChildObservation::Exited(status);
        }
        thread::sleep(Duration::from_millis(20));
    }
}

fn shutdown_child(
    child: &mut ContainedChild,
    connection: &RuntimeConnectionInternal,
    config: &SupervisorConfig,
) -> anyhow::Result<()> {
    let _ = send_shutdown(connection);
    if wait_for_exit(&mut child.child, config.shutdown_graceful) {
        ensure_job_empty_or_terminate(child, config.shutdown_terminate_wait)?;
        return Ok(());
    }
    terminate_child(child, config.shutdown_terminate_wait)
}

fn send_shutdown(connection: &RuntimeConnectionInternal) -> anyhow::Result<()> {
    let url = Url::parse(&connection.api_url)?;
    let host = url
        .host_str()
        .ok_or_else(|| anyhow::anyhow!("API URL missing host"))?;
    let port = url
        .port()
        .ok_or_else(|| anyhow::anyhow!("API URL missing port"))?;
    let mut stream = TcpStream::connect((host, port))?;
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.set_write_timeout(Some(Duration::from_secs(2)))?;
    let request = format!(
        "POST /api/v1/system/shutdown HTTP/1.1\r\nHost: {host}:{port}\r\nAuthorization: Bearer {}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        connection.supervisor_token.expose()
    );
    stream.write_all(request.as_bytes())?;
    let mut response = [0_u8; 32];
    let _ = stream.read(&mut response)?;
    Ok(())
}

fn terminate_child(child: &mut ContainedChild, wait: Duration) -> anyhow::Result<()> {
    child.job.terminate();
    let _ = child.child.kill();
    if wait_for_exit(&mut child.child, wait) {
        child.job.wait_until_empty(wait)?;
        return Ok(());
    }
    let _ = child.child.kill();
    let _ = child.child.wait();
    child.job.wait_until_empty(wait)?;
    Ok(())
}

fn ensure_job_empty_or_terminate(child: &mut ContainedChild, wait: Duration) -> anyhow::Result<()> {
    if child
        .job
        .wait_until_empty(Duration::from_millis(100))
        .is_ok()
    {
        return Ok(());
    }
    child.job.terminate();
    child.job.wait_until_empty(wait)
}

fn wait_for_exit(child: &mut Child, timeout: Duration) -> bool {
    let start = Instant::now();
    while start.elapsed() < timeout {
        if child.try_wait().ok().flatten().is_some() {
            return true;
        }
        thread::sleep(Duration::from_millis(20));
    }
    false
}

enum ChildObservation {
    StopRequested,
    Exited(ExitStatus),
    StdoutViolation,
}

struct ContainedChild {
    child: Child,
    job: platform::Job,
    handshake_rx: mpsc::Receiver<anyhow::Result<String>>,
    stdout_violation_rx: mpsc::Receiver<()>,
}

fn publish(
    shared: &Arc<Mutex<SharedState>>,
    event_sink: &dyn EventSink,
    state: RuntimeState,
    connection: Option<RuntimeConnectionInternal>,
    error: Option<RuntimeErrorInternal>,
) {
    let event = {
        let mut guard = shared.lock().expect("runtime state mutex");
        guard.generation += 1;
        guard.state = state;
        guard.connection = connection;
        guard.error = error;
        RuntimeChangedEvent {
            generation: guard.generation,
            state,
        }
    };
    remember_event(shared, event.clone());
    event_sink.emit(event);
}

fn publish_error(
    shared: &Arc<Mutex<SharedState>>,
    event_sink: &dyn EventSink,
    code: impl Into<String>,
    message: impl Into<String>,
) {
    publish(
        shared,
        event_sink,
        RuntimeState::Failed,
        None,
        Some(RuntimeErrorInternal {
            code: code.into(),
            message: message.into(),
        }),
    );
}

fn remember_event(shared: &Arc<Mutex<SharedState>>, event: RuntimeChangedEvent) {
    shared
        .lock()
        .expect("runtime event mutex")
        .events
        .push(event);
}

fn append_log(shared: &Arc<Mutex<SharedState>>, line: String) {
    shared
        .lock()
        .expect("runtime log mutex")
        .logs
        .push(redact(&line));
}

fn snapshot_from_shared(shared: &SharedState) -> crate::RuntimeSnapshot {
    crate::RuntimeSnapshot {
        generation: shared.generation,
        state: shared.state,
        connection: shared
            .connection
            .as_ref()
            .map(|connection| crate::RuntimeConnection {
                api_url: connection.api_url.clone(),
                app_token: connection.app_token.clone(),
            }),
        error: shared.error.as_ref().map(|error| crate::RuntimeError {
            code: error.code.clone(),
            message: error.message.clone(),
        }),
    }
}

pub fn initial_snapshot() -> crate::RuntimeSnapshot {
    RuntimeHandle::new().snapshot()
}

pub fn self_test() -> anyhow::Result<()> {
    anyhow::ensure!(HANDSHAKE_TIMEOUT == Duration::from_secs(15));
    anyhow::ensure!(HANDSHAKE_MAX_BYTES == 16 * 1024);
    anyhow::ensure!(SHUTDOWN_GRACEFUL == Duration::from_secs(20));
    anyhow::ensure!(SHUTDOWN_TERMINATE_WAIT == Duration::from_secs(5));
    anyhow::ensure!(RESTART_LIMIT == 3);
    anyhow::ensure!(PACKAGED_ORIGIN == "http://tauri.localhost");
    let snapshot = initial_snapshot();
    anyhow::ensure!(snapshot.generation == 0);
    anyhow::ensure!(snapshot.connection.is_none());
    Ok(())
}

fn redact(line: &str) -> String {
    if line.contains("Authorization: Bearer")
        || line.contains("appToken")
        || line.contains("supervisorToken")
    {
        return "[redacted runtime secret]".to_string();
    }
    line.to_string()
}

fn status_text(status: ExitStatus) -> String {
    match status.code() {
        Some(code) => format!("code {code}"),
        None => "terminated".to_string(),
    }
}

#[cfg(windows)]
mod platform {
    use super::*;
    use std::{ffi::c_void, os::windows::io::AsRawHandle, ptr};

    type Bool = i32;
    type Dword = u32;
    type Handle = *mut c_void;

    const JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE: Dword = 0x0000_2000;
    const JOB_OBJECT_BASIC_ACCOUNTING_INFORMATION_CLASS: Dword = 1;
    const JOB_OBJECT_EXTENDED_LIMIT_INFORMATION_CLASS: Dword = 9;

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct IoCounters {
        read_operation_count: u64,
        write_operation_count: u64,
        other_operation_count: u64,
        read_transfer_count: u64,
        write_transfer_count: u64,
        other_transfer_count: u64,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct JobObjectBasicLimitInformation {
        per_process_user_time_limit: i64,
        per_job_user_time_limit: i64,
        limit_flags: Dword,
        minimum_working_set_size: usize,
        maximum_working_set_size: usize,
        active_process_limit: Dword,
        affinity: usize,
        priority_class: Dword,
        scheduling_class: Dword,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct JobObjectExtendedLimitInformation {
        basic_limit_information: JobObjectBasicLimitInformation,
        io_info: IoCounters,
        process_memory_limit: usize,
        job_memory_limit: usize,
        peak_process_memory_used: usize,
        peak_job_memory_used: usize,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct JobObjectBasicAccountingInformation {
        total_user_time: i64,
        total_kernel_time: i64,
        this_period_total_user_time: i64,
        this_period_total_kernel_time: i64,
        total_page_fault_count: Dword,
        total_processes: Dword,
        active_processes: Dword,
        total_terminated_processes: Dword,
    }

    #[link(name = "kernel32")]
    extern "system" {
        fn CreateJobObjectW(attributes: *const c_void, name: *const u16) -> Handle;
        fn SetInformationJobObject(
            job: Handle,
            info_class: Dword,
            info: *const c_void,
            info_length: Dword,
        ) -> Bool;
        fn AssignProcessToJobObject(job: Handle, process: Handle) -> Bool;
        fn QueryInformationJobObject(
            job: Handle,
            info_class: Dword,
            info: *mut c_void,
            info_length: Dword,
            return_length: *mut Dword,
        ) -> Bool;
        fn TerminateJobObject(job: Handle, exit_code: u32) -> Bool;
        fn CloseHandle(handle: Handle) -> Bool;
    }

    pub struct Job {
        handle: Handle,
    }

    unsafe impl Send for Job {}

    pub fn contain(child: &mut Child) -> anyhow::Result<Job> {
        unsafe {
            let job = CreateJobObjectW(ptr::null(), ptr::null());
            anyhow::ensure!(!job.is_null(), "CreateJobObjectW failed");
            let mut info: JobObjectExtendedLimitInformation = std::mem::zeroed();
            info.basic_limit_information.limit_flags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            let ok = SetInformationJobObject(
                job,
                JOB_OBJECT_EXTENDED_LIMIT_INFORMATION_CLASS,
                &info as *const _ as *const c_void,
                std::mem::size_of::<JobObjectExtendedLimitInformation>() as Dword,
            );
            if ok == 0 {
                CloseHandle(job);
                anyhow::bail!("SetInformationJobObject failed");
            }
            let process = child.as_raw_handle() as Handle;
            let ok = AssignProcessToJobObject(job, process);
            if ok == 0 {
                CloseHandle(job);
                anyhow::bail!("AssignProcessToJobObject failed");
            }
            Ok(Job { handle: job })
        }
    }

    impl Job {
        pub fn terminate(&self) {
            unsafe {
                let _ = TerminateJobObject(self.handle, 1);
            }
        }

        pub fn active_processes(&self) -> anyhow::Result<u32> {
            unsafe {
                let mut info: JobObjectBasicAccountingInformation = std::mem::zeroed();
                let ok = QueryInformationJobObject(
                    self.handle,
                    JOB_OBJECT_BASIC_ACCOUNTING_INFORMATION_CLASS,
                    &mut info as *mut _ as *mut c_void,
                    std::mem::size_of::<JobObjectBasicAccountingInformation>() as Dword,
                    ptr::null_mut(),
                );
                anyhow::ensure!(ok != 0, "QueryInformationJobObject failed");
                Ok(info.active_processes)
            }
        }

        pub fn wait_until_empty(&self, timeout: Duration) -> anyhow::Result<()> {
            let start = Instant::now();
            loop {
                if self.active_processes()? == 0 {
                    return Ok(());
                }
                if start.elapsed() >= timeout {
                    anyhow::bail!("contained job still has active descendants");
                }
                thread::sleep(Duration::from_millis(20));
            }
        }
    }

    impl Drop for Job {
        fn drop(&mut self) {
            unsafe {
                let _ = CloseHandle(self.handle);
            }
        }
    }
}

#[cfg(not(windows))]
mod platform {
    use super::*;

    pub struct Job;

    pub fn contain(_child: &mut Child) -> anyhow::Result<Job> {
        Ok(Job)
    }

    impl Job {
        pub fn terminate(&self) {}

        pub fn wait_until_empty(&self, _timeout: Duration) -> anyhow::Result<()> {
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{fs, path::Path};
    use tempfile::TempDir;

    const APP_TOKEN: &str = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE";
    const SUPERVISOR_TOKEN: &str = "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI";

    #[derive(Clone)]
    struct NoopEventSink;

    impl EventSink for NoopEventSink {
        fn emit(&self, _event: RuntimeChangedEvent) {}
    }

    fn fixture_path() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../fixtures/fake-api/fake-api.ps1")
            .canonicalize()
            .expect("fake API fixture exists")
    }

    fn pwsh() -> PathBuf {
        PathBuf::from("pwsh.exe")
    }

    fn config(mode: &str, temp: &TempDir) -> SupervisorConfig {
        let mut config = SupervisorConfig::new(
            Launcher {
                program: pwsh(),
                prefix_args: vec![
                    OsString::from("-NoProfile"),
                    OsString::from("-ExecutionPolicy"),
                    OsString::from("Bypass"),
                    OsString::from("-File"),
                    fixture_path().into_os_string(),
                    OsString::from("-Mode"),
                    OsString::from(mode),
                ],
            },
            temp.path().join("runtime"),
            temp.path().join("data"),
            "http://localhost:1420".to_string(),
        );
        config.handshake_timeout = Duration::from_secs(3);
        config.shutdown_graceful = Duration::from_secs(3);
        config.shutdown_terminate_wait = Duration::from_secs(1);
        config.restart_window = Duration::from_secs(2);
        config
    }

    fn wait_for_state(handle: &RuntimeHandle, state: RuntimeState) -> crate::RuntimeSnapshot {
        let start = Instant::now();
        loop {
            let snapshot = handle.snapshot();
            if snapshot.state == state {
                return snapshot;
            }
            assert!(
                start.elapsed() < Duration::from_secs(10),
                "state timeout: {state:?}"
            );
            thread::sleep(Duration::from_millis(20));
        }
    }

    #[test]
    fn parses_and_validates_handshake() {
        let line = format!(
            "{HANDSHAKE_PREFIX}{{\"protocolVersion\":1,\"apiUrl\":\"http://127.0.0.1:7800\",\"appToken\":\"{APP_TOKEN}\",\"supervisorToken\":\"{SUPERVISOR_TOKEN}\"}}"
        );
        let connection = validate_handshake(&line).expect("valid handshake");
        assert_eq!(connection.app_token, APP_TOKEN);
        assert_eq!(connection.supervisor_token.expose(), SUPERVISOR_TOKEN);

        assert!(validate_handshake("bad").is_err());
        assert!(validate_handshake(&line.replace("127.0.0.1:7800", "example.com:7800")).is_err());
        assert!(validate_handshake(&line.replace(SUPERVISOR_TOKEN, APP_TOKEN)).is_err());
        assert!(
            validate_handshake(&line.replace("protocolVersion\":1", "protocolVersion\":2"))
                .is_err()
        );
    }

    #[test]
    fn debug_output_redacts_tokens() {
        let line = format!(
            "{HANDSHAKE_PREFIX}{{\"protocolVersion\":1,\"apiUrl\":\"http://127.0.0.1:7800\",\"appToken\":\"{APP_TOKEN}\",\"supervisorToken\":\"{SUPERVISOR_TOKEN}\"}}"
        );
        let connection = validate_handshake(&line).expect("valid handshake");
        let shared = SharedState {
            generation: 1,
            state: RuntimeState::Connected,
            connection: Some(connection.clone()),
            error: None,
            logs: Vec::new(),
            events: Vec::new(),
        };
        for rendered in [
            format!("{connection:?}"),
            format!("{:?}", connection.supervisor_token),
            format!("{shared:?}"),
        ] {
            assert!(!rendered.contains(APP_TOKEN));
            assert!(!rendered.contains(SUPERVISOR_TOKEN));
            assert!(rendered.contains("[redacted]"));
        }
    }

    #[test]
    fn connects_and_exposes_only_app_token() {
        let temp = TempDir::new().expect("temp dir");
        fs::create_dir_all(temp.path().join("runtime")).expect("runtime dir");
        fs::create_dir_all(temp.path().join("data")).expect("data dir");
        let handle = RuntimeHandle::new();
        handle
            .start_with_config(config("valid", &temp), NoopEventSink)
            .expect("start supervisor");
        let snapshot = wait_for_state(&handle, RuntimeState::Connected);
        let connection = snapshot.connection.as_ref().expect("connection");
        assert!(connection.api_url.starts_with("http://127.0.0.1:"));
        assert_eq!(connection.app_token, APP_TOKEN);
        let serialized = serde_json::to_string(&snapshot).expect("snapshot json");
        assert!(!serialized.contains(SUPERVISOR_TOKEN));
        assert!(handle.events().iter().all(|event| {
            let value = serde_json::to_string(event).expect("event json");
            !value.contains(APP_TOKEN) && !value.contains(SUPERVISOR_TOKEN)
        }));
        handle.stop_for_test();
    }

    #[test]
    fn suppresses_handshake_and_tokens_from_logs() {
        let temp = TempDir::new().expect("temp dir");
        let handle = RuntimeHandle::new();
        handle
            .start_with_config(config("valid", &temp), NoopEventSink)
            .expect("start supervisor");
        let _ = wait_for_state(&handle, RuntimeState::Connected);
        handle.stop_for_test();
        let logs = handle.logs().join("\n");
        assert!(!logs.contains(APP_TOKEN));
        assert!(!logs.contains(SUPERVISOR_TOKEN));
        assert!(!logs.contains(HANDSHAKE_PREFIX));
    }

    #[test]
    fn malformed_missing_and_delayed_handshakes_fail_without_connection() {
        for mode in ["malformed", "missing", "delayed", "duplicate"] {
            let temp = TempDir::new().expect("temp dir");
            let mut cfg = config(mode, &temp);
            cfg.restart_limit = 0;
            cfg.handshake_timeout = Duration::from_millis(500);
            let handle = RuntimeHandle::new();
            handle
                .start_with_config(cfg, NoopEventSink)
                .expect("start supervisor");
            let snapshot = wait_for_state(&handle, RuntimeState::Failed);
            assert!(snapshot.connection.is_none());
            assert_eq!(
                snapshot.error.expect("error").code,
                "restart_budget_exhausted"
            );
            handle.stop_for_test();
        }
    }

    #[test]
    fn restart_budget_is_terminal_after_fourth_exit() {
        let temp = TempDir::new().expect("temp dir");
        let mut cfg = config("crash", &temp);
        cfg.restart_window = Duration::from_secs(30);
        let handle = RuntimeHandle::new();
        handle
            .start_with_config(cfg, NoopEventSink)
            .expect("start supervisor");
        let snapshot = wait_for_state(&handle, RuntimeState::Failed);
        assert_eq!(
            snapshot.error.expect("error").code,
            "restart_budget_exhausted"
        );
        let restarting = handle
            .events()
            .iter()
            .filter(|event| event.state == RuntimeState::Restarting)
            .count();
        assert_eq!(restarting, 3);
        handle.stop_for_test();
    }

    #[test]
    fn intentional_shutdown_does_not_restart_exit_7() {
        let temp = TempDir::new().expect("temp dir");
        let handle = RuntimeHandle::new();
        handle
            .start_with_config(config("exit7", &temp), NoopEventSink)
            .expect("start supervisor");
        let _ = wait_for_state(&handle, RuntimeState::Connected);
        handle.stop_for_test();
        let snapshot = handle.snapshot();
        assert_eq!(snapshot.state, RuntimeState::Stopping);
        assert!(snapshot.error.is_none());
        let events = handle.events();
        assert!(events
            .iter()
            .any(|event| event.state == RuntimeState::Stopping));
        let stopping_index = events
            .iter()
            .position(|event| event.state == RuntimeState::Stopping)
            .expect("stopping event");
        assert!(!events[stopping_index..]
            .iter()
            .any(|event| event.state == RuntimeState::Restarting));
    }

    #[test]
    fn forced_shutdown_reaps_child() {
        let temp = TempDir::new().expect("temp dir");
        let handle = RuntimeHandle::new();
        handle
            .start_with_config(config("ignore-shutdown", &temp), NoopEventSink)
            .expect("start supervisor");
        let _ = wait_for_state(&handle, RuntimeState::Connected);
        handle.stop_for_test();
        let snapshot = handle.snapshot();
        assert_eq!(snapshot.state, RuntimeState::Stopping);
        assert!(snapshot.error.is_none());
    }

    #[test]
    fn shutdown_reaps_grandchild_process_tree() {
        let temp = TempDir::new().expect("temp dir");
        let handle = RuntimeHandle::new();
        handle
            .start_with_config(config("grandchild", &temp), NoopEventSink)
            .expect("start supervisor");
        let _ = wait_for_state(&handle, RuntimeState::Connected);
        handle.stop_for_test();
        let snapshot = handle.snapshot();
        assert_eq!(snapshot.state, RuntimeState::Stopping);
        assert!(snapshot.error.is_none());
    }

    #[test]
    fn fake_fixture_is_owned_and_present() {
        assert!(Path::new(&fixture_path()).exists());
    }

    #[test]
    fn portable_runtime_root_matches_windows_zip_layout() {
        let app_dir = Path::new(r"C:\Voyage VII");
        assert_eq!(
            portable_runtime_root(app_dir),
            PathBuf::from(r"C:\Voyage VII\resources\runtime")
        );
    }

    #[test]
    fn packaged_runtime_root_requires_manifest_and_api_executable() {
        let temp = TempDir::new().expect("temp dir");
        let root = temp.path().join("resources").join("runtime");
        assert!(!is_packaged_runtime_root(&root));

        fs::create_dir_all(root.join("api")).expect("api dir");
        fs::write(root.join("manifest.json"), "{}").expect("manifest");
        assert!(!is_packaged_runtime_root(&root));

        fs::write(root.join("api").join("voyage-vii-api.exe"), "").expect("api exe");
        assert!(is_packaged_runtime_root(&root));
    }

    #[test]
    fn packaged_runtime_selection_prefers_portable_runtime() {
        let temp = TempDir::new().expect("temp dir");
        let app_dir = temp.path().join("app");
        let portable = portable_runtime_root(&app_dir);
        let tauri = temp.path().join("tauri").join("runtime");
        create_packaged_runtime_root(&portable);
        create_packaged_runtime_root(&tauri);

        let selected =
            select_packaged_runtime_root(Some(&app_dir), Some(&temp.path().join("tauri")))
                .expect("runtime root");
        assert_eq!(selected, portable);
    }

    #[test]
    fn packaged_runtime_selection_falls_back_to_tauri_resources() {
        let temp = TempDir::new().expect("temp dir");
        let app_dir = temp.path().join("app");
        let resource_dir = temp.path().join("tauri");
        let tauri = resource_dir.join("runtime");
        create_packaged_runtime_root(&tauri);

        let selected = select_packaged_runtime_root(Some(&app_dir), Some(&resource_dir))
            .expect("runtime root");
        assert_eq!(selected, tauri);
    }

    #[test]
    fn packaged_runtime_selection_fails_when_no_candidate_is_valid() {
        let temp = TempDir::new().expect("temp dir");
        assert!(select_packaged_runtime_root(Some(temp.path()), None).is_err());
    }

    fn create_packaged_runtime_root(root: &Path) {
        fs::create_dir_all(root.join("api")).expect("api dir");
        fs::write(root.join("manifest.json"), "{}").expect("manifest");
        fs::write(root.join("api").join("voyage-vii-api.exe"), "").expect("api exe");
    }

    #[test]
    fn env_sanitizer_removes_voyage_variables_from_child() {
        let temp = TempDir::new().expect("temp dir");
        unsafe {
            env::set_var("VOYAGE_VII_SHOULD_NOT_LEAK", "secret");
        }
        let handle = RuntimeHandle::new();
        handle
            .start_with_config(config("env-check", &temp), NoopEventSink)
            .expect("start supervisor");
        let snapshot = wait_for_state(&handle, RuntimeState::Connected);
        assert!(snapshot.connection.is_some());
        handle.stop_for_test();
        unsafe {
            env::remove_var("VOYAGE_VII_SHOULD_NOT_LEAK");
        }
    }

    #[test]
    fn state_generation_increases_on_transitions() {
        let temp = TempDir::new().expect("temp dir");
        let handle = RuntimeHandle::new();
        handle
            .start_with_config(config("valid", &temp), NoopEventSink)
            .expect("start supervisor");
        let connected = wait_for_state(&handle, RuntimeState::Connected);
        handle.stop_for_test();
        let stopping = handle.snapshot();
        assert!(connected.generation > 0);
        assert!(stopping.generation > connected.generation);
    }

    #[test]
    fn shutdown_request_uses_supervisor_token() {
        let temp = TempDir::new().expect("temp dir");
        let marker = temp.path().join("shutdown-token.txt");
        let mut cfg = config("record-shutdown-token", &temp);
        cfg.launcher.prefix_args.push(OsString::from("-MarkerPath"));
        cfg.launcher
            .prefix_args
            .push(marker.as_os_str().to_os_string());
        let handle = RuntimeHandle::new();
        handle
            .start_with_config(cfg, NoopEventSink)
            .expect("start supervisor");
        let _ = wait_for_state(&handle, RuntimeState::Connected);
        handle.stop_for_test();
        let recorded = fs::read_to_string(marker).expect("recorded token");
        assert_eq!(recorded.trim(), SUPERVISOR_TOKEN);
    }
}
