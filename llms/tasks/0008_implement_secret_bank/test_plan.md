# Secret Bank Test Scenarios and Safety Matrix

## Scope & Assumptions

- Scope covers Secret Bank MVP behavior from Tasks 01-07: encrypted local secrets, env fallback allowlist, hierarchical effective metadata, trusted runtime resolution, tool integration, durable audit events, and operator LiveView surfaces.
- Hierarchy under test is `env allowlist -> world -> city -> department -> lemming`; runtime lookup is `lemming -> department -> city -> world -> env allowlist`.
- Bank keys in the current implementation are uppercase env-style identifiers such as `GITHUB_TOKEN`; tests should use fake values only, e.g. `dev_only_fake_github_token`.
- Product acceptance requires `$secrets.*` reference coverage. If the final implementation intentionally keeps the current `$KEY` reference form instead, Task 09 must encode that decision explicitly and include a failing/regression test or task note for the product-contract mismatch.
- Env fallback mappings are application config, not database rows, and should be tested with controlled application env plus restored state after each test.
- UI tests should assert stable selectors and safe rendered metadata, not broad raw HTML snapshots.
- This plan defines what Task 09 should implement; it does not add automated test code.

## Risk Areas

- Secret values leaking through metadata APIs, LiveView HTML, assigns rendered to clients, audit payloads, telemetry/log metadata, PubSub events, prompts, snapshots, finalization payloads, or exception messages.
- Runtime resolving untrusted `$secrets.*` references from model-provided/user-provided tool args instead of only trusted tool/adapter configuration.
- Hierarchy resolution choosing the wrong source after create, replace, delete, or override fallback.
- Env fallback accidentally scanning arbitrary process environment variables instead of honoring the allowlist.
- Database uniqueness/check constraints allowing duplicate or invalid scope shapes.
- Durable audit events omitting required Secret Bank actions or storing value-bearing payloads.
- UI exposing reveal/copy/export semantics or allowing child scopes to delete inherited secrets.
- Decryption/provider failures raising unsafe exceptions instead of returning safe error atoms.

## Product Acceptance Criteria Mapping

| Product area | Required test layers | Primary scenarios |
|---|---|---|
| Secret configuration at every scope | Context, DB, LiveView | SB-001 through SB-008, SB-031 through SB-038 |
| Write-only values | DB, Context, LiveView, Runtime safety | SB-009, SB-010, SB-039 through SB-052 |
| Effective source display | Context, LiveView | SB-011 through SB-018, SB-033 through SB-038 |
| Override behavior | Context, Runtime | SB-011 through SB-018, SB-025 |
| Delete behavior | Context, LiveView | SB-019 through SB-024, SB-037, SB-038 |
| Runtime resolution | Unit, Integration, Tool runtime | SB-025 through SB-030, SB-045 through SB-049 |
| Observability and audit | Integration, Log/telemetry capture | SB-053 through SB-060 |
| Env fallback allowlist | Unit, Context, LiveView | SB-061 through SB-066 |
| Safety matrix enforcement | Regression, integration, LiveView | SB-039 through SB-060 |

