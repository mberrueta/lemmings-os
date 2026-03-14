# ADR-0009 — Secret Bank (Hierarchical Secret Management)

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

## Context

LemmingsOS needs a secure mechanism for storing and resolving credentials required by Tools (for example API tokens, service credentials, or integration keys).

Because the runtime supports a hierarchical architecture:

```
World
  └ City
      └ Department
```

secret storage must support scoped resolution so that different environments or departments can override credentials while still allowing shared defaults.

The system must also ensure that:

- Tools cannot request arbitrary secrets
- Lemmings never see raw secrets
- secrets are injected only inside the Tool Runtime
- secrets are never persisted in agent context, logs, or checkpoints

This design must remain simple enough for a self‑hosted open source deployment while allowing future expansion to external secret managers.

---

# Decision

LemmingsOS will implement a **Secret Bank subsystem** responsible for storing and resolving runtime secrets used by Tools.

The Bank stores **logical secret keys** and resolves them according to a **hierarchical scope model**.

Scopes:

```
Department → City → World
```

When resolving a secret, the runtime always prefers the **nearest scope**.

Example:

```
resolve_secret("github.token")

Lookup order:
1. Department
2. City
3. World
```

The first matching secret found is returned to the Tool Runtime.

---

# Secret Keys

Secrets are stored in the Bank using **logical keys**, not environment variable names.

Examples:

```
github.token
openai.api_key
aws.access_key_id
aws.secret_access_key
```

Each key may exist at any scope.

Example:

```
World
  github.token = <org default>

City
  github.token = <region bot>

Department
  github.token = <team credential>
```

Resolution precedence ensures local overrides are possible without duplicating configuration globally.

---

# Tool Secret Requirements

Tools declare the logical secrets they require as part of their contract.

Example:

```
tool: github_issue_creator
required_secrets:
  - github.token
```

These requirement names are **logical identifiers**, not references to concrete storage keys.

Tools therefore remain generic and reusable across deployments.

---

# Secret Bindings

Concrete secret resolution is controlled by **Tool Policy**, not by the Tool itself.

Each Tool configuration may define **secret bindings** mapping logical requirements to concrete Bank keys.

Example:

```
secret_bindings:
  github.token: secrets.github.company
```

This means:

```
Tool requires: github.token
Policy binds to: secrets.github.company
Bank returns value stored under that key
```

This ensures:

- Tools cannot request arbitrary Bank secrets
- credential selection is controlled by runtime configuration
- multiple Tools may use different credentials for the same provider

Example:

```
Tool: github_issue_creator
secret_bindings:
  github.token: secrets.github.company

Tool: github_repo_reader
secret_bindings:
  github.token: secrets.github.personal
```

---

# Runtime Resolution Flow

Execution sequence:

```
Lemming
   ↓
Tool Runtime
   ↓
Tool contract declares required secrets
   ↓
Tool policy resolves secret bindings
   ↓
Bank resolves secret key by scope
   ↓
Secret injected into Tool Runtime
```

Secrets are **never exposed to the Lemming** and must never appear in:

- agent context
- logs
- checkpoints
- persisted agent state

---

# Scope Resolution

Secret lookup follows nearest‑scope precedence:

```
Department
  → City
      → World
```

This allows local overrides without duplicating configuration globally.

Example:

```
World
  github.token = org_default

Department
  github.token = client_x_token
```

Tools executed inside that Department will automatically use the department credential.

## Intentional asymmetry with policy evaluation

Secret resolution and tool policy evaluation (ADR-0012) intentionally use **opposite precedence rules**. This is not an inconsistency — it reflects the different nature of each concern.

**Secrets resolve upward (most specific wins):**
Secret resolution is a *definition lookup*. The runtime searches from the most specific scope upward until it finds a binding. A Department-level secret overrides a City-level secret for the same key because the Department is explicitly providing a more specific credential. This is the standard override model: local configuration overrides shared defaults.

**Policy evaluates downward (deny-dominant):**
Policy evaluation is *authorization enforcement*. A deny rule at any level in the hierarchy is final and cannot be overridden by a more specific level below it. A Department cannot grant a tool that World has denied. If "most specific wins" applied to denies, any Department admin could escape platform-level restrictions — which would defeat the purpose of hierarchical governance.

In summary:
- Most specific wins → appropriate for *finding the right credential*
- Most restrictive wins → appropriate for *enforcing security constraints*

---

# Responsibilities

The Secret Bank is responsible for:

- storing encrypted secret values
- resolving scoped secret keys
- returning secret values only to the Tool Runtime

