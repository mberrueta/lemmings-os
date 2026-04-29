# ADR-0010 — Control Plane Authentication and Admin Access

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# Context

LemmingsOS exposes a control plane used by human operators to manage the runtime.

The control plane includes the UI and APIs used to:

- create and manage Worlds, Cities, Departments, and Lemmings
- configure Tool policies
- manage connections and secrets
- inspect runtime state
- operate the system

Because LemmingsOS is designed to be self-hosted and may run on a publicly reachable VPS, the control plane must require authentication.

Without authentication, an exposed instance could allow unauthorized users to:

- spawn or terminate Lemmings
- execute tools against external systems
- modify runtime policy
- inspect internal system state

The architecture separates two different security domains:

Control Plane
: human operator authentication and administrative access

Runtime Plane
: Lemmings, tools, secret resolution, and agent execution

The Secret Bank subsystem manages runtime credentials for tools and must **not** be used for administrator authentication.

## Secret Bank MVP sequencing note

As of the Secret Bank MVP, the control plane still runs in the local-admin mode
used by the current Phoenix application. The Secret Bank UI and context APIs do
not enforce login, sessions, RBAC, per-user secret permissions, or per-user
actor attribution.

This is an implementation sequencing constraint, not a change to this ADR's
target authentication model. Deployments must treat the current control plane as
trusted/private network software until ADR-0010 is implemented.

This ADR also recognizes that LemmingsOS is more valuable than a purely personal single-user tool. For small teams, the system benefits significantly from allowing multiple authenticated users with access limited by hierarchy level.

---

# Decision Drivers

1. **Team viability** — Single-admin access creates poor traceability and prevents shared team operation. Multiple authenticated users with distinct roles must be first-class from v1.

2. **Hierarchy alignment** — Access scope must mirror the World → City → Department structure governing every other runtime concern. A separate model would create inconsistency between the runtime plane and the control plane.

3. **Self-hosted threat model** — The control plane may be exposed on a publicly reachable host. Authentication must be enforced from first boot with no open default.

4. **Separation of planes** — Control-plane user credentials must remain entirely separate from runtime credentials managed by the Secret Bank. The same subsystem must not serve both concerns.

5. **Proportional complexity** — v1 must be operable by a small team without deep security expertise. Fully configurable RBAC would add significant implementation and operational burden with marginal early benefit.

6. **Bootstrap safety** — A fresh installation must not accept connections before the first administrator account exists. The system must enter a constrained bootstrap mode automatically.

---

# Considered Options

## Option A — Single admin account only

One hardcoded admin account. No multi-user support, no scope restrictions.

**Pros:**

- simplest possible implementation
- no user management surface to secure

**Cons:**

- all control-plane actions are attributed to a single account, destroying per-actor traceability
- unsuitable for any team environment; multiple operators must share one password
- the audit log becomes meaningless for accountability when every event has the same actor

Rejected. Shared credentials make the audit model defined in ADR-0018 operationally useless for forensic reconstruction.

---

## Option B — Full configurable RBAC

User-defined roles, custom permission sets, and a policy editor in the control plane UI.

**Pros:**

- maximum flexibility for any organizational structure
- well-understood enterprise pattern

**Cons:**

- substantial implementation complexity disproportionate to v1 deployment scale
- policy misconfiguration risk increases when operators can define arbitrary permission matrices
- most self-hosted deployments will never use the flexibility
- authorization logic no longer mirrors the runtime hierarchy, creating a separate mental model to maintain

Rejected. Implementation and operational complexity are disproportionate to the realistic scale of v1 deployments.

---

## Option C — Small-team scoped access model (chosen)

Multiple users with fixed built-in roles (admin, operator, viewer) scoped to World, City, or Department.

**Pros:**

- multi-user support enables team deployments with per-actor audit trails
- fixed roles keep the permission model easy to audit and reason about
- scope assignments mirror the existing hierarchy — an operator managing a City understands immediately what they can and cannot access
- significantly simpler to implement and maintain than configurable RBAC

**Cons:**

- fixed roles cannot express all organizational permission structures
- no per-user exceptions or action-level permissions in v1

Chosen. Sufficient for the target use case and aligned with the system's existing hierarchical design principles.

---

# Decision

