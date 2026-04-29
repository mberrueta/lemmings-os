# ADR-0020 — Hierarchical Configuration Model

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: LemmingsOS maintainers

---

# 1. Context

LemmingsOS organizes configuration and governance around a strict hierarchy:

```text
World -> City -> Department -> Lemming
```

This is the product-level configuration contract. Runtime execution may later add a more specific overlay for concrete agent instances, but that does not change the base hierarchical model defined here.

Every subsystem that enforces runtime behavior - tool authorization, cost governance, model routing, risk classification, and approval workflows - requires configuration that is scope-aware, deterministically resolved, and safe to override at lower levels.

Without a canonical configuration model, each subsystem risks implementing its own resolution strategy with conflicting semantics. Most critically, an unspecified merge strategy creates a security gap: a naive "child overrides parent" rule applied uniformly would allow a lower-scope administrator to re-enable a tool that a World-level administrator has explicitly denied, or to increase a budget cap above a World-level ceiling. This ADR defines the intended model that prevents that failure mode.

---

# 2. Decision Drivers

1. **Deterministic resolution** - every runtime component reading a configuration key must obtain the same effective value regardless of which node or process performs the resolution.
2. **Deny dominance for governance keys** - tool denials and budget ceilings set at a higher scope must not be overridable by a lower scope.
3. **Override semantics for operational keys** - most configuration keys represent operational preferences, not governance constraints.
4. **Distributed consistency without coordination** - a City node must be able to resolve effective configuration locally without real-time RPC to sibling nodes.
5. **Auditability** - changes to configuration must produce audit events so the history of effective configuration at any scope can be reconstructed.
6. **Safe update propagation** - configuration changes at higher scopes should propagate to runtime components without forcing restarts.

---

# 3. Considered Options

## Option A - Flat global configuration with runtime overrides

All configuration lives in a single global table. Individual components read the global config and apply their own local overrides through application-level code.

**Rejected.** This model does not reflect the system hierarchy and cannot enforce hierarchy-aligned governance constraints.

## Option B - Fully versioned configuration tables with event sourcing

Configuration is stored append-only as a sequence of change events per scope. Effective configuration is derived by replaying the event sequence.

**Rejected for v1.** The audit requirement is satisfied by emitting change events to the audit log rather than making the storage model itself an event log.

## Option C - File-based configuration with environment variable overrides

Configuration is managed through files with environment variables providing runtime overrides.

**Rejected.** File-based configuration cannot support hierarchy-scoped governance without reintroducing coordination problems.

## Option D - Hierarchical JSONB configuration with dual merge semantics (chosen)

Each hierarchy scope stores only the configuration it explicitly defines. Effective configuration is resolved by a centralized resolver using two distinct merge semantics applied in a single deterministic pipeline.

**Chosen.** This maps directly to the runtime hierarchy and keeps governance semantics explicit.

---

# 4. Decision

LemmingsOS uses a **hierarchical configuration model with dual merge semantics**.

Bootstrap YAML is ingestion input, not the persisted source of truth. Durable configuration is stored in scoped JSONB columns rather than a single catch-all blob.

The hierarchy follows two distinct merge modes:

1. **Override-dominant merge** - for operational configuration keys, child values replace parent values.
2. **Deny-dominant constraints** - for governance namespaces, a child scope may only tighten a restriction, never loosen one established by an ancestor.

The two governance namespaces subject to deny-dominant constraints are:

- **`tools.deny`** - tool deny lists; union of all ancestor denials is the floor
- **`cost.budget`** - budget caps; minimum across all ancestor caps is the ceiling

All other namespaces use override-dominant semantics.

Tool-related configuration belongs to this same architectural contract. If an implementation stages a dedicated leaf-scope tool bucket, that bucket is only a storage vehicle for the hierarchy above; it does not redefine the governance model.

---

# 5. Configuration Storage

Each hierarchy entity stores partial configuration. Unset keys are resolved from the parent.

At the World, City, Department, and Lemming scopes, configuration is stored as split JSONB columns instead of a single catch-all `config_jsonb` field:

