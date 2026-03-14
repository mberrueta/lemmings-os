# ADR-0020 — Hierarchical Configuration Model

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: LemmingsOS maintainers

---

# 1. Context

LemmingsOS organizes execution and governance around a strict hierarchy:

```
World → City → Department → Lemming
```

Every subsystem that enforces runtime behavior — tool authorization (ADR-0012),
cost governance (ADR-0015), model routing (ADR-0019), risk classification
(ADR-0013) — requires configuration that is scope-aware, deterministically
resolved, and safe to override at lower levels.

Prior ADRs assumed configuration inheritance but did not define:

- where configuration is stored
- how inheritance is resolved at each hierarchy level
- whether child scopes may override governance-critical keys such as tool denials or budget caps
- how changes propagate across a distributed cluster
- how the runtime observes configuration updates without restarting

Without a canonical configuration model, each subsystem risks implementing its
own resolution strategy with conflicting semantics. Most critically, an
unspecified merge strategy creates a security gap: a naïve "child overrides
parent" rule applied uniformly would allow a Department-level administrator to
re-enable a tool that a World-level administrator has explicitly denied, or to
increase a budget cap above a World-level ceiling. ADR-0012 and ADR-0015 both
assume this cannot happen. This ADR defines the model that enforces that
assumption.

---

# 2. Decision Drivers

1. **Deterministic resolution** — Every runtime component reading a configuration
   key must obtain the same effective value regardless of which node or process
   performs the resolution. Non-deterministic configuration is a correctness hazard.

2. **Deny dominance for governance keys** — Tool denials and budget ceilings set at
   a higher scope must not be overridable by a lower scope. A World-level tool deny
   is a hard constraint; it cannot be re-enabled at City, Department, or Lemming
   level. A budget cap set at World level defines an absolute ceiling; a child scope
   may set a tighter cap but never a looser one.

3. **Override semantics for operational keys** — Most configuration keys represent
   operational preferences, not governance constraints. For these, lower scopes
   should be able to customize behavior without restriction (e.g., a Department
   configuring a different default model, or a Lemming reducing its parallel tool
   limit).

4. **Distributed consistency without coordination** — A City node must be able to
   resolve effective configuration locally without real-time RPC to sibling nodes.
   The resolution model must tolerate eventual consistency in cache state while
   remaining deterministic.

5. **Auditability** — Changes to configuration must produce audit events so that
   the history of effective configuration at any scope can be reconstructed after
   the fact. The database stores current state; the audit log stores history.

6. **Safe update propagation** — A configuration change at World level should
   propagate to runtime components without forcing restarts. Long-running Lemmings
   must not silently continue with stale governance configuration indefinitely.

---

# 3. Considered Options

## Option A — Flat global configuration with runtime overrides

All configuration lives in a single global table. Individual components read the
global config and apply their own local overrides through application-level code.

**Pros:**
- trivial to implement in v1
- no hierarchy-aware resolution logic required

**Cons:**
- does not reflect the system hierarchy; organizational scope boundaries are not
  modeled
- local overrides applied in application code cannot be audited or validated
  centrally
- deny-dominant semantics cannot be enforced consistently; every component would
  need to implement its own deny propagation logic
- configuration drift between components becomes likely

Rejected. Flat global configuration cannot enforce hierarchy-aligned governance
constraints and conflicts with the foundational isolation model of ADR-0003.

---

## Option B — Fully versioned configuration tables with event sourcing

Configuration is stored append-only as a sequence of change events per scope.
Effective configuration is derived by replaying the event sequence.

**Pros:**
- complete auditability; full history is the source of truth, not derived
- rollback to any prior configuration state is deterministic
- no separate audit event emission required; the storage model is the audit trail

**Cons:**
- query complexity for effective configuration resolution is high; every read
  requires a projection over potentially large event sequences
- cache invalidation and consistency reasoning become significantly harder
- schema migration against an event-sourced config store is operationally complex
- disproportionate to the v1 deployment target; self-hosted operators gain little
  from full event sourcing for configuration