## Scenario Matrix

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| SB-001 | P0 | DB | DB | Stores only encrypted ciphertext | World exists | Create `GITHUB_TOKEN` with fake value; reload raw DB column | `value_encrypted` is binary ciphertext and does not equal or contain plaintext | Assert no plaintext/preview/hash columns exist |
| SB-002 | P0 | DB | DB | World-scope uniqueness | World exists | Insert/create same key twice at world scope | One local row exists; API performs replace/upsert or DB rejects duplicate | Covers partial unique index |
| SB-003 | P0 | DB | DB | City-scope uniqueness | World and city exist | Create same key twice at same city | One local city row exists | Same key may also exist at world |
| SB-004 | P0 | DB | DB | Department-scope uniqueness | Department exists | Create same key twice at same department | One local department row exists | Same key may exist at parent scopes |
| SB-005 | P0 | DB | DB | Lemming-scope uniqueness | Lemming exists | Create same key twice at same lemming | One local lemming row exists | Same key may exist at parent scopes |
| SB-006 | P0 | DB | DB | Invalid hierarchy shape blocked | Direct changeset or insert attempt | Attempt department without city and lemming without department | Changeset/DB constraint rejects invalid shape | Use changeset when possible; DB constraint coverage acceptable |
| SB-007 | P1 | DB | DB | Secret rows cascade with owner | Hierarchy with secrets at all scopes | Delete city/department/lemming owner | Owned lower-scope secret rows are deleted | Audit events remain, IDs nilified where configured |
| SB-008 | P1 | DB | DB | World isolation for same key | Two worlds exist | Create same key in both worlds and list/resolve per world | Each world sees only its own effective metadata/value | No cross-world leakage |
| SB-009 | P0 | Integration | Validation | Context metadata excludes values | Secret exists | Call `list_effective_metadata/2` and inspect returned maps | Maps include key/source/configured/timestamps/actions only; no `value`, preview, hash, ciphertext | Regression guard for read models |
| SB-010 | P0 | Integration | Validation | Replace never returns old or new value | Local secret exists | Replace value via context | Return metadata only; old/new values absent | Check audit payload too in SB-056 |
| SB-011 | P0 | Integration | Runtime | Env effective at world when no local value | Env allowlist configured and env var set | List metadata at world | Key shown as configured from `env`; no delete action | Must restore app/env config after test |
| SB-012 | P0 | Integration | Runtime | World overrides env | Env fallback and world secret exist | List/resolve at world | Source is current/world, not env; runtime returns world fake value | Value only from runtime API boundary |
| SB-013 | P0 | Integration | Runtime | City inherits world | World secret exists; city has no local value | List metadata at city; resolve at city | Source identifies world; delete unavailable | Display source may be scope label/current implementation source string |
| SB-014 | P0 | Integration | Runtime | City overrides world/env | City local secret exists for inherited key | List/resolve at city | Source is current city; city fake value wins | Parent no longer effective for that key |
| SB-015 | P0 | Integration | Runtime | Department inherits city/world/env | Parent secret exists; department has no local value | List/resolve at department | Most specific parent source is effective | Repeat for city, world, env parents where practical |
| SB-016 | P0 | Integration | Runtime | Department override fallback | Department local secret overrides city | Delete department local secret | Effective source falls back to city | Covers required override fallback |
| SB-017 | P0 | Integration | Runtime | Lemming inherits department/city/world/env | Parent secret exists; lemming has no local value | List/resolve at lemming | Most specific parent source is effective | Covers lemming effective display |
| SB-018 | P0 | Integration | Runtime | Lemming override fallback | Lemming local secret overrides department | Delete lemming local secret | Effective source falls back to department | Covers most-specific delete fallback |
| SB-019 | P0 | Integration | Validation | Delete local world secret | World local secret exists | Delete from world scope | Local row removed; env fallback appears if configured or key unresolved | Audit event recorded |
| SB-020 | P0 | Integration | Validation | Delete local city secret | City override exists over world | Delete from city scope | City row removed; world effective metadata returns | Inherited source not deleted |
| SB-021 | P0 | Integration | Validation | Delete local department secret | Department override exists over city | Delete from department | Department row removed; city effective metadata returns | Required fallback case |
| SB-022 | P0 | Integration | Validation | Delete local lemming secret | Lemming override exists over department | Delete from lemming | Lemming row removed; department effective metadata returns | Required fallback case |
| SB-023 | P0 | Integration | Auth | Inherited delete blocked | Child scope sees inherited key | Call delete at child for inherited key | Returns `:inherited_secret_not_deletable`; parent row remains | Same expectation for env inherited source |
| SB-024 | P1 | Integration | Validation | Replace requires local secret | Child scope only inherits key | Attempt replace-only API if available or UI replace action | Returns safe `:local_secret_required_for_replace` or edit action unavailable | Current `upsert_secret/3` may intentionally create/replace; adapt to implemented API |
| SB-025 | P0 | Unit | Runtime | `$secrets.*` secret reference normalization | Parser available | Normalize `$secrets.GITHUB_TOKEN`, `$GITHUB_TOKEN`, and normalized `GITHUB_TOKEN` according to the final contract | Accepted reference forms resolve to `GITHUB_TOKEN`; unsupported forms are rejected by explicit contract tests | This row must expose the current `$KEY` vs `$secrets.*` drift |
| SB-026 | P0 | Unit | Validation | Malformed secret reference rejected | Parser/runtime API available | Resolve `$`, `$secrets.`, `$secrets`, empty key, lowercase/invalid chars, unsafe punctuation | Returns `:invalid_key` and records safe failure where runtime API is used | Error contains no value |
| SB-027 | P0 | Integration | Runtime | Missing secret returns safe error | No local or env value | Resolve configured/valid missing key | Returns `{:error, :missing_secret}`; audit `secret.access_failed` recorded | No adapter execution |
| SB-028 | P0 | Integration | Runtime | Non-allowlisted env ignored | Real env var set but no allowlist entry | Resolve matching key | Returns `:missing_secret`; no environment scanning | Critical env safety |
| SB-029 | P1 | Integration | Runtime | Explicit env override used | Config maps key to distinct env var | Resolve key with env var set | Returns env fake value; source `env`; event safe | Example `OPENROUTER_DEFAULT -> OPENROUTER_API_KEY` if valid in implementation |
| SB-030 | P1 | Integration | Runtime | Decrypt failure safe path | Corrupt ciphertext or use test hook if available | Resolve local secret | Returns `:decrypt_failed` or safe provider failure; no raw value in error/event/log | If corruption is impractical, document residual manual/security test |
| SB-031 | P0 | LiveView | UI | World Secrets surface renders safe metadata | World page mounted with env/local secret | Visit world detail | Shows key, source, `[configured]`, safe timestamps/actions; no value | Use stable `*-secrets-*` selectors |
| SB-032 | P0 | LiveView | UI | World create/replace flow | World page mounted | Submit secret form twice for same key with fake values | Row remains configured; no value in rendered HTML; activity updates | Assert form IDs, not raw HTML blob |
| SB-033 | P0 | LiveView | UI | City inherited secret not deletable | City inherits world/env key | Visit city surface | Inherited row visible; no delete button for inherited row | Stable row/action IDs |
| SB-034 | P0 | LiveView | UI | City local override actions visible | City has local key | Visit city surface | Edit/delete controls visible for local row only | No reveal/copy/export controls |
| SB-035 | P0 | LiveView | UI | Department inherited secret not deletable | Department inherits city key | Visit department surface | Inherited row visible; delete button absent | Required acceptance criterion |
| SB-036 | P0 | LiveView | UI | Department override hides inherited source | Department creates same inherited key | Submit local value | Row source becomes department/current; parent row not duplicated as effective | Checks effective list dedupe |
| SB-037 | P0 | LiveView | UI | Department delete fallback | Department local override exists over city | Click delete and confirm | Row source returns to city; value never rendered | Stable delete selector |
| SB-038 | P0 | LiveView | UI | Lemming create/delete fallback | Lemming inherits department key | Create local override, then delete it | Source changes to lemming/current, then back to department | Covers lemming UI path |
| SB-039 | P0 | LiveView | UI | UI has no reveal/copy/export affordances | Any secret surface with secrets | Render all Secret surfaces | No reveal/copy/export buttons or text; no first/last/hash/preview | Avoid asserting against whole page; use targeted selectors/text |
| SB-040 | P0 | LiveView | UI | Password input submission does not echo value | Secret form submitted with sentinel fake value | Check rendered HTML and flash | Sentinel absent from HTML/flash | Covers validation success path |
| SB-041 | P0 | LiveView | Validation | Validation errors safe | Submit invalid key with value sentinel | Check error render | Error mentions invalid key safely; sentinel value absent | Do not echo submitted secret value |
| SB-042 | P0 | Integration | API | Metadata inspect/log safety | Secret schema loaded inside boundary | Inspect metadata/read model and context return values | No secret value in inspect output; schema value field redacted if inspected | Focus on public returns; schema redact is secondary |
| SB-043 | P0 | Integration | Observability | Application logs avoid values on admin change | Capture logs around create/replace/delete | Perform admin operations with sentinel | Logs do not include sentinel/old/new values | Include safe IDs/event names only |
| SB-044 | P0 | Integration | Observability | Application logs avoid values on runtime access/failure | Capture logs around resolve success/failure | Resolve sentinel secret and missing key | Logs do not include sentinel | Covers failure reason safety |
| SB-045 | P0 | Integration | Runtime | Trusted tool config references resolve | Tool/adapter config contains `$secrets.GITHUB_TOKEN` or the final approved reference form | Execute tool through runtime with fake adapter | Adapter receives raw value only inside trusted call | Audit `secret.accessed` recorded |
| SB-046 | P0 | Integration | Runtime | Model-provided args do not resolve refs | Tool args from model contain `$secrets.GITHUB_TOKEN` and `$GITHUB_TOKEN` | Execute tool path | Adapter/model sees literal arg or safe rejection; no secret access event | Critical untrusted input boundary |
| SB-047 | P0 | Integration | Runtime | Missing trusted secret aborts adapter | Trusted config references absent key | Execute tool path | Adapter is not called; safe tool error returned; `secret.access_failed` event recorded | No partial credentials |
| SB-048 | P0 | Integration | Runtime | Prompt/context messages exclude values | Runtime uses secret-backed tool | Inspect model prompt/context messages | Sentinel absent; safe configured status/reference only if needed | Covers Lemming/LLM boundary |
| SB-049 | P0 | Integration | Runtime | Tool execution summaries exclude values | Runtime uses secret-backed tool | Inspect tool execution/activity summary | Sentinel absent; secret ref/status safe | Covers persisted tool execution records |
| SB-050 | P0 | Integration | Runtime | Runtime snapshots exclude values | Runtime uses secret-backed tool | Inspect page data/snapshot output | Sentinel absent from snapshot maps/JSON | Covers instance/page snapshots |
| SB-051 | P0 | Integration | Runtime | Finalization payload excludes values | Secret-backed execution finalizes | Inspect finalization payload/message | Sentinel absent | Required safety surface |
| SB-052 | P0 | Integration | PubSub | PubSub events exclude values | Subscribe to runtime topics | Execute secret-backed tool | Broadcast payloads contain no sentinel, preview, or hash | Covers runtime/event stream |
| SB-053 | P0 | Integration | Audit | `secret.created` durable event | Create local secret | Query recent events | Event exists with safe message/payload; no value | Include scope IDs |
| SB-054 | P0 | Integration | Audit | `secret.replaced` durable event | Replace local secret | Query events | Event exists; old/new sentinels absent | Payload safe fields only |
| SB-055 | P0 | Integration | Audit | `secret.deleted` durable event | Delete local secret | Query events | Event exists; deleted value absent | Real delete plus immutable audit |
| SB-056 | P0 | Integration | Audit | `secret.accessed` durable event | Runtime resolves secret | Query events | Event includes key/ref, requested scope, resolved source/tool when available; no value | Product event minimum |
| SB-057 | P0 | Integration | Audit | `secret.access_failed` durable event | Runtime misses/invalid key | Query events | Event includes safe reason; no value | Cover missing and invalid variants |
| SB-058 | P1 | Integration | Audit | Recent activity hierarchy filtering | Events at world/city/department/lemming | List recent activity at each scope | Relevant ancestor/current events appear; unrelated sibling/world events do not leak across worlds | Verify deterministic ordering/limit |
| SB-059 | P1 | Integration | Observability | Telemetry metadata safe | Attach telemetry handler if events emitted | Perform runtime/admin operations | Metadata includes hierarchy IDs and safe names only; sentinel absent | If no telemetry exists, mark as not applicable with log coverage |
| SB-060 | P1 | Integration | Audit | Audit events immutable enough for MVP | Event created | Attempt public update/delete API discovery | No normal update/delete API exists for audit events | DB nilify behavior covered separately |
| SB-061 | P0 | Unit | Config | Env fallback policy convention mapping | App config has string entry | Call policy listing | Shows `bank_key`, derived env var, convention mapping kind, allowlisted status | No env value shown |
| SB-062 | P0 | Unit | Config | Env fallback policy explicit mapping | App config has tuple entry | Call policy listing | Shows explicit env var and mapping kind | No env value shown |
| SB-063 | P0 | LiveView | UI | Env fallback display is read-only | Settings/Secret surface mounted | Inspect env fallback section | Shows mapping metadata only; no create/replace/delete controls | No process env browsing |
| SB-064 | P0 | Integration | Runtime | Configured env fallback missing env value | Allowlist entry exists but env var unset | Resolve key | Returns `:missing_secret`; access_failed event safe | Distinguish configured-but-unset from non-allowlisted |
| SB-065 | P0 | Integration | Runtime | Env allowlist fallback overridden at every hierarchy level | Env value and local values exist at world/city/department/lemming | Resolve at each scope | World beats env; city beats world; department beats city; lemming beats department | Can be one comprehensive table-driven test |
| SB-066 | P1 | Integration | Seeds | Seeds idempotent and fake-only | Test DB migrated | Run seeds twice or seed helper twice | No duplicate sample secrets; counts stable; sample value fake and not rendered | Restore env/config as needed |