```text
worlds / cities / departments / lemmings
  -> limits_config
  -> runtime_config
  -> costs_config
  -> models_config
```

The leaf Lemming scope may also carry tool-related configuration. Whether that surface is stored in a dedicated `tools_config` bucket, in policy records, or through another representation is an implementation concern. The architectural contract remains the same: tool-related configuration is resolved through the hierarchy and obeys the same deny-dominant rules.

Configuration is partial by design. The World document typically contains the authoritative defaults. City documents contain only the keys they override. Department and Lemming documents follow the same pattern.

---

# 6. Merge Semantics

## 6.1 Override-dominant merge (default)

For all configuration namespaces not subject to deny-dominant constraints, child values replace parent values recursively.

## 6.2 Deny-dominant merge (governance namespaces)

For governance namespaces, the merge rule is inverted: the most restrictive value across all ancestor scopes always wins. A child can only add restrictions; it cannot remove them.

**`tools.deny` - union semantics**

The effective tool deny list is the union of all deny lists across all ancestor scopes. No descendant can remove a tool from an ancestor's deny list.

**`cost.budget.cap_usd` - minimum semantics**

The effective budget cap is the minimum cap across all ancestor scopes. A child scope may set a tighter cap (a sub-budget) but cannot exceed the parent ceiling.

Tool governance is therefore not a separate exception to hierarchy; it is one of the primary reasons the hierarchy exists.

---

# 7. Configuration Resolver

All runtime components access configuration exclusively through the resolver. Direct database access is forbidden.

```
LemmingsOs.Config.Resolver
```

The resolver accepts preloaded Ecto structs, not IDs:

```elixir
Config.Resolver.resolve(%World{})
Config.Resolver.resolve(%City{world: %World{}})
Config.Resolver.resolve(%Department{city: %City{world: %World{}}})
Config.Resolver.resolve(%Lemming{department: %Department{city: %City{world: %World{}}}})
```

Each call returns an immutable effective configuration map with typed struct values.

Merge semantics for the resolver:

- child overrides parent for operational keys
- nil values in the child are pruned before merge, so they do not clobber parent defaults
- the resolver returns typed embedded schema structs, not raw maps
- source tracing / explanation metadata is intentionally separate from effective resolution

The resolver remains the only location in the codebase where merge semantics are implemented. Subsystems must not re-implement merge logic.

---

# 8. Scope Matrix

Not all keys are settable at all hierarchy levels.

| Namespace | World | City | Department | Lemming | Notes |
|---|---|---|---|---|---|
| `models.*` | ✅ | ⚠️ | ⚠️ | ✅ | Model routing may specialize lower down |
| `tools.max_parallel` | ✅ | ✅ | ✅ | ✅ | Override-dominant |
| `tools.deny` | ✅ | ✅ | ✅ | ✅ | **Deny-dominant; union of all ancestors** |
| `tools.risk.*` | ✅ | ❌ | ❌ | ❌ | Risk classification is global |
| `cost.budget.cap_usd` | ✅ | ✅ | ✅ | ✅ | **Deny-dominant; minimum of all ancestors** |
| `cost.budget.window` | ✅ | ❌ | ❌ | ❌ | Budget window is World-level only |
| `runtime.*` | ✅ | ✅ | ✅ | ✅ | Execution limits may vary |
| `security.*` | ✅ | ⚠️ | ❌ | ❌ | Security policies are mostly global |
| `observability.*` | ✅ | ✅ | ❌ | ❌ | Logging and metric scope |

Legend:

```text
✅ allowed
⚠️ discouraged / exceptional override
❌ not allowed; resolver rejects if present
```

---

# 9. Configuration Versioning

The database stores only the current configuration state at each scope.

History is tracked through the audit event system. Every successful configuration change emits:

```text
event_type: config.updated
metadata:
  scope_type: world | city | department | lemming
  scope_id: <uuid>
  actor: <user or system identity>
  previous_hash: <sha256 of previous persisted config bucket payload>
  new_hash: <sha256 of new persisted config bucket payload>
  changed_keys: [...]
```

---

# 10. Failure Model