Rejected for v1. The audit requirement is satisfied by emitting change events to
the existing audit log (ADR-0018) rather than making the storage model itself an
event log. Full event sourcing for configuration is a future extension.

---

## Option C — File-based configuration with environment variable overrides

Configuration is managed through files (YAML, TOML, or similar) bundled with the
application, with environment variables providing runtime overrides.

**Pros:**
- familiar operational model for many self-hosted operators
- no database dependency for configuration access at startup

**Cons:**
- hierarchy-scoped configuration (World, City, Department) cannot be represented
  in static files without per-scope file sets, which creates operational complexity
- changes to World or Department configuration require file changes and container
  redeployment, eliminating the ability to update configuration at runtime
- deny-dominant governance semantics cannot be enforced when configuration lives
  in files managed by different operators at different scopes
- distributed runtime nodes would require synchronized file state across containers

Rejected. File-based configuration cannot support runtime-mutable hierarchy-
scoped governance without reintroducing the coordination problems it attempts
to avoid.

---

## Option D — Hierarchical JSONB configuration with dual merge semantics (chosen)

Each hierarchy entity (`worlds`, `cities`, `departments`, `lemming_instances`)
stores a partial JSONB configuration document containing only the keys it defines.
Effective configuration is resolved by a centralized resolver using two distinct
merge semantics applied in a single deterministic pipeline.

**Pros:**
- maps directly to the runtime hierarchy; every configuration value has an explicit
  scope owner
- dual merge semantics (override-dominant and deny-dominant) enforce both
  operational flexibility and governance correctness in a single resolution pass
- partial documents avoid full-copy-on-write; each scope only stores what it
  explicitly configures
- resolver is a single canonical codepath; all subsystems share the same semantics
- ETS-backed caching makes per-Lemming config resolution effectively O(1) at scale

**Cons:**
- dual merge semantics add implementation surface that must be maintained and
  tested carefully
- JSONB partial documents require discipline to prevent unbounded key accumulation
- cache invalidation across a distributed cluster is eventual; there is a brief
  window after a World-level deny change where in-flight operations may proceed
  under the previous effective config

Chosen. See section 4 and rationale for full justification.

---

# 4. Decision

LemmingsOS uses a **hierarchical configuration model with dual merge semantics**.

Configuration is stored as partial JSONB documents at each hierarchy scope.
Effective configuration is resolved through a single deterministic pipeline that
applies two merge strategies in sequence:

1. **Override-dominant merge** — for operational configuration keys, child values
   replace parent values.

2. **Deny-dominant constraints** — applied as a post-merge pass over governance
   namespaces. These constraints are ceiling-only: a child scope may only tighten a
   restriction, never loosen one established by an ancestor.

The two governance namespaces subject to deny-dominant constraints are:

- **`tools.deny`** — tool deny lists; union of all ancestor denials is the floor
- **`cost.budget`** — budget caps; minimum across all ancestor caps is the ceiling

All other namespaces use override-dominant semantics.

---

# 5. Configuration Storage

Each hierarchy entity stores a partial configuration document in its `config_jsonb`
column. A document contains only the keys that scope explicitly configures;
unset keys are resolved from the parent.

Storage schema (abbreviated):

```
worlds        → config_jsonb
cities        → config_jsonb
departments   → config_jsonb
lemming_types → config_jsonb
```

Configuration is partial by design. The World document typically contains the
authoritative defaults. City, Department, and Lemming Type documents contain only
the keys they override or extend.

Example World configuration:

```json
{
  "models": { "default": "qwen3" },
  "tools": {
    "max_parallel": 4,
    "deny": ["shell_exec", "file_write"]
  },
  "cost": {
    "budget": { "cap_usd": 50.00, "window": "monthly" }
  }
}
```

Example Department override:

```json
{
  "tools": {
    "max_parallel": 2,
    "deny": ["web_search"]
  },
  "cost": {
    "budget": { "cap_usd": 10.00 }
  }
}
```

---

# 6. Merge Semantics

## 6.1 Override-dominant merge (default)