Version 1 of LemmingsOS implements a **small-team scoped access model**.

The system supports:

- multiple authenticated users
- password-based authentication
- fixed built-in roles
- scope-limited access aligned with the runtime hierarchy
- hashed password storage
- authenticated UI sessions
- append-only audit events for administrative and operational actions

Built-in roles for v1:

- `admin`
- `operator`
- `viewer`

Each non-admin access assignment is scoped to one hierarchy level:

- `world`
- `city`
- `department`

Permissions are **static and code-defined** in v1. The system does not implement configurable RBAC policies for individual users.

The effective access model is therefore:

```text
(role, scope_type, scope_id)
```

Examples:

- `admin, world, world_main`
- `operator, city, salvador`
- `viewer, department, customer_support`

---

# Access Model

## Role semantics

### Admin

Admin users may:

- manage users and assignments
- install and enable tool packages
- configure platform availability
- manage secrets and connections
- manage policies
- operate within their assigned scope and all descendants

In most deployments, admin will be assigned at world scope.

### Operator

Operators may perform mutating operational actions within their assigned scope and all descendants.

Examples:

- operator assigned to a `city` may create, update, and operate Departments and Lemmings in that city
- operator assigned to a `department` may create and operate Lemmings in that department

Operators may use only capabilities already made available by admins for that scope.

Operators may not:

- manage users
- install packages
- change platform-wide authentication settings
- access or manage secrets unless explicitly allowed by future policy work

### Viewer

Viewers have read-only access within their assigned scope and all descendants.

They may inspect:

- runtime state
- status
- logs and audit information permitted by the UI
- results and artifacts permitted by the UI

They may not perform mutating actions.

## Scope inheritance

Scope access flows downward.

A user assigned to a level may act on that level and every descendant level.

Examples:

- a `viewer` at `world` scope can view the full world
- an `operator` at `city` scope can operate that city and all departments under it
- an `operator` at `department` scope can operate only that department

This keeps the authorization model aligned with the core LemmingsOS hierarchy:

```text
World → City → Department → Lemming
```

---

# Bootstrap Flow (First Access)

A fresh installation contains no users.

When the system detects that no admin user exists, the UI enters **bootstrap mode**.

Bootstrap mode exposes only the initial administrator creation screen.

All other control plane endpoints remain unavailable.

Bootstrap flow:

```text
User opens UI
      ↓
System detects: no admin configured
      ↓
Bootstrap mode enabled
      ↓
First user creates admin account and password
      ↓
Password hashed and stored
      ↓
Bootstrap mode permanently disabled
```

After the first admin account is created:

- bootstrap endpoints are disabled
- authentication is required for all control plane operations
- all additional users must be created by an authenticated admin

Re-entering bootstrap mode requires explicit operator action, such as a database reset or dedicated recovery workflow.

---

# Password Storage

User passwords are stored **only as hashes**.

Plaintext passwords are never stored.

The recommended hashing algorithm is:

**Argon2id**

Reasons:

- modern password hashing standard
- memory-hard algorithm resistant to GPU attacks
- widely supported in Elixir ecosystems

Implementation guidelines:

- use a well maintained library such as `argon2_elixir`
- include a unique salt per password
- store algorithm parameters with the hash

Example schema shape:

```text
users
  id
  email
  password_hash
  inserted_at
  updated_at

user_assignments
  id
  user_id
  role
  scope_type
  scope_id
  inserted_at
```

Password hashes are never exposed via APIs or logs.

---

# Session Security

Administrative and operational actions require an authenticated session.

Typical flow:

```text
User login
   ↓
Password verification
   ↓
Session created
   ↓
Session cookie issued
   ↓
Subsequent UI/API requests require valid session
```

Session management should follow Phoenix security best practices:

- signed and encrypted cookies
- CSRF protection for form actions
- session invalidation on logout
- session renewal after login

Session expiration may be configurable.

---

# Password Rotation Policy

The system may optionally enforce password rotation.

Configuration example:

```text
auth:
  password_max_age_days: 180
```

If the password exceeds the configured age:

- the user must change the password before performing further control-plane actions

This feature is optional and may be disabled by default for small self-hosted installations.

---

# Admin-Controlled Platform Availability