## Acceptance Criteria

- Given local secrets at world, city, department, and lemming scopes, when metadata is listed at each scope, then only the most specific effective key appears and all returned fields are safe metadata.
- Given an inherited secret at a child scope, when the admin views that child Secrets surface, then the inherited key is visible as configured and delete is unavailable.
- Given a child creates a local secret with an inherited key, when the effective list is refreshed, then the child source wins and the inherited row is not duplicated for that key.
- Given a local override is deleted, when parent or env fallback exists, then the next inherited source becomes effective; when none exists, the key becomes unresolved.
- Given an env var exists without an allowlist entry, when runtime resolves that key, then resolution returns `:missing_secret` and does not read from the open process environment.
- Given malformed `$secrets`/`$` references or invalid keys, when normalized or resolved, then the API returns `:invalid_key` and records only safe failure metadata where applicable.
- Given a trusted tool/adapter config contains a secret reference, when the tool executes, then the adapter receives the raw value only inside the trusted call path and all serialized/runtime-visible payloads contain only safe metadata.
- Given a model-provided or user-provided tool argument contains a secret reference string, when the tool executes, then it is not resolved and does not produce `secret.accessed` audit events.
- Given create, replace, delete, access, and access failure operations, when recent events are queried, then durable events exist with safe event type, hierarchy IDs, key/ref, source/reason/tool metadata where applicable, and no value-bearing material.
- Given any Secret Bank operation uses sentinel fake value `dev_only_secret_sentinel_123`, when UI HTML, logs, events, telemetry metadata, PubSub payloads, prompts, snapshots, and finalization payloads are inspected, then the sentinel and any derived preview/hash are absent.

