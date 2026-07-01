pub fn self_test() -> anyhow::Result<()> {
    anyhow::ensure!(
        cfg!(target_os = "windows"),
        "Windows is the only current native gate"
    );
    anyhow::ensure!(
        cfg!(target_arch = "x86_64"),
        "Windows x64 is the only current native architecture"
    );
    Ok(())
}
