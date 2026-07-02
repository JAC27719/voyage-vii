use serde::{Deserialize, Serialize};
use std::{
    ffi::OsString,
    fs,
    io::{Read, Write},
    net::TcpStream,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant},
};
use url::Url;

const HANDSHAKE_PREFIX: &str = "VOYAGE_VII_HANDSHAKE ";
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(15);
const HANDSHAKE_MAX_BYTES: usize = 16 * 1024;
const READY_TIMEOUT: Duration = Duration::from_secs(60);
const SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(20);
const PROCESS_REAP_TIMEOUT: Duration = Duration::from_secs(5);
const TARGET: &str = "x86_64-pc-windows-msvc";
const PRODUCT_VERSION: &str = env!("CARGO_PKG_VERSION");
const PACKAGED_ORIGIN: &str = "http://tauri.localhost";

#[derive(Debug, Clone)]
pub struct SmokeArgs {
    data_root: PathBuf,
}

#[derive(Debug, Clone)]
struct SmokeConfig {
    runtime_root: PathBuf,
    data_root: PathBuf,
    api_program: PathBuf,
    api_prefix_args: Vec<OsString>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SmokeOutput {
    schema_version: u8,
    product_version: &'static str,
    target: &'static str,
    fresh_elapsed_ms: u128,
    retained_elapsed_ms: u128,
    components: Vec<ComponentOutput>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ComponentOutput {
    id: String,
    version: String,
    state: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    schema_version: u8,
    product_version: String,
    target: String,
    components: Vec<ManifestComponent>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ManifestComponent {
    id: String,
    version: String,
    path: String,
    sha256: String,
    license_path: Option<String>,
    source: ManifestSource,
}

#[derive(Debug, Deserialize)]
struct ManifestSource {
    kind: String,
    url: Option<String>,
    revision: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Handshake {
    protocol_version: u8,
    api_url: String,
    app_token: String,
    supervisor_token: String,
}

#[derive(Debug, Deserialize)]
struct ReadyBody {
    status: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StatusBody {
    schema_version: u8,
    request_id: String,
    overall_state: String,
    components: Vec<StatusComponent>,
}

#[derive(Debug, Deserialize)]
struct StatusComponent {
    id: String,
    version: String,
    state: String,
}

struct SmokeChild {
    child: Child,
    job: platform::Job,
}

pub fn parse_args(args: impl IntoIterator<Item = OsString>) -> anyhow::Result<Option<SmokeArgs>> {
    let args: Vec<OsString> = args.into_iter().collect();
    if args.is_empty() {
        return Ok(None);
    }
    if args.first().is_none_or(|arg| arg != "--smoke-test") {
        return Ok(None);
    }
    anyhow::ensure!(
        args.len() == 3 && args[1] == "--data-root",
        "usage: --smoke-test --data-root <absolute-temporary-path>"
    );
    let data_root = PathBuf::from(&args[2]);
    anyhow::ensure!(data_root.is_absolute(), "smoke data root must be absolute");
    ensure_under_temp(&data_root)?;
    Ok(Some(SmokeArgs { data_root }))
}

pub fn run_from_args(args: impl IntoIterator<Item = OsString>) -> anyhow::Result<Option<String>> {
    let Some(args) = parse_args(args)? else {
        return Ok(None);
    };
    let exe = std::env::current_exe()?;
    let app_dir = exe
        .parent()
        .ok_or_else(|| anyhow::anyhow!("desktop executable has no parent directory"))?;
    let runtime_root = app_dir.join("resources").join("runtime");
    let config = SmokeConfig {
        api_program: runtime_root.join("api").join("voyage-vii-api.exe"),
        runtime_root,
        data_root: args.data_root,
        api_prefix_args: Vec::new(),
    };
    Ok(Some(run(config)?))
}

fn run(config: SmokeConfig) -> anyhow::Result<String> {
    anyhow::ensure!(
        cfg!(target_os = "windows"),
        "Windows is the only current native gate"
    );
    anyhow::ensure!(
        cfg!(target_arch = "x86_64"),
        "Windows x64 is the only current native architecture"
    );
    fs::create_dir_all(&config.data_root)?;
    let components = validate_runtime(&config.runtime_root)?;
    let fresh_elapsed_ms = run_once(&config)?;
    let retained_elapsed_ms = run_once(&config)?;
    let output = SmokeOutput {
        schema_version: 1,
        product_version: PRODUCT_VERSION,
        target: TARGET,
        fresh_elapsed_ms,
        retained_elapsed_ms,
        components,
    };
    Ok(format!(
        "VOYAGE_VII_SMOKE {}",
        serde_json::to_string(&output)?
    ))
}

fn run_once(config: &SmokeConfig) -> anyhow::Result<u128> {
    let started = Instant::now();
    let mut child = spawn_api(config)?;
    let handshake = read_handshake(&mut child.child, HANDSHAKE_TIMEOUT)?;
    let _components = wait_ready_and_status(&handshake)?;
    send_shutdown(&handshake)?;
    if !wait_for_exit(&mut child.child, SHUTDOWN_TIMEOUT) {
        child.job.terminate();
        let _ = child.child.kill();
        anyhow::ensure!(
            wait_for_exit(&mut child.child, PROCESS_REAP_TIMEOUT),
            "API process did not exit after termination"
        );
    }
    child.job.wait_until_empty(PROCESS_REAP_TIMEOUT)?;
    Ok(started.elapsed().as_millis())
}

fn validate_status(status: &StatusBody) -> anyhow::Result<()> {
    anyhow::ensure!(status.schema_version == 1, "status schemaVersion must be 1");
    anyhow::ensure!(!status.request_id.is_empty(), "status requestId is empty");
    anyhow::ensure!(
        status.overall_state == "ready",
        "status overallState must be ready"
    );
    let expected = [("sqlite", "3.53.3"), ("tigerbeetle", "0.17.7")];
    anyhow::ensure!(
        status.components.len() == expected.len(),
        "status must report sqlite and tigerbeetle only"
    );
    for ((expected_id, expected_version), component) in expected.iter().zip(&status.components) {
        anyhow::ensure!(
            component.id == *expected_id,
            "status component order mismatch"
        );
        anyhow::ensure!(
            component.version == *expected_version,
            "status component version mismatch"
        );
        anyhow::ensure!(
            component.state == "healthy",
            "status component must be healthy"
        );
    }
    Ok(())
}

fn validate_runtime(runtime_root: &Path) -> anyhow::Result<Vec<ComponentOutput>> {
    let manifest_path = runtime_root.join("manifest.json");
    let manifest: Manifest = serde_json::from_str(&fs::read_to_string(&manifest_path)?)?;
    anyhow::ensure!(
        manifest.schema_version == 1,
        "runtime manifest schemaVersion must be 1"
    );
    anyhow::ensure!(
        manifest.product_version == PRODUCT_VERSION,
        "runtime manifest productVersion mismatch"
    );
    anyhow::ensure!(
        manifest.target == TARGET,
        "runtime manifest target mismatch"
    );
    let expected = ["api", "sqlite", "tigerbeetle"];
    anyhow::ensure!(
        manifest.components.len() == expected.len(),
        "runtime manifest must contain api, sqlite, tigerbeetle"
    );
    let mut outputs = Vec::new();
    for (index, expected_id) in expected.iter().enumerate() {
        let component = &manifest.components[index];
        anyhow::ensure!(
            component.id == *expected_id,
            "runtime manifest component order mismatch"
        );
        validate_relative_posix_path(&component.path)?;
        let path = runtime_root.join(component.path.replace('/', std::path::MAIN_SEPARATOR_STR));
        anyhow::ensure!(path.is_file(), "runtime component file is missing");
        anyhow::ensure!(
            sha256_file(&path)? == component.sha256,
            "runtime component hash mismatch"
        );
        if component.id == "tigerbeetle" {
            validate_windows_x64_pe(&path)?;
        }
        validate_source(component)?;
        match component.id.as_str() {
            "api" => anyhow::ensure!(
                component.license_path.is_none(),
                "api licensePath must be null"
            ),
            "sqlite" | "tigerbeetle" => {
                let license_path = component
                    .license_path
                    .as_ref()
                    .ok_or_else(|| anyhow::anyhow!("third-party component missing licensePath"))?;
                validate_relative_posix_path(license_path)?;
                anyhow::ensure!(
                    runtime_root
                        .join(license_path.replace('/', std::path::MAIN_SEPARATOR_STR))
                        .is_file(),
                    "third-party license file missing"
                );
            }
            _ => anyhow::bail!("unsupported runtime component"),
        }
        outputs.push(ComponentOutput {
            id: component.id.clone(),
            version: component.version.clone(),
            state: "verified".to_string(),
        });
    }
    anyhow::ensure!(
        runtime_root.join("THIRD-PARTY-NOTICES.txt").is_file(),
        "THIRD-PARTY-NOTICES.txt is missing"
    );
    Ok(outputs)
}

fn validate_source(component: &ManifestComponent) -> anyhow::Result<()> {
    match component.id.as_str() {
        "api" => {
            anyhow::ensure!(component.source.kind == "first-party-build");
            anyhow::ensure!(component.source.url.is_none());
            anyhow::ensure!(
                component
                    .source
                    .revision
                    .as_deref()
                    .is_some_and(|value| value.len() == 40),
                "api source revision must be an audited commit"
            );
        }
        "sqlite" => {
            anyhow::ensure!(component.source.kind == "official-source");
            anyhow::ensure!(component
                .source
                .url
                .as_deref()
                .is_some_and(|url| url.starts_with("https://")));
            anyhow::ensure!(
                component.source.revision.as_deref() == Some(component.version.as_str())
            );
        }
        "tigerbeetle" => {
            anyhow::ensure!(component.source.kind == "official-release");
            anyhow::ensure!(component
                .source
                .url
                .as_deref()
                .is_some_and(|url| url.starts_with("https://")));
            anyhow::ensure!(
                component.source.revision.as_deref() == Some(component.version.as_str())
            );
        }
        _ => anyhow::bail!("unsupported runtime component source"),
    }
    Ok(())
}

fn validate_relative_posix_path(path: &str) -> anyhow::Result<()> {
    anyhow::ensure!(!path.is_empty(), "manifest path is empty");
    anyhow::ensure!(!path.starts_with('/'), "manifest path must be relative");
    anyhow::ensure!(
        !path.contains('\\'),
        "manifest path must use POSIX separators"
    );
    anyhow::ensure!(
        !path.contains(':'),
        "manifest path must not contain a drive prefix"
    );
    for part in path.split('/') {
        anyhow::ensure!(
            !part.is_empty() && part != "." && part != "..",
            "manifest path is unsafe"
        );
    }
    Ok(())
}

fn validate_windows_x64_pe(path: &Path) -> anyhow::Result<()> {
    let bytes = fs::read(path)?;
    anyhow::ensure!(
        bytes.len() >= 0x40 && &bytes[0..2] == b"MZ",
        "TigerBeetle executable is not a PE image"
    );
    let pe_offset =
        u32::from_le_bytes(bytes[0x3c..0x40].try_into().expect("fixed PE offset")) as usize;
    anyhow::ensure!(
        pe_offset
            .checked_add(6)
            .is_some_and(|end| end <= bytes.len()),
        "TigerBeetle PE header is truncated"
    );
    anyhow::ensure!(
        &bytes[pe_offset..pe_offset + 4] == b"PE\0\0",
        "TigerBeetle executable is missing the PE signature"
    );
    let machine = u16::from_le_bytes([bytes[pe_offset + 4], bytes[pe_offset + 5]]);
    anyhow::ensure!(
        machine == 0x8664,
        "TigerBeetle executable is not Windows x64"
    );
    Ok(())
}

fn spawn_api(config: &SmokeConfig) -> anyhow::Result<SmokeChild> {
    let mut args = config.api_prefix_args.clone();
    args.extend([
        OsString::from("serve"),
        OsString::from("--runtime"),
        OsString::from("managed"),
        OsString::from("--runtime-root"),
        config.runtime_root.as_os_str().to_os_string(),
        OsString::from("--data-root"),
        config.data_root.as_os_str().to_os_string(),
        OsString::from("--allowed-origin"),
        OsString::from(PACKAGED_ORIGIN),
        OsString::from("--handshake"),
        OsString::from("stdout-v1"),
    ]);
    let mut child = Command::new(&config.api_program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()?;
    let job = platform::contain(&mut child)?;
    Ok(SmokeChild { child, job })
}

fn read_handshake(child: &mut Child, timeout: Duration) -> anyhow::Result<Handshake> {
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| anyhow::anyhow!("stdout pipe missing"))?;
    let (tx, rx) = std::sync::mpsc::channel();
    thread::spawn(move || {
        let result = read_bounded_line(stdout, HANDSHAKE_MAX_BYTES);
        let _ = tx.send(result);
    });
    let line = rx.recv_timeout(timeout)??;
    let payload = line
        .strip_prefix(HANDSHAKE_PREFIX)
        .ok_or_else(|| anyhow::anyhow!("missing handshake prefix"))?;
    let handshake: Handshake = serde_json::from_str(payload)?;
    anyhow::ensure!(
        handshake.protocol_version == 1,
        "invalid handshake protocol"
    );
    validate_loopback_url(&handshake.api_url)?;
    validate_token(&handshake.app_token)?;
    validate_token(&handshake.supervisor_token)?;
    anyhow::ensure!(
        handshake.app_token != handshake.supervisor_token,
        "smoke tokens must be distinct"
    );
    Ok(handshake)
}

fn wait_ready_and_status(handshake: &Handshake) -> anyhow::Result<Vec<StatusComponent>> {
    let started = Instant::now();
    loop {
        if started.elapsed() > READY_TIMEOUT {
            anyhow::bail!("API did not become ready within 60 seconds");
        }
        if let Ok(response) = http_request(&handshake.api_url, "GET", "/health/ready", None) {
            if response.status == 200 {
                let ready: ReadyBody = serde_json::from_str(&response.body)?;
                if ready.status == "ready" {
                    break;
                }
            }
        }
        thread::sleep(Duration::from_secs(1));
    }
    let response = http_request(
        &handshake.api_url,
        "GET",
        "/api/v1/system/status",
        Some(&handshake.app_token),
    )?;
    anyhow::ensure!(response.status == 200, "status endpoint did not return 200");
    let status: StatusBody = serde_json::from_str(&response.body)?;
    validate_status(&status)?;
    Ok(status.components)
}

fn send_shutdown(handshake: &Handshake) -> anyhow::Result<()> {
    let response = http_request(
        &handshake.api_url,
        "POST",
        "/api/v1/system/shutdown",
        Some(&handshake.supervisor_token),
    )?;
    anyhow::ensure!(
        response.status == 202,
        "shutdown returned unexpected status"
    );
    Ok(())
}

struct HttpResponse {
    status: u16,
    body: String,
}

fn http_request(
    api_url: &str,
    method: &str,
    path: &str,
    token: Option<&str>,
) -> anyhow::Result<HttpResponse> {
    let parsed = Url::parse(api_url)?;
    let host = parsed
        .host_str()
        .ok_or_else(|| anyhow::anyhow!("API URL missing host"))?;
    let port = parsed
        .port()
        .ok_or_else(|| anyhow::anyhow!("API URL missing port"))?;
    let mut stream = TcpStream::connect((host, port))?;
    stream.set_read_timeout(Some(Duration::from_secs(10)))?;
    stream.set_write_timeout(Some(Duration::from_secs(10)))?;
    let auth = token
        .map(|token| format!("Authorization: Bearer {token}\r\n"))
        .unwrap_or_default();
    let request = format!(
        "{method} {path} HTTP/1.1\r\nHost: {host}:{port}\r\nOrigin: {PACKAGED_ORIGIN}\r\n{auth}Content-Length: 0\r\nConnection: close\r\n\r\n"
    );
    stream.write_all(request.as_bytes())?;
    let mut response = String::new();
    stream.read_to_string(&mut response)?;
    parse_http_response(&response)
}

fn parse_http_response(response: &str) -> anyhow::Result<HttpResponse> {
    let (head, body) = response
        .split_once("\r\n\r\n")
        .ok_or_else(|| anyhow::anyhow!("HTTP response missing body separator"))?;
    let status = head
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .ok_or_else(|| anyhow::anyhow!("HTTP response missing status"))?
        .parse()?;
    Ok(HttpResponse {
        status,
        body: body.to_string(),
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
    anyhow::ensure!(parsed.port().is_some(), "API URL must include port");
    anyhow::ensure!(parsed.username().is_empty() && parsed.password().is_none());
    anyhow::ensure!(parsed.path() == "/");
    anyhow::ensure!(parsed.query().is_none() && parsed.fragment().is_none());
    Ok(())
}

fn validate_token(token: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        token.len() == 43
            && token
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_'),
        "handshake token is not 32-byte unpadded base64url"
    );
    Ok(())
}

fn read_bounded_line(mut reader: impl Read, max_bytes: usize) -> anyhow::Result<String> {
    let mut bytes = Vec::new();
    let mut buffer = [0u8; 1];
    while bytes.len() <= max_bytes {
        match reader.read(&mut buffer)? {
            0 => break,
            _ => {
                bytes.push(buffer[0]);
                if buffer[0] == b'\n' {
                    break;
                }
            }
        }
    }
    anyhow::ensure!(bytes.len() <= max_bytes, "handshake line exceeds 16 KiB");
    anyhow::ensure!(
        bytes.last().is_some_and(|byte| *byte == b'\n'),
        "handshake line was not terminated"
    );
    Ok(String::from_utf8(bytes)?
        .trim_end_matches(['\r', '\n'])
        .to_string())
}

fn ensure_under_temp(path: &Path) -> anyhow::Result<()> {
    let path = path.components().collect::<PathBuf>();
    let temp = std::env::temp_dir().components().collect::<PathBuf>();
    anyhow::ensure!(
        path.starts_with(&temp),
        "smoke data root must be under the system temporary directory"
    );
    Ok(())
}

fn wait_for_exit(child: &mut Child, timeout: Duration) -> bool {
    let started = Instant::now();
    while started.elapsed() < timeout {
        if child.try_wait().ok().flatten().is_some() {
            return true;
        }
        thread::sleep(Duration::from_millis(20));
    }
    false
}

fn sha256_file(path: &Path) -> anyhow::Result<String> {
    let bytes = fs::read(path)?;
    Ok(sha256_bytes(&bytes))
}

#[cfg(windows)]
fn sha256_bytes(bytes: &[u8]) -> String {
    use std::{ffi::c_void, ptr};

    type BcryptHandle = *mut c_void;
    type NtStatus = i32;
    const BCRYPT_SHA256_ALGORITHM: &[u16] = &[
        b'S' as u16,
        b'H' as u16,
        b'A' as u16,
        b'2' as u16,
        b'5' as u16,
        b'6' as u16,
        0,
    ];

    #[link(name = "bcrypt")]
    extern "system" {
        fn BCryptOpenAlgorithmProvider(
            algorithm: *mut BcryptHandle,
            psz_alg_id: *const u16,
            psz_implementation: *const u16,
            flags: u32,
        ) -> NtStatus;
        fn BCryptCreateHash(
            algorithm: BcryptHandle,
            hash: *mut BcryptHandle,
            hash_object: *mut u8,
            hash_object_length: u32,
            secret: *const u8,
            secret_length: u32,
            flags: u32,
        ) -> NtStatus;
        fn BCryptHashData(
            hash: BcryptHandle,
            input: *const u8,
            input_length: u32,
            flags: u32,
        ) -> NtStatus;
        fn BCryptFinishHash(
            hash: BcryptHandle,
            output: *mut u8,
            output_length: u32,
            flags: u32,
        ) -> NtStatus;
        fn BCryptDestroyHash(hash: BcryptHandle) -> NtStatus;
        fn BCryptCloseAlgorithmProvider(algorithm: BcryptHandle, flags: u32) -> NtStatus;
    }

    unsafe {
        let mut algorithm = ptr::null_mut();
        assert_eq!(
            BCryptOpenAlgorithmProvider(
                &mut algorithm,
                BCRYPT_SHA256_ALGORITHM.as_ptr(),
                ptr::null(),
                0,
            ),
            0
        );
        let mut hash = ptr::null_mut();
        assert_eq!(
            BCryptCreateHash(algorithm, &mut hash, ptr::null_mut(), 0, ptr::null(), 0, 0,),
            0
        );
        assert_eq!(
            BCryptHashData(hash, bytes.as_ptr(), bytes.len() as u32, 0),
            0
        );
        let mut output = [0_u8; 32];
        assert_eq!(BCryptFinishHash(hash, output.as_mut_ptr(), 32, 0), 0);
        let _ = BCryptDestroyHash(hash);
        let _ = BCryptCloseAlgorithmProvider(algorithm, 0);
        output.iter().map(|byte| format!("{byte:02x}")).collect()
    }
}

#[cfg(not(windows))]
fn sha256_bytes(_bytes: &[u8]) -> String {
    "unsupported-non-windows".to_string()
}

pub fn self_test() -> anyhow::Result<()> {
    anyhow::ensure!(HANDSHAKE_TIMEOUT == Duration::from_secs(15));
    anyhow::ensure!(READY_TIMEOUT == Duration::from_secs(60));
    anyhow::ensure!(SHUTDOWN_TIMEOUT == Duration::from_secs(20));
    anyhow::ensure!(PROCESS_REAP_TIMEOUT == Duration::from_secs(5));
    anyhow::ensure!(TARGET == "x86_64-pc-windows-msvc");
    Ok(())
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
            let ok = AssignProcessToJobObject(job, child.as_raw_handle() as Handle);
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

        pub fn wait_until_empty(&self, timeout: Duration) -> anyhow::Result<()> {
            let started = Instant::now();
            loop {
                if self.active_processes()? == 0 {
                    return Ok(());
                }
                if started.elapsed() >= timeout {
                    anyhow::bail!("contained job still has active descendants");
                }
                thread::sleep(Duration::from_millis(20));
            }
        }

        fn active_processes(&self) -> anyhow::Result<u32> {
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
    use std::ffi::OsString;
    use std::io::Cursor;
    use tempfile::TempDir;

    fn write_file(path: &Path, bytes: &[u8]) {
        fs::create_dir_all(path.parent().expect("parent")).expect("parent dir");
        fs::write(path, bytes).expect("fixture write");
    }

    fn minimal_windows_x64_pe() -> Vec<u8> {
        let mut bytes = vec![0u8; 0x98];
        bytes[0..2].copy_from_slice(b"MZ");
        bytes[0x3c..0x40].copy_from_slice(&(0x80u32).to_le_bytes());
        bytes[0x80..0x84].copy_from_slice(b"PE\0\0");
        bytes[0x84..0x86].copy_from_slice(&(0x8664u16).to_le_bytes());
        bytes
    }

    fn minimal_windows_i386_pe() -> Vec<u8> {
        let mut bytes = minimal_windows_x64_pe();
        bytes[0x84..0x86].copy_from_slice(&(0x014cu16).to_le_bytes());
        bytes
    }

    fn fixture_runtime() -> TempDir {
        let temp = TempDir::new().expect("temp dir");
        let root = temp.path();
        let api = b"api";
        let sqlite = b"sqlite";
        let tigerbeetle = minimal_windows_x64_pe();
        write_file(&root.join("api/voyage-vii-api.exe"), api);
        write_file(&root.join("sqlite/sqlite3.c"), sqlite);
        write_file(&root.join("tigerbeetle/tigerbeetle.exe"), &tigerbeetle);
        write_file(&root.join("licenses/sqlite/PUBLIC-DOMAIN.txt"), b"sqlite");
        write_file(&root.join("licenses/tigerbeetle/LICENSE"), b"tb");
        write_file(&root.join("THIRD-PARTY-NOTICES.txt"), b"notices");
        let manifest = serde_json::json!({
            "schemaVersion": 1,
            "productVersion": PRODUCT_VERSION,
            "target": TARGET,
            "components": [
                {
                    "id": "api",
                    "version": PRODUCT_VERSION,
                    "path": "api/voyage-vii-api.exe",
                    "sha256": sha256_bytes(api),
                    "licensePath": null,
                    "source": { "kind": "first-party-build", "url": null, "revision": "0123456789abcdef0123456789abcdef01234567" }
                },
                {
                    "id": "sqlite",
                    "version": "3.53.3",
                    "path": "sqlite/sqlite3.c",
                    "sha256": sha256_bytes(sqlite),
                    "licensePath": "licenses/sqlite/PUBLIC-DOMAIN.txt",
                    "source": { "kind": "official-source", "url": "https://www.sqlite.org/2026/sqlite-amalgamation-3530300.zip", "revision": "3.53.3" }
                },
                {
                    "id": "tigerbeetle",
                    "version": "0.17.7",
                    "path": "tigerbeetle/tigerbeetle.exe",
                    "sha256": sha256_bytes(&tigerbeetle),
                    "licensePath": "licenses/tigerbeetle/LICENSE",
                    "source": { "kind": "official-release", "url": "https://github.com/tigerbeetle/tigerbeetle/releases/download/0.17.7/tigerbeetle-x86_64-windows.zip", "revision": "0.17.7" }
                }
            ]
        });
        fs::write(
            root.join("manifest.json"),
            serde_json::to_string_pretty(&manifest).expect("manifest json"),
        )
        .expect("manifest write");
        temp
    }

    #[test]
    fn parses_smoke_args_only() {
        assert!(parse_args(Vec::<OsString>::new()).expect("parse").is_none());
        assert!(parse_args([OsString::from("--help")])
            .expect("parse")
            .is_none());
        let data = std::env::temp_dir().join("voyage-smoke-test");
        let parsed = parse_args([
            OsString::from("--smoke-test"),
            OsString::from("--data-root"),
            data.as_os_str().to_os_string(),
        ])
        .expect("parse")
        .expect("smoke args");
        assert_eq!(parsed.data_root, data);
    }

    #[test]
    fn rejects_non_temp_or_relative_data_root() {
        assert!(parse_args([
            OsString::from("--smoke-test"),
            OsString::from("--data-root"),
            OsString::from("relative"),
        ])
        .is_err());
        assert!(parse_args([
            OsString::from("--smoke-test"),
            OsString::from("--data-root"),
            OsString::from("C:\\VoyageData"),
        ])
        .is_err());
    }

    #[test]
    fn validates_runtime_manifest_and_hashes() {
        let runtime = fixture_runtime();
        let components = validate_runtime(runtime.path()).expect("valid runtime");
        assert_eq!(components.len(), 3);
        assert_eq!(components[0].id, "api");
        fs::write(runtime.path().join("sqlite/sqlite3.c"), b"changed").expect("mutate");
        assert!(validate_runtime(runtime.path()).is_err());
    }

    #[test]
    fn rejects_non_x64_tigerbeetle_executable() {
        let temp = TempDir::new().expect("temp dir");
        let path = temp.path().join("tigerbeetle.exe");
        fs::write(&path, minimal_windows_i386_pe()).expect("fixture write");
        assert!(validate_windows_x64_pe(&path).is_err());
    }

    #[test]
    fn rejects_unsafe_manifest_paths() {
        for path in ["../api.exe", "C:/api.exe", "/api.exe", "api\\voyage.exe"] {
            assert!(validate_relative_posix_path(path).is_err());
        }
        assert!(validate_relative_posix_path("api/voyage-vii-api.exe").is_ok());
    }

    #[test]
    fn parses_http_status_and_body() {
        let response = parse_http_response("HTTP/1.1 202 Accepted\r\nContent-Length: 2\r\n\r\n{}")
            .expect("http response");
        assert_eq!(response.status, 202);
        assert_eq!(response.body, "{}");
    }

    #[test]
    fn validates_handshake_token_shape_and_line_bound() {
        let token = "A".repeat(43);
        validate_token(&token).expect("valid token");
        assert!(validate_token(&(token.clone() + "=")).is_err());
        assert!(validate_token("short").is_err());

        let line = "VOYAGE_VII_HANDSHAKE {}\n";
        assert_eq!(
            read_bounded_line(Cursor::new(line), HANDSHAKE_MAX_BYTES).expect("bounded line"),
            "VOYAGE_VII_HANDSHAKE {}"
        );
        let oversized = "A".repeat(HANDSHAKE_MAX_BYTES + 1) + "\n";
        assert!(read_bounded_line(Cursor::new(oversized), HANDSHAKE_MAX_BYTES).is_err());
    }

    #[test]
    fn validates_status_contract() {
        let status = StatusBody {
            schema_version: 1,
            request_id: "request".to_string(),
            overall_state: "ready".to_string(),
            components: vec![
                StatusComponent {
                    id: "sqlite".to_string(),
                    version: "3.53.3".to_string(),
                    state: "healthy".to_string(),
                },
                StatusComponent {
                    id: "tigerbeetle".to_string(),
                    version: "0.17.7".to_string(),
                    state: "healthy".to_string(),
                },
            ],
        };
        validate_status(&status).expect("valid status");

        let mut degraded = status;
        degraded.components[1].state = "unhealthy".to_string();
        assert!(validate_status(&degraded).is_err());
    }
}