For all configuration namespaces not subject to deny-dominant constraints, child
values replace parent values recursively. This is a standard `deep_merge`.

```
models.default: "qwen3" (world) → unchanged if Department does not set it
tools.max_parallel: 4 (world) → 2 (department wins)
```

## 6.2 Deny-dominant merge (governance namespaces)

For governance namespaces, the merge rule is inverted: the most restrictive value
across all ancestor scopes always wins. A child can only add restrictions; it
cannot remove them.

**`tools.deny` — union semantics**

The effective tool deny list is the union of all deny lists across all ancestor
scopes. No descendant can remove a tool from an ancestor's deny list.

```
world:      deny = [shell_exec, file_write]
department: deny = [web_search]
effective:  deny = [shell_exec, file_write, web_search]
```

If World denies `shell_exec`, no Department, City, or Lemming type can re-enable
`shell_exec`. The ADR-0012 deny-dominance guarantee is structurally enforced by
the resolution algorithm, not by downstream policy checks.

**`cost.budget.cap_usd` — minimum semantics**

The effective budget cap is the minimum cap across all ancestor scopes. A child
scope may set a tighter cap (a sub-budget) but cannot exceed the parent ceiling.

```
world:      cap_usd = 50.00
department: cap_usd = 10.00
effective:  cap_usd = 10.00 (tighter wins)

world:      cap_usd = 50.00
department: cap_usd = 100.00  ← attempts to exceed parent
effective:  cap_usd = 50.00   ← parent ceiling enforced
```

---

# 7. Configuration Resolver

All runtime components access configuration exclusively through the resolver. Direct
database access is forbidden.

```
LemmingsOs.Config.Resolver
```

Interface:

```elixir
Config.Resolver.effective(world_id)
Config.Resolver.effective(world_id, city_id)
Config.Resolver.effective(world_id, city_id, department_id)
Config.Resolver.effective(world_id, city_id, department_id, lemming_type_id)
```

Each call returns an immutable effective configuration map for the given scope.

Resolution algorithm:

```elixir
def effective(world_id, city_id \\ nil, dept_id \\ nil, lemming_type_id \\ nil) do
  layers =
    [
      load_config(:world, world_id),
      load_config(:city, city_id),
      load_config(:department, dept_id),
      load_config(:lemming_type, lemming_type_id)
    ]
    |> Enum.reject(&is_nil/1)

  layers
  |> Enum.reduce(%{}, &deep_merge(&2, &1))   # step 1: override-dominant
  |> enforce_deny_dominant(layers)            # step 2: governance constraints
end

# Union of all ancestor tool deny lists — no ancestor denial can be removed
defp enforce_deny_dominant(config, layers) do
  all_tool_denials =
    layers
    |> Enum.flat_map(&(get_in(&1, [:tools, :deny]) || []))
    |> MapSet.new()

  min_budget_cap =
    layers
    |> Enum.map(&get_in(&1, [:cost, :budget, :cap_usd]))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      caps -> Enum.min(caps)
    end

  config
  |> put_in_if_present([:tools, :deny], MapSet.to_list(all_tool_denials))
  |> put_in_if_present([:cost, :budget, :cap_usd], min_budget_cap)
end
```

The resolver is the only location in the codebase where merge semantics are
implemented. Subsystems must not re-implement merge logic.

---

# 8. Runtime Caching

Resolved configuration is cached per node in ETS.

```
LemmingsOs.Config.Cache
```

Cache key: `{world_id, city_id, department_id, lemming_type_id}`

Properties:

- ETS-backed, read-optimized
- lazily populated on first resolver call for a given scope tuple
- invalidated on configuration change events
- rebuilt lazily on cache miss or node restart

Cluster-wide cache invalidation:

When a configuration change is persisted, the control plane emits a
`config.updated` audit event (ADR-0018). All City nodes observe this event and
drop the affected cache entries. The next resolver call for that scope reloads
from PostgreSQL and repopulates the cache.

---

# 9. Configuration Propagation