Authentication and authorization are distinct from platform capability publication.

Admins control what is available in the system at three separate levels.

## 1. Platform availability

Admins may:

- install tool packages
- register tools
- enable or disable tools globally
- manage connections and secret-backed integrations

## 2. Scope availability

Admins may decide what is available at each hierarchy level.

Examples:

- enable Tool A for a World
- enable Tool B only for one City
- allow a Department to use a subset of platform capabilities

## 3. User access

Users may act only within their assigned scope and only on capabilities already made available above them.

This ensures that operators do not define platform capabilities themselves. They operate only on the subset published by admins.

---

# Audit Events

Administrative and operational actions generate events in the global append-only audit log.

Examples of auditable events:

- user login
- user logout
- password change
- user created
- assignment changed
- tool package installed
- tool enabled or disabled
- policy change
- secret creation or modification
- Department created or updated
- Lemming created, paused, resumed, or terminated

Audit records should contain enough actor and scope detail to support traceability.

Example fields:

```text
event_type
actor_user_id
actor_role
world
city
department
description
timestamp
```

Audit logs are append-only and immutable.

This aligns with the system-wide audit log design already used for secret access and runtime events.

---

# Security Principles

### Control Plane vs Runtime Plane

Authentication applies only to the control plane.

Lemmings and tools do not authenticate using human user accounts.

Runtime components operate using runtime policies and the Secret Bank.

### Secret Bank Separation

The Secret Bank is used only for runtime credentials required by tools.

It must **never** store user passwords or authentication data.

Control-plane authentication and runtime secret management are separate subsystems.

### Static authorization model in v1

Version 1 uses built-in roles and hierarchy-based scope rules.

It does **not** support arbitrary custom permission matrices, per-user exceptions, or dynamic RBAC policy editors.

This keeps the initial security model understandable and auditable.

---

# Non-Goals for v1

The following capabilities are explicitly **out of scope for v1** and will be defined in future ADRs:

- fully configurable RBAC
- per-action custom permission matrices
- two-factor authentication (TOTP)
- hardware security keys
- VPN-only control plane access
- IP allowlists
- SSO integrations (OAuth, OIDC, SAML, etc.)

The v1 goal is a secure, useful, and simple model suitable for single operators and small teams.

---

# Rationale

A pure single-admin model is simpler, but it creates weak traceability and poor fit for team use.

A full enterprise RBAC model would add substantial complexity too early.

The chosen model is the middle path:

- more useful than single-user access
- much simpler than generic RBAC
- naturally aligned with the World → City → Department hierarchy
- sufficient for small teams operating a shared LemmingsOS deployment

This makes LemmingsOS viable not only as a personal self-hosted tool, but also as an internal platform for a company with a small number of employees.

---

# Consequences

## Positive

- Multi-user support with per-actor audit trails makes LemmingsOS viable as a shared team platform, not only as a personal self-hosted tool.
- Scope-aligned role assignments are immediately intuitive to operators already familiar with the World → City → Department hierarchy.
- Fixed roles reduce the attack surface of the authorization system itself — there are no policy editors to misconfigure.
- Bootstrap mode ensures an exposed installation cannot accept unauthorized connections before the first admin account exists.

## Negative / Trade-offs

- Fixed roles cannot model every organizational access structure. Teams with non-standard reporting hierarchies will encounter limitations that configurable RBAC would address.
- Password-only authentication has weaker assurance than MFA. Until TOTP is introduced, a compromised password grants full access within the user's scope.
- No per-user exceptions in v1. Granting a user a temporary elevated capability requires assigning a broader role than desired for that period.

## Mitigations

- The `(role, scope_type, scope_id)` tuple schema is designed to accommodate configurable RBAC extension in a future ADR without a table redesign.
- Argon2id password hashing is memory-hard and resistant to GPU-based brute-force attacks, reducing exposure from compromised password hashes.
- Append-only audit events record every authentication and administrative action, providing forensic detection capability even in the absence of MFA.

---

# Future Extensions

Potential improvements include:

- multiple roles per user
- configurable RBAC
- action-level permissions
- temporary access grants
- SSO integration
- hardware-backed authentication
- control plane network restrictions

These features will be defined in future ADRs once the core runtime architecture stabilizes.