The Bank is **not responsible for**:

- administrator authentication
- UI access control
- platform login credentials

Administrative authentication belongs to a separate control‑plane subsystem defined in ADR-0010.

---

# Secret Encryption

All secret values stored in the Bank are encrypted at rest.

Encryption uses a system master key provided through environment configuration.

Example:

```
LEMMINGS_MASTER_KEY
```

The master key is never stored in the database.

Secrets are encrypted before persistence and decrypted only when injected into the Tool Runtime.

The v1 encryption algorithm is **XChaCha20-Poly1305**.

Rationale for this choice:

- Provides authenticated encryption (confidentiality + integrity)
- Uses extended nonces (192-bit) which significantly reduces the risk of nonce reuse errors in distributed systems
- Well supported by modern cryptographic libraries (libsodium and Rust/Go/Elixir bindings)
- Considered state-of-the-art for application-level secret encryption
- Simpler operational model compared to schemes requiring strict nonce management

If the master key is lost or replaced without a coordinated migration process, previously stored secrets become unreadable and cannot be recovered.

For that reason, installation and operational documentation must clearly explain:

- how to generate the master key
- how to store it securely
- how to back it up safely
- the operational consequences of losing or changing it

---

# Security Guarantees

The system guarantees that:

- Lemmings never have direct access to secret values
- Tools can only access secrets declared in their contract
- policies control which concrete credentials a Tool receives
- secrets are resolved only during Tool execution

---

# Audit and Change Tracking

Secret management must include **auditability from day one**.

The system records immutable **audit events** using a generic append‑only audit log shared by the platform.

Each event contains:

- event type
- world
- city
- department
- tool (if applicable)
- contextual text / description
- timestamp

The log is **append‑only and immutable**.

Example audit record:

```
secret, m1, c1, d1, t1, access gh_token, inserted_at
```

Typical secret‑related events include:

- secret created
- secret replaced
- secret accessed by Tool Runtime

Audit logs must **never include the secret value itself**.

The goal of auditing is operational traceability, not secret recovery.

---

# Secret Immutability

Secret values are treated as **write‑only material**.

Once stored:

- the raw value cannot be retrieved through the UI
- the value cannot be displayed again
- the value cannot be exported

Updating a secret replaces the stored value but does not expose the previous one.

This model mirrors common operational patterns used by platforms such as Fly.io, where secrets are write‑once and not readable after creation.

---

# Connection Objects (Day‑0 Support)

Although v1 secret storage operates on logical secret keys, the Bank may also support **Connection Objects** from the start.

A Connection Object groups configuration and secret references required to access an external system.

Example:

```
connection: github_company

config:
  base_url: https://api.github.com

secrets:
  token: github.token
```

Tools may reference a connection instead of resolving multiple individual secrets.

Connection objects provide:

- cleaner configuration for complex integrations
- grouping of related credentials
- easier reuse across tools

Connection objects still rely on the same underlying Bank resolution model and secret bindings.

---

# Consequences

## Positive

- Lemmings and runtime state are structurally isolated from secret values; a
  storage breach of Postgres, ETS, or DETS does not expose credentials.
- Secret resolution through a single Bank abstraction means policy inheritance
  and audit coverage apply consistently to every credential, regardless of the
  tool consuming it.
- Connection Objects group related credentials behind a logical name; tool
  authors reference `connection_ref = "github_prod"` rather than managing
  individual secret keys.
- The write-only immutability model prevents accidental secret exposure through
  the control plane UI or API.

## Negative

- Loss of the master key renders all stored secrets permanently unreadable;
  there is no recovery path without the key.
- v1 secret storage is limited to environment-variable-backed values; operators
  who need secret rotation, fine-grained TTLs, or audit trails beyond the
  platform's own log must integrate an external manager as a future extension.
- The Bank is City-local in v1; there is no cross-City secret replication.
  If a City node is unavailable, its secrets are inaccessible until the node
  recovers.

## Mitigations

- The master key must be treated as a critical operational secret: generated
  securely, stored in a separate secure location (not the same system as the
  database), and backed up. Installation documentation must make the recovery
  consequences explicit.
- The environment-variable storage model is acceptable for v1 self-hosted
  deployments. External secret manager integration (Vault, Infisical, cloud KMS)
  is a defined Future Extension and the Bank abstraction is designed to support
  it without changing the tool-facing API.

---

# Future Extensions

Possible future capabilities include:

- external secret manager integration (Vault, cloud KMS, etc.)
- automatic secret rotation