```
Admin UI or API call
        │
        ▼
  Config.Validator validates structure and deny-dominant constraints
        │
        ▼
  PostgreSQL update (config_jsonb on the hierarchy entity)
        │
        ▼
  config.updated audit event emitted (ADR-0018)
        │
        ▼
  All City nodes receive event and invalidate affected cache entries
        │
        ▼
  Next resolver call for that scope reloads from DB
```

Propagation model: **eventual consistency with deterministic resolution**.

There is a brief window between a change being persisted and all City nodes
invalidating their caches. For most operational keys this is acceptable. For
governance-critical changes (e.g., a World-level tool denial), operators who
require immediate enforcement may restart affected City nodes, which forces a
full cache rebuild.

Long-running Lemmings apply new configuration on their next execution cycle
boundary, not mid-task.

---

# 10. Configuration Scope Matrix

Not all keys are settable at all hierarchy levels. This table defines which
namespaces are valid at each scope.

| Namespace | World | City | Department | Lemming Type | Notes |
|---|---|---|---|---|---|
| `models.*` | ✅ | ⚠️ | ⚠️ | ❌ | Model routing is typically global |
| `tools.max_parallel` | ✅ | ✅ | ✅ | ❌ | Concurrency limit, override-dominant |
| `tools.deny` | ✅ | ✅ | ✅ | ❌ | **Deny-dominant; union of all ancestors** |
| `tools.risk.*` | ✅ | ❌ | ❌ | ❌ | Risk classification is global (ADR-0013) |
| `cost.budget.cap_usd` | ✅ | ✅ | ✅ | ❌ | **Deny-dominant; minimum of all ancestors** |
| `cost.budget.window` | ✅ | ❌ | ❌ | ❌ | Budget window is World-level only |
| `runtime.*` | ✅ | ✅ | ✅ | ✅ | Execution limits may vary |
| `security.*` | ✅ | ⚠️ | ❌ | ❌ | Security policies are mostly global |
| `observability.*` | ✅ | ✅ | ❌ | ❌ | Logging and metric scope |

Legend:

```
✅ allowed
⚠️ discouraged / exceptional override
❌ not allowed; resolver rejects if present
```

---

# 11. Configuration Versioning

The database stores only the current configuration state at each scope.

History is tracked through the audit event system (ADR-0018). Every successful
configuration change emits:

```
event_type: config.updated
metadata:
  scope_type: world | city | department | lemming_type
  scope_id: <uuid>
  actor: <user or system identity>
  previous_hash: <sha256 of previous config_jsonb>
  new_hash: <sha256 of new config_jsonb>
  changed_keys: [...]
```

This gives operators a complete audit trail for governance changes without
requiring event-sourced configuration storage.

---

# 12. Failure Model

| Condition | Behavior |
|---|---|
| Invalid configuration submitted | Rejected by `Config.Validator` before persistence; no change written |
| Child attempts to remove ancestor tool denial | Rejected by validator; `config.updated` is not emitted |
| Child attempts to exceed parent budget cap | Validator rejects; if bypassed, resolver enforces minimum semantics |
| Cache miss | Resolver reloads from PostgreSQL and repopulates cache |
| Node restart | Cache rebuilt lazily on first resolver call per scope |
| DB unreachable during resolver call | Returns `{:error, :config_unavailable}`; callers must handle gracefully |

---

# 13. Implementation Notes

Key modules:

```
LemmingsOs.Config.Resolver   — effective config resolution and dual merge
LemmingsOs.Config.Cache      — ETS-backed per-node cache
LemmingsOs.Config.Validator  — schema and governance constraint validation
```

Configuration namespace ownership by ADR:

- `tools.*` — ADR-0012 (Tool Policy and Authorization)
- `tools.risk.*` — ADR-0013 (Tool Risk Classification)
- `cost.*` — ADR-0015 (Runtime Cost Governance)
- `models.*` — ADR-0019 (LLM Model Provider Execution)
- `runtime.*` — ADR-0004 (Lemming Execution Model)

Subsystems must:

- define the configuration keys they own and their valid scopes
- validate their namespace keys through `Config.Validator`
- read configuration exclusively through `Config.Resolver`
- never apply their own inheritance logic