| Condition | Behavior |
|---|---|
| Invalid configuration submitted | Rejected by validation before persistence; no change written |
| Child attempts to remove ancestor tool denial | Rejected by validator; `config.updated` is not emitted |
| Child attempts to exceed parent budget cap | Validator rejects; if bypassed, resolver enforces minimum semantics |
| DB unreachable during resolver call | Returns `{:error, :config_unavailable}`; callers must handle gracefully |

---

# 11. Implementation Notes

Key modules:

```text
LemmingsOs.Config.Resolver   - effective config resolution and dual merge
LemmingsOs.Config.Cache      - ETS-backed per-node cache
LemmingsOs.Config.Validator  - schema and governance constraint validation
```

Configuration namespace ownership by ADR:

- `tools.*` - ADR-0012 (Tool Policy and Authorization)
- `tools.risk.*` - ADR-0013 (Tool Risk Classification)
- `cost.*` - ADR-0015 (Runtime Cost Governance)
- `models.*` - ADR-0019 (LLM Model Provider Execution)
- `runtime.*` - ADR-0004 (Lemming Execution Model)

Subsystems must:

- define the configuration keys they own and their valid scopes
- validate their namespace keys through `Config.Validator`
- read configuration exclusively through `Config.Resolver`
- never apply their own inheritance logic

Implementation sequencing may introduce tool-related storage in stages, but that sequencing does not change the contract above.

## 11.1 Secret Bank MVP Configuration Note

Secret Bank env fallback configuration is currently stored in application
configuration, not in hierarchy JSONB buckets and not in the configuration
resolver.

Current shape:

```elixir
config :lemmings_os, LemmingsOs.SecretBank,
  allowed_env_vars: ["$GITHUB_TOKEN", "$OPENROUTER_API_KEY"],
  env_fallbacks: [
    "$GITHUB_TOKEN",
    {"OPENROUTER_API_KEY", "$OPENROUTER_API_KEY"}
  ]
```

The fallback list is a closed policy: a configured bank key can read an env var
only when that env var is also present in `allowed_env_vars`. The earlier
logical-key example
`env_fallbacks: ["github.token", {"openrouter.default", "OPENROUTER_API_KEY"}]`
is future architecture, not accepted by the current uppercase key validator.

Secret values themselves are not configuration documents. Persisted local values
live in `secret_bank_secrets.value_encrypted`; safe effective metadata is
resolved by `LemmingsOs.SecretBank`.

---

# 12. Consequences

## Positive

- Deny-dominant merge semantics make the governance guarantees structurally enforceable.
- Effective configuration is always deterministic regardless of which node or process evaluates it.
- Partial JSONB documents avoid full config duplication across scopes.
- A single canonical resolver codepath means governance semantics are auditable and testable in isolation.

## Negative

- Dual merge semantics add implementation surface.
- Cache invalidation is eventual.
- JSONB partial documents require discipline from operators and tooling.

## Mitigations

- The governance namespace list is small and explicitly enumerated.
- For operators who require immediate enforcement of a governance change, restarting affected City nodes flushes the cache and forces an immediate reload.
- `Config.Validator` is a mandatory gateway before persistence; it rejects both invalid configuration and attempts to set keys at disallowed scope levels.

---

# 13. Future Extensions

- Configuration rollback
- Dry-run evaluation
- Per-operator namespace isolation
- Signed configuration documents

---

# 14. Rationale

The core design tension in hierarchical configuration is between operational flexibility and governance correctness. A uniform "child overrides parent" rule maximizes flexibility but creates a governance gap. A uniform "parent always wins" rule preserves governance but makes the configuration system too rigid.

Dual merge semantics resolve this tension by being explicit about which keys belong to each category. Governance keys - tool denials and budget ceilings - use deny-dominant semantics because their entire purpose is to establish hard constraints that cannot be circumvented. All other operational keys use override-dominant semantics because customization at lower scopes is a legitimate and expected behavior.

This is an architectural contract, not a branch-specific persistence note. Implementation may stage the storage surfaces incrementally, but the resolution model, scope semantics, and governance rules remain the product definition.