## Safety Matrix

| Surface | Must never contain | Verification scenario(s) | Required assertion |
|---|---|---|---|
| Database plaintext columns | Raw value, preview, hash, first/last chars | SB-001 | Only ciphertext binary stores value material; no plaintext columns |
| Context metadata/read models | Raw value, ciphertext, preview, hash | SB-009, SB-010 | Returned maps have only safe keys |
| Secret schema inspect output | Raw decrypted value | SB-042 | `inspect/1` redacts value-bearing field |
| LiveView rendered HTML | Raw value, preview, hash, reveal/copy/export controls | SB-031 through SB-041 | Sentinel absent; selectors show `[configured]` only |
| LiveView assigns rendered to client | Raw value or hidden form value after submit | SB-040, SB-041 | Sentinel absent from rendered view and flash/errors |
| Forms and validation errors | Submitted secret value | SB-040, SB-041 | Error text safe and value not echoed |
| Durable audit events | Raw/old/new values, preview, hash, provider token material | SB-053 through SB-058 | Event message/payload safe; sentinel absent |
| Logs | Raw values and derived material | SB-043, SB-044 | Captured logs do not include sentinel |
| Telemetry | Raw values and derived material | SB-059 | Measurements/metadata safe or no telemetry emitted |
| PubSub runtime events | Raw resolved values, secret-bearing adapter config | SB-052 | Broadcast payloads contain no sentinel |
| Tool execution records/activity | Raw resolved values, secret-bearing args/config | SB-049 | Persisted summaries safe |
| Lemming prompts/context messages | Raw values and secret inventory | SB-048 | Prompt/context contains no sentinel; no unrelated Bank inventory |
| Runtime snapshots/page data | Raw values, adapter config with resolved values | SB-050 | Snapshot maps/JSON contain no sentinel |
| Checkpoints/DETS/ETS persisted state | Raw values in serialized runtime state | SB-050 | Serialized state inspected for sentinel absence where accessible |
| Finalization payloads | Raw values, previews, hashes | SB-051 | Final message/payload contains no sentinel |
| Exceptions/error tuples | Raw values, provider token material | SB-026, SB-027, SB-030, SB-047 | Error atoms/messages safe |
| Env fallback UI | Env values, arbitrary env inventory | SB-061 through SB-064 | Shows only configured mapping metadata |
| Tool/model input boundary | Resolved secrets from untrusted args | SB-046 | No resolution and no access audit event |