---

# 14. Considered Options

See section 3 above. Options A (flat global), B (fully versioned tables), and C
(file-based) were evaluated and rejected before arriving at Option D (hierarchical
JSONB with dual merge semantics).

---

# 15. Consequences

## Positive

- Deny-dominant merge semantics make the ADR-0012 and ADR-0015 governance
  guarantees structurally enforceable at the configuration layer, rather than
  relying on each subsystem to implement its own deny-propagation logic.
- Effective configuration is always deterministic regardless of which node or
  process evaluates it.
- Partial JSONB documents avoid full config duplication across scopes; each scope
  stores only what it explicitly overrides.
- A single canonical resolver codepath means governance semantics are auditable
  and testable in isolation, independent of the subsystems that consume them.
- ETS caching makes per-Lemming config resolution effectively constant-time at scale.

## Negative

- Dual merge semantics add implementation surface. The distinction between
  override-dominant and deny-dominant namespaces must be documented and enforced
  consistently; an incorrect classification of a governance key as override-dominant
  would be a silent security gap.
- Cache invalidation is eventual. For governance-critical changes (World-level tool
  denials), there is a propagation window during which cached effective configs may
  not yet reflect the new denial.
- JSONB partial documents require discipline from operators and tooling; keys that
  do not belong at a given scope must be caught by the validator.

## Mitigations

- The governance namespace list (`tools.deny`, `cost.budget.*`) is small and
  explicitly enumerated in the resolver. Adding a new deny-dominant namespace
  requires a deliberate code change, not a configuration value.
- For operators who require immediate enforcement of a governance change, restarting
  affected City nodes flushes the cache and forces an immediate reload.
- `Config.Validator` is a mandatory gateway before persistence; it rejects both
  invalid configuration and attempts to set keys at disallowed scope levels.

---

# 16. Non-Goals

This ADR intentionally does not define:

- the schema or semantics of individual configuration keys within each namespace
  (owned by the respective subsystem ADRs)
- configuration import/export tooling
- environment-variable-based configuration override for local development
  (handled by `runtime.exs` at the Mix release level)
- multi-tenancy where different World operators have independent configuration
  namespaces (future extension)
- full event-sourced configuration history with rollback (future extension)

---

# 17. Future Extensions

- **Configuration rollback**: store full JSONB snapshots alongside audit events to
  allow one-click rollback to a prior configuration state via the control plane.
- **Dry-run evaluation**: a resolver mode that previews the effective configuration
  for a proposed change before it is committed to the database.
- **Per-operator namespace isolation**: for multi-tenant deployments where different
  World operators should not observe each other's configuration keys.
- **Signed configuration documents**: cryptographic signatures over config_jsonb
  to detect tampering in high-security deployments.

---

# 18. Rationale

The core design tension in hierarchical configuration is between operational
flexibility and governance correctness. A uniform "child overrides parent" rule
maximizes flexibility but creates a governance gap: any lower-scope administrator
can nullify a higher-scope security decision. A uniform "parent always wins" rule
preserves governance but makes the configuration system too rigid for legitimate
operational customization.

Dual merge semantics resolve this tension by being explicit about which keys
belong to each category. Governance keys — tool denials and budget ceilings — use
deny-dominant semantics because their entire purpose is to establish hard
constraints that cannot be circumvented. All other operational keys use
override-dominant semantics because customization at lower scopes is a legitimate
and expected behavior.

This approach also makes the security guarantees of ADR-0012 and ADR-0015
structurally enforced rather than conventionally enforced. A World administrator
who denies `shell_exec` does not need to trust that every Department administrator
will respect that denial in their own configuration. The resolver guarantees it
algorithmically.

The choice of PostgreSQL JSONB with partial documents, rather than fully-versioned
tables or event sourcing, reflects the v1 operational target: self-hosted operators
running on a single VPS do not benefit from the complexity of append-only config
tables. The audit trail requirement is satisfied by emitting `config.updated`
events to the existing audit log infrastructure rather than reimplementing event
sourcing specifically for configuration.
