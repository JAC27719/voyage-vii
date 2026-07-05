use std::collections::BTreeSet;

const PLATFORM_SQLITE_NAMESPACES: &[&str] = &[
    "audit",
    "grants",
    "import_export",
    "local_users",
    "module_registry",
    "simulation_runs",
];

const ALLOWED_CAPABILITIES: &[&str] = &[
    "read", "create", "update", "archive", "search", "import", "export", "simulate", "report",
];

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CallerSurface {
    Ui,
    Cli,
    Mcp,
    Internal,
}

impl CallerSurface {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Ui => "ui",
            Self::Cli => "cli",
            Self::Mcp => "mcp",
            Self::Internal => "internal",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LifecycleState {
    Available,
    Disabled,
    Unavailable,
    MigrationRequired,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Availability {
    Available,
    Reserved,
    Deferred,
    Unavailable,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CallerIdentity {
    pub surface: CallerSurface,
    pub caller_id: &'static str,
    pub local_user_id: &'static str,
    pub request_id: &'static str,
    pub invocation_context: &'static str,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CapabilityDeclaration {
    pub capability: &'static str,
    pub availability: Availability,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OperationDeclaration {
    pub id: &'static str,
    pub required_capability: &'static str,
    pub required_scope: &'static str,
    pub request_schema_id: &'static str,
    pub response_schema_id: &'static str,
    pub audit_object_policy: &'static str,
    pub availability: Availability,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StorageNamespaceDeclaration {
    pub sqlite_namespace: &'static str,
    pub sqlite_owner: &'static str,
    pub platform_user_reference: &'static str,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SpecialtyEngineDeclaration {
    pub engine_id: &'static str,
    pub owning_module_id: &'static str,
    pub purpose: &'static str,
    pub exclusive: bool,
    pub lifecycle_owner: &'static str,
    pub provenance_source: &'static str,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AdapterDeclaration {
    pub kind: &'static str,
    pub source_root: &'static str,
    pub runtime_mode: &'static str,
    pub lifecycle_owner: &'static str,
    pub health_model: &'static str,
    pub compatibility_boundary: &'static str,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ReportDeclaration {
    pub id: &'static str,
    pub availability: Availability,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EventDeclaration {
    pub id: &'static str,
    pub availability: Availability,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ImportExportDeclaration {
    pub import_format_id: &'static str,
    pub import_availability: Availability,
    pub export_format_id: &'static str,
    pub export_availability: Availability,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SimulationDeclaration {
    pub capability: &'static str,
    pub availability: Availability,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ModuleRegistration {
    pub id: &'static str,
    pub display_name: &'static str,
    pub version: &'static str,
    pub lifecycle_state: LifecycleState,
    pub product_prd_path: &'static str,
    pub source_root: &'static str,
    pub capabilities: &'static [CapabilityDeclaration],
    pub operations: &'static [OperationDeclaration],
    pub reports: &'static [ReportDeclaration],
    pub events: &'static [EventDeclaration],
    pub storage: &'static [StorageNamespaceDeclaration],
    pub specialty_engines: &'static [SpecialtyEngineDeclaration],
    pub adapter: AdapterDeclaration,
    pub import_export: ImportExportDeclaration,
    pub simulation: SimulationDeclaration,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RegistryValidationError {
    DuplicateModuleId(String),
    UnknownCapability(String),
    UndeclaredOperationCapability {
        operation: String,
        capability: String,
    },
    PlatformNamespaceClaimed {
        module_id: String,
        namespace: String,
    },
    DuplicateSqliteNamespaceOwner(String),
    NonFinanceTigerBeetleOwner(String),
    AdapterSourceOutsideModule {
        module_id: String,
        source_root: String,
    },
    InvalidOperationSchema {
        operation: String,
        schema_id: String,
    },
    UnsafeRegistryValue {
        field: String,
        value: String,
    },
}

static FINANCE_CAPABILITIES: &[CapabilityDeclaration] = &[
    CapabilityDeclaration {
        capability: "read",
        availability: Availability::Available,
    },
    CapabilityDeclaration {
        capability: "create",
        availability: Availability::Reserved,
    },
    CapabilityDeclaration {
        capability: "update",
        availability: Availability::Reserved,
    },
    CapabilityDeclaration {
        capability: "archive",
        availability: Availability::Reserved,
    },
    CapabilityDeclaration {
        capability: "search",
        availability: Availability::Reserved,
    },
    CapabilityDeclaration {
        capability: "import",
        availability: Availability::Deferred,
    },
    CapabilityDeclaration {
        capability: "export",
        availability: Availability::Deferred,
    },
    CapabilityDeclaration {
        capability: "simulate",
        availability: Availability::Deferred,
    },
    CapabilityDeclaration {
        capability: "report",
        availability: Availability::Reserved,
    },
];

static FINANCE_OPERATIONS: &[OperationDeclaration] = &[
    OperationDeclaration {
        id: "runtime_status",
        required_capability: "read",
        required_scope: "runtime.status",
        request_schema_id: "finance.runtime_status.request.reserved",
        response_schema_id: "finance.runtime_status.response.reserved",
        audit_object_policy: "metadata_only",
        availability: Availability::Available,
    },
    OperationDeclaration {
        id: "list_accounts",
        required_capability: "read",
        required_scope: "finance.accounts",
        request_schema_id: "finance.list_accounts.request.reserved",
        response_schema_id: "finance.list_accounts.response.reserved",
        audit_object_policy: "stable_object_ids_only",
        availability: Availability::Reserved,
    },
    OperationDeclaration {
        id: "create_account",
        required_capability: "create",
        required_scope: "finance.accounts",
        request_schema_id: "finance.create_account.request.reserved",
        response_schema_id: "finance.create_account.response.reserved",
        audit_object_policy: "stable_object_ids_only",
        availability: Availability::Reserved,
    },
    OperationDeclaration {
        id: "post_entry",
        required_capability: "create",
        required_scope: "finance.entries",
        request_schema_id: "finance.post_entry.request.reserved",
        response_schema_id: "finance.post_entry.response.reserved",
        audit_object_policy: "stable_object_ids_only",
        availability: Availability::Reserved,
    },
    OperationDeclaration {
        id: "archive_account",
        required_capability: "archive",
        required_scope: "finance.accounts",
        request_schema_id: "finance.archive_account.request.reserved",
        response_schema_id: "finance.archive_account.response.reserved",
        audit_object_policy: "stable_object_ids_only",
        availability: Availability::Reserved,
    },
    OperationDeclaration {
        id: "search_entries",
        required_capability: "search",
        required_scope: "finance.entries",
        request_schema_id: "finance.search_entries.request.reserved",
        response_schema_id: "finance.search_entries.response.reserved",
        audit_object_policy: "stable_object_ids_only",
        availability: Availability::Reserved,
    },
    OperationDeclaration {
        id: "balance_sheet",
        required_capability: "report",
        required_scope: "finance.reports.balance_sheet",
        request_schema_id: "finance.balance_sheet.request.reserved",
        response_schema_id: "finance.balance_sheet.response.reserved",
        audit_object_policy: "stable_object_ids_only",
        availability: Availability::Reserved,
    },
    OperationDeclaration {
        id: "period_activity",
        required_capability: "report",
        required_scope: "finance.reports.period_activity",
        request_schema_id: "finance.period_activity.request.reserved",
        response_schema_id: "finance.period_activity.response.reserved",
        audit_object_policy: "stable_object_ids_only",
        availability: Availability::Reserved,
    },
    OperationDeclaration {
        id: "budget_variance",
        required_capability: "report",
        required_scope: "finance.reports.budget_variance",
        request_schema_id: "finance.budget_variance.request.reserved",
        response_schema_id: "finance.budget_variance.response.reserved",
        audit_object_policy: "stable_object_ids_only",
        availability: Availability::Reserved,
    },
    OperationDeclaration {
        id: "export_finance",
        required_capability: "export",
        required_scope: "finance.export",
        request_schema_id: "finance.export.request.deferred",
        response_schema_id: "finance.export.response.deferred",
        audit_object_policy: "metadata_only",
        availability: Availability::Deferred,
    },
    OperationDeclaration {
        id: "import_finance",
        required_capability: "import",
        required_scope: "finance.import",
        request_schema_id: "finance.import.request.deferred",
        response_schema_id: "finance.import.response.deferred",
        audit_object_policy: "metadata_only",
        availability: Availability::Deferred,
    },
    OperationDeclaration {
        id: "run_forecast",
        required_capability: "simulate",
        required_scope: "finance.simulation.forecast",
        request_schema_id: "finance.run_forecast.request.deferred",
        response_schema_id: "finance.run_forecast.response.deferred",
        audit_object_policy: "metadata_only",
        availability: Availability::Deferred,
    },
];

static FINANCE_REPORTS: &[ReportDeclaration] = &[
    ReportDeclaration {
        id: "balance_sheet",
        availability: Availability::Reserved,
    },
    ReportDeclaration {
        id: "period_activity",
        availability: Availability::Reserved,
    },
    ReportDeclaration {
        id: "budget_variance",
        availability: Availability::Reserved,
    },
];

static FINANCE_EVENTS: &[EventDeclaration] = &[
    EventDeclaration {
        id: "finance.lifecycle_changed",
        availability: Availability::Reserved,
    },
    EventDeclaration {
        id: "finance.account_changed",
        availability: Availability::Reserved,
    },
    EventDeclaration {
        id: "finance.entry_posted",
        availability: Availability::Reserved,
    },
    EventDeclaration {
        id: "finance.period_changed",
        availability: Availability::Reserved,
    },
    EventDeclaration {
        id: "finance.budget_changed",
        availability: Availability::Reserved,
    },
];

static FINANCE_STORAGE: &[StorageNamespaceDeclaration] = &[StorageNamespaceDeclaration {
    sqlite_namespace: "finance",
    sqlite_owner: "finance",
    platform_user_reference: "required",
}];

static FINANCE_SPECIALTY_ENGINES: &[SpecialtyEngineDeclaration] = &[SpecialtyEngineDeclaration {
    engine_id: "tigerbeetle",
    owning_module_id: "finance",
    purpose: "ledger_balances_and_transfers",
    exclusive: true,
    lifecycle_owner: "platform",
    provenance_source: "packaged_runtime_manifest",
}];

static FINANCE_MODULES: &[ModuleRegistration] = &[ModuleRegistration {
    id: "finance",
    display_name: "Finance",
    version: "0.1.0-proposed",
    lifecycle_state: LifecycleState::Available,
    product_prd_path: "modules/finance/spec/PRD.md",
    source_root: "modules/finance",
    capabilities: FINANCE_CAPABILITIES,
    operations: FINANCE_OPERATIONS,
    reports: FINANCE_REPORTS,
    events: FINANCE_EVENTS,
    storage: FINANCE_STORAGE,
    specialty_engines: FINANCE_SPECIALTY_ENGINES,
    adapter: AdapterDeclaration {
        kind: "zig-api",
        source_root: "modules/finance/adapters/zig-api/",
        runtime_mode: "managed_by_platform_lifecycle",
        lifecycle_owner: "platform",
        health_model: "compatibility_runtime_status",
        compatibility_boundary: "private_adapter_routes_are_implementation_details",
    },
    import_export: ImportExportDeclaration {
        import_format_id: "finance.import.deferred",
        import_availability: Availability::Deferred,
        export_format_id: "finance.export.deferred",
        export_availability: Availability::Deferred,
    },
    simulation: SimulationDeclaration {
        capability: "simulate",
        availability: Availability::Deferred,
    },
}];

pub fn registered_modules() -> &'static [ModuleRegistration] {
    FINANCE_MODULES
}

pub fn reserved_caller_surfaces() -> &'static [CallerSurface] {
    &[
        CallerSurface::Ui,
        CallerSurface::Cli,
        CallerSurface::Mcp,
        CallerSurface::Internal,
    ]
}

pub fn validate_registry(modules: &[ModuleRegistration]) -> Result<(), RegistryValidationError> {
    let mut module_ids = BTreeSet::new();
    let mut sqlite_namespaces = BTreeSet::new();

    for module in modules {
        if !module_ids.insert(module.id) {
            return Err(RegistryValidationError::DuplicateModuleId(
                module.id.to_string(),
            ));
        }

        validate_string_fields(module)?;

        let mut declared_capabilities = BTreeSet::new();
        for capability in module.capabilities {
            if !ALLOWED_CAPABILITIES.contains(&capability.capability) {
                return Err(RegistryValidationError::UnknownCapability(
                    capability.capability.to_string(),
                ));
            }
            declared_capabilities.insert(capability.capability);
        }

        for operation in module.operations {
            if !declared_capabilities.contains(operation.required_capability) {
                return Err(RegistryValidationError::UndeclaredOperationCapability {
                    operation: operation.id.to_string(),
                    capability: operation.required_capability.to_string(),
                });
            }
            validate_operation_schema(operation, operation.request_schema_id)?;
            validate_operation_schema(operation, operation.response_schema_id)?;
        }

        for storage in module.storage {
            if PLATFORM_SQLITE_NAMESPACES.contains(&storage.sqlite_namespace) {
                return Err(RegistryValidationError::PlatformNamespaceClaimed {
                    module_id: module.id.to_string(),
                    namespace: storage.sqlite_namespace.to_string(),
                });
            }
            if !sqlite_namespaces.insert(storage.sqlite_namespace) {
                return Err(RegistryValidationError::DuplicateSqliteNamespaceOwner(
                    storage.sqlite_namespace.to_string(),
                ));
            }
        }

        for engine in module.specialty_engines {
            if engine.engine_id == "tigerbeetle" && engine.owning_module_id != "finance" {
                return Err(RegistryValidationError::NonFinanceTigerBeetleOwner(
                    engine.owning_module_id.to_string(),
                ));
            }
        }

        if !adapter_source_is_under_module(module.source_root, module.adapter.source_root) {
            return Err(RegistryValidationError::AdapterSourceOutsideModule {
                module_id: module.id.to_string(),
                source_root: module.adapter.source_root.to_string(),
            });
        }
    }

    Ok(())
}

pub fn self_test() -> anyhow::Result<()> {
    validate_registry(registered_modules()).map_err(|err| anyhow::anyhow!("{err:?}"))?;
    anyhow::ensure!(reserved_caller_surfaces()
        .iter()
        .map(|surface| surface.as_str())
        .eq(["ui", "cli", "mcp", "internal"]));
    anyhow::ensure!(
        [
            LifecycleState::Available,
            LifecycleState::Disabled,
            LifecycleState::Unavailable,
            LifecycleState::MigrationRequired,
        ]
        .len()
            == 4
    );
    anyhow::ensure!(
        [
            Availability::Available,
            Availability::Reserved,
            Availability::Deferred,
            Availability::Unavailable,
        ]
        .len()
            == 4
    );
    let reserved_identity_shape = CallerIdentity {
        surface: CallerSurface::Internal,
        caller_id: "platform",
        local_user_id: "local-owner",
        request_id: "self-test",
        invocation_context: "static-registration",
    };
    anyhow::ensure!(reserved_identity_shape.surface == CallerSurface::Internal);
    anyhow::ensure!(registered_modules().len() == 1);
    anyhow::ensure!(registered_modules()[0].id == "finance");
    Ok(())
}

fn validate_string_fields(module: &ModuleRegistration) -> Result<(), RegistryValidationError> {
    let mut values = vec![
        ("module.id", module.id),
        ("module.display_name", module.display_name),
        ("module.version", module.version),
        ("module.product_prd_path", module.product_prd_path),
        ("module.source_root", module.source_root),
        ("adapter.kind", module.adapter.kind),
        ("adapter.source_root", module.adapter.source_root),
        ("adapter.runtime_mode", module.adapter.runtime_mode),
        ("adapter.lifecycle_owner", module.adapter.lifecycle_owner),
        ("adapter.health_model", module.adapter.health_model),
        (
            "adapter.compatibility_boundary",
            module.adapter.compatibility_boundary,
        ),
        (
            "import_export.import_format_id",
            module.import_export.import_format_id,
        ),
        (
            "import_export.export_format_id",
            module.import_export.export_format_id,
        ),
        ("simulation.capability", module.simulation.capability),
    ];

    for capability in module.capabilities {
        values.push(("capability.capability", capability.capability));
    }
    for operation in module.operations {
        values.extend([
            ("operation.id", operation.id),
            (
                "operation.required_capability",
                operation.required_capability,
            ),
            ("operation.required_scope", operation.required_scope),
            ("operation.request_schema_id", operation.request_schema_id),
            ("operation.response_schema_id", operation.response_schema_id),
            (
                "operation.audit_object_policy",
                operation.audit_object_policy,
            ),
        ]);
    }
    for report in module.reports {
        values.push(("report.id", report.id));
    }
    for event in module.events {
        values.push(("event.id", event.id));
    }
    for storage in module.storage {
        values.extend([
            ("storage.sqlite_namespace", storage.sqlite_namespace),
            ("storage.sqlite_owner", storage.sqlite_owner),
            (
                "storage.platform_user_reference",
                storage.platform_user_reference,
            ),
        ]);
    }
    for engine in module.specialty_engines {
        values.extend([
            ("specialty_engine.engine_id", engine.engine_id),
            ("specialty_engine.owning_module_id", engine.owning_module_id),
            ("specialty_engine.purpose", engine.purpose),
            ("specialty_engine.lifecycle_owner", engine.lifecycle_owner),
            (
                "specialty_engine.provenance_source",
                engine.provenance_source,
            ),
        ]);
    }

    for (field, value) in values {
        if registry_value_is_sensitive(value) {
            return Err(RegistryValidationError::UnsafeRegistryValue {
                field: field.to_string(),
                value: value.to_string(),
            });
        }
    }

    Ok(())
}

fn validate_operation_schema(
    operation: &OperationDeclaration,
    schema_id: &str,
) -> Result<(), RegistryValidationError> {
    if schema_id.is_empty()
        || !(schema_id.ends_with(".reserved")
            || schema_id.ends_with(".deferred")
            || schema_id.ends_with(".available"))
    {
        return Err(RegistryValidationError::InvalidOperationSchema {
            operation: operation.id.to_string(),
            schema_id: schema_id.to_string(),
        });
    }
    Ok(())
}

fn adapter_source_is_under_module(module_root: &str, adapter_source_root: &str) -> bool {
    let module_root = module_root.trim_end_matches('/');
    let adapter_source_root = adapter_source_root.trim_end_matches('/');
    adapter_source_root
        .strip_prefix(module_root)
        .is_some_and(|remaining| remaining.starts_with('/') && remaining.len() > 1)
}

fn registry_value_is_sensitive(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    lower.contains("token")
        || lower.contains("credential")
        || lower.contains("password")
        || lower.contains("authorization:")
        || lower.contains("supervisor")
        || lower.contains("appsecret")
        || lower.contains("database=")
        || lower.contains("data source=")
        || lower.contains("postgres://")
        || lower.contains("postgresql://")
        || lower.contains("mysql://")
        || lower.contains("sqlite://")
        || lower.contains("http://")
        || lower.contains("https://")
        || contains_local_absolute_path(value)
}

fn contains_local_absolute_path(value: &str) -> bool {
    let bytes = value.as_bytes();
    value.starts_with('/')
        || bytes.windows(3).any(|window| {
            window[0].is_ascii_alphabetic()
                && window[1] == b':'
                && (window[2] == b'\\' || window[2] == b'/')
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    static BAD_CAPABILITIES: &[CapabilityDeclaration] = &[CapabilityDeclaration {
        capability: "delete",
        availability: Availability::Available,
    }];

    static BAD_OPERATION_CAPABILITIES: &[OperationDeclaration] = &[OperationDeclaration {
        id: "bad_operation",
        required_capability: "export",
        required_scope: "finance.bad",
        request_schema_id: "finance.bad.request",
        response_schema_id: "finance.bad.response",
        audit_object_policy: "metadata_only",
        availability: Availability::Reserved,
    }];

    static PLATFORM_STORAGE: &[StorageNamespaceDeclaration] = &[StorageNamespaceDeclaration {
        sqlite_namespace: "local_users",
        sqlite_owner: "finance",
        platform_user_reference: "required",
    }];

    static OTHER_TIGERBEETLE: &[SpecialtyEngineDeclaration] = &[SpecialtyEngineDeclaration {
        engine_id: "tigerbeetle",
        owning_module_id: "garden",
        purpose: "not_allowed",
        exclusive: true,
        lifecycle_owner: "platform",
        provenance_source: "packaged_runtime_manifest",
    }];

    fn finance() -> ModuleRegistration {
        registered_modules()[0].clone()
    }

    fn assert_validation_error(modules: &[ModuleRegistration], expected: RegistryValidationError) {
        assert_eq!(validate_registry(modules), Err(expected));
    }

    #[test]
    fn validates_static_finance_registration() {
        self_test().expect("platform registry self-test");
        let modules = registered_modules();
        assert_eq!(modules.len(), 1);
        let finance = &modules[0];
        assert_eq!(finance.id, "finance");
        assert_eq!(finance.display_name, "Finance");
        assert_eq!(finance.version, "0.1.0-proposed");
        assert_eq!(finance.lifecycle_state, LifecycleState::Available);
        assert_eq!(finance.product_prd_path, "modules/finance/spec/PRD.md");
        assert_eq!(finance.source_root, "modules/finance");
        assert_eq!(finance.adapter.kind, "zig-api");
        assert_eq!(
            finance.adapter.source_root,
            "modules/finance/adapters/zig-api/"
        );
        assert_eq!(finance.storage[0].sqlite_namespace, "finance");
        assert_eq!(finance.storage[0].sqlite_owner, "finance");
        assert_eq!(finance.specialty_engines[0].engine_id, "tigerbeetle");
        assert_eq!(
            finance.specialty_engines[0].purpose,
            "ledger_balances_and_transfers"
        );
        assert!(finance.specialty_engines[0].exclusive);
        assert_eq!(
            finance
                .operations
                .iter()
                .find(|operation| operation.id == "runtime_status")
                .expect("runtime_status operation")
                .availability,
            Availability::Available
        );
    }

    #[test]
    fn reserves_all_gateway_caller_surfaces() {
        let surfaces: Vec<&str> = reserved_caller_surfaces()
            .iter()
            .map(|surface| surface.as_str())
            .collect();
        assert_eq!(surfaces, ["ui", "cli", "mcp", "internal"]);
    }

    #[test]
    fn rejects_duplicate_module_ids() {
        let left = finance();
        let right = finance();
        assert_validation_error(
            &[left, right],
            RegistryValidationError::DuplicateModuleId("finance".to_string()),
        );
    }

    #[test]
    fn rejects_unknown_capabilities() {
        let mut module = finance();
        module.capabilities = BAD_CAPABILITIES;
        assert_validation_error(
            &[module],
            RegistryValidationError::UnknownCapability("delete".to_string()),
        );
    }

    #[test]
    fn rejects_operations_that_reference_undeclared_capabilities() {
        let mut module = finance();
        module.capabilities = &[CapabilityDeclaration {
            capability: "read",
            availability: Availability::Available,
        }];
        module.operations = BAD_OPERATION_CAPABILITIES;
        assert_validation_error(
            &[module],
            RegistryValidationError::UndeclaredOperationCapability {
                operation: "bad_operation".to_string(),
                capability: "export".to_string(),
            },
        );
    }

    #[test]
    fn rejects_platform_namespace_claims() {
        let mut module = finance();
        module.storage = PLATFORM_STORAGE;
        assert_validation_error(
            &[module],
            RegistryValidationError::PlatformNamespaceClaimed {
                module_id: "finance".to_string(),
                namespace: "local_users".to_string(),
            },
        );
    }

    #[test]
    fn rejects_duplicate_sqlite_namespace_owners() {
        let mut other = finance();
        other.id = "garden";
        assert_validation_error(
            &[finance(), other],
            RegistryValidationError::DuplicateSqliteNamespaceOwner("finance".to_string()),
        );
    }

    #[test]
    fn rejects_non_finance_tigerbeetle_ownership() {
        let mut module = finance();
        module.id = "garden";
        module.storage = &[StorageNamespaceDeclaration {
            sqlite_namespace: "garden",
            sqlite_owner: "garden",
            platform_user_reference: "required",
        }];
        module.specialty_engines = OTHER_TIGERBEETLE;
        assert_validation_error(
            &[module],
            RegistryValidationError::NonFinanceTigerBeetleOwner("garden".to_string()),
        );
    }

    #[test]
    fn rejects_adapter_source_roots_outside_module_path() {
        let mut module = finance();
        module.adapter.source_root = "services/api/";
        assert_validation_error(
            &[module],
            RegistryValidationError::AdapterSourceOutsideModule {
                module_id: "finance".to_string(),
                source_root: "services/api/".to_string(),
            },
        );
    }

    #[test]
    fn rejects_adapter_source_roots_with_sibling_prefixes() {
        let mut module = finance();
        module.adapter.source_root = "modules/finance-evil/adapters/zig-api/";
        assert_validation_error(
            &[module],
            RegistryValidationError::AdapterSourceOutsideModule {
                module_id: "finance".to_string(),
                source_root: "modules/finance-evil/adapters/zig-api/".to_string(),
            },
        );
    }

    #[test]
    fn rejects_empty_operation_schema_ids() {
        let mut module = finance();
        let mut operations = FINANCE_OPERATIONS.to_vec();
        operations[0].request_schema_id = "";
        module.operations = Box::leak(operations.into_boxed_slice());
        assert_validation_error(
            &[module],
            RegistryValidationError::InvalidOperationSchema {
                operation: "runtime_status".to_string(),
                schema_id: String::new(),
            },
        );
    }

    #[test]
    fn rejects_operation_schema_ids_without_explicit_state() {
        let mut module = finance();
        let mut operations = FINANCE_OPERATIONS.to_vec();
        operations[0].response_schema_id = "finance.runtime_status.response";
        module.operations = Box::leak(operations.into_boxed_slice());
        assert_validation_error(
            &[module],
            RegistryValidationError::InvalidOperationSchema {
                operation: "runtime_status".to_string(),
                schema_id: "finance.runtime_status.response".to_string(),
            },
        );
    }

    #[test]
    fn rejects_sensitive_registry_values() {
        for value in [
            "appToken",
            "supervisor authority",
            "password=secret",
            "postgres://local/db",
            "http://127.0.0.1:7800/private",
            "C:\\Users\\jcane\\secret",
            "/home/jcane/secret",
        ] {
            assert!(registry_value_is_sensitive(value), "{value}");
        }
        assert!(!registry_value_is_sensitive(
            "modules/finance/adapters/zig-api/"
        ));
        assert!(!registry_value_is_sensitive(
            "private_adapter_routes_are_implementation_details"
        ));
    }

    #[test]
    fn static_registry_has_no_sensitive_values() {
        validate_registry(registered_modules()).expect("safe registry values");
    }
}
