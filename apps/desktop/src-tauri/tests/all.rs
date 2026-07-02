#[test]
fn desktop_foundation_contracts_are_static() {
    let config = include_str!("../tauri.conf.json");
    assert!(config.contains("\"productName\": \"Voyage VII\""));
    assert!(config.contains("\"identifier\": \"io.github.jac27719.voyage-vii\""));

    let capabilities = include_str!("../capabilities/default.json");
    assert!(capabilities.contains("core:default"));
    assert!(capabilities.contains("allow-get-runtime-snapshot"));
    assert!(capabilities.contains("allow-open-logs"));
    assert!(!capabilities.contains("shell:"));
    assert!(!capabilities.contains("fs:"));
    assert!(!capabilities.contains("process:"));

    let main = include_str!("../src/main.rs");
    assert!(main.contains("get_runtime_snapshot"));
    assert!(main.contains("open_logs"));

    let permissions = include_str!("../permissions/app-commands.toml");
    assert!(permissions.contains("commands.allow = [\"get_runtime_snapshot\"]"));
    assert!(permissions.contains("commands.allow = [\"open_logs\"]"));
}
