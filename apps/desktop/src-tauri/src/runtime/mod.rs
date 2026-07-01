use serde::Serialize;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum RuntimeState {
    Launching,
    Connected,
    Restarting,
    Failed,
    Stopping,
}

const RUNTIME_STATES: [RuntimeState; 5] = [
    RuntimeState::Launching,
    RuntimeState::Connected,
    RuntimeState::Restarting,
    RuntimeState::Failed,
    RuntimeState::Stopping,
];

pub fn initial_snapshot() -> crate::RuntimeSnapshot {
    crate::RuntimeSnapshot {
        generation: 0,
        state: RuntimeState::Launching,
        connection: None,
        error: None,
    }
}

pub fn self_test() -> anyhow::Result<()> {
    anyhow::ensure!(RUNTIME_STATES.len() == 5, "runtime state contract changed");
    let snapshot = initial_snapshot();
    anyhow::ensure!(snapshot.generation == 0);
    anyhow::ensure!(snapshot.connection.is_none());
    Ok(())
}