## Regression Checklist

- Create/replace/delete local secrets at world, city, department, and lemming scope.
- Verify effective metadata source for env, world, city, department, and lemming sources.
- Verify inherited delete prevention at city, department, and lemming child scopes.
- Verify local override fallback after delete at city, department, and lemming scopes.
- Verify env allowlist convention, explicit override, configured-but-unset, and non-allowlisted env behavior.
- Verify `$`/`$secrets.*` normalization behavior matches the final implementation contract.
- Verify malformed secret refs and invalid keys return safe errors.
- Verify missing secret, decrypt/provider failure, and invalid scope paths produce safe events/errors.
- Verify durable events for create, replace, delete, accessed, and access_failed.
- Verify no raw values in UI, context returns, logs, audit events, telemetry, PubSub, prompts, snapshots, tool summaries, and finalization payloads.
- Verify seeded/demo Secret Bank data is idempotent and fake-only.
- Verify no env fallback table/schema/CRUD and no tool binding table/schema/CRUD were introduced.

## Narrow Tests To Run After Task 09

Run narrow checks first, expanding only if failures require it:

```bash
mix test test/lemmings_os/secret_bank_test.exs
mix test test/lemmings_os/events_test.exs
mix test test/lemmings_os/tools/runtime_test.exs test/lemmings_os/lemming_instances/executor/tool_step_runtime_test.exs
mix test test/lemmings_os_web/live/world_live_test.exs test/lemmings_os_web/live/cities_live_test.exs test/lemmings_os_web/live/departments_live_test.exs test/lemmings_os_web/live/lemmings_live_test.exs test/lemmings_os_web/live/settings_live_test.exs
mix test test/lemmings_os/seeds_test.exs
```

Final validation after the narrow tests pass:

```bash
mix precommit
```

If Task 09 adds or changes runtime snapshot/finalization coverage in other files, also run the directly touched executor/page-data tests before `mix precommit`.

## Out Of Scope

- Writing automated ExUnit or LiveView tests in Task 08.
- Multi-user authentication, RBAC, per-user permissions, or approval workflows.
- External secret managers, rotation automation, TTLs, or full connection object UI.
- Revealing, copying, exporting, hashing, partially masking, or previewing stored values.
- Testing real provider credentials or real external network calls.
