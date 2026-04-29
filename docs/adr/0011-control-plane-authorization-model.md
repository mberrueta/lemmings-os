# ADR-0011 — Control Plane Authorization Model

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

LemmingsOS exposes a control plane used by human operators to manage the runtime.

Authentication verifies the identity of the user, but the system must also determine
whether that authenticated user is allowed to perform a specific action on a specific
resource.

Because LemmingsOS is structured around a strict hierarchy:

World → City → Department → Lemming

access control must align with this hierarchy so that permissions remain predictable
and easy to reason about.

The system already supports:

- multiple authenticated users (target architecture)
- fixed built-in roles (target architecture)
- scoped user assignments (target architecture)
- hierarchical runtime resources

Therefore a consistent authorization model is required to determine whether a user may
operate on a given resource.

## Secret Bank MVP sequencing note

The Secret Bank MVP does not yet apply this authorization model. The World,
City, Department, and Lemming Secret surfaces assume the current implicit local
admin. Secret create, replace, delete, metadata listing, and runtime resolution
validate hierarchy scope consistency, but they do not check authenticated user
roles or assignments.

Future authorization work must wrap Secret Bank admin actions with the role and
scope checks defined here. It must not add value reveal/export behavior.

---

# 2. Decision Drivers

1. **Predictability** — Authorization decisions must be deterministic given only the
   user's assignments and the target resource. Operators must be able to reason about
   access without consulting a policy engine or dynamic rules.

2. **Hierarchy alignment** — The runtime is organized by World → City → Department →
   Lemming. The authorization model must mirror this structure so that access
   assignments have intuitive and consistent scope semantics.

3. **Composability with authentication** — The authorization model must layer cleanly
   on top of the session-based authentication defined in ADR-0010 without introducing
   additional identity state or a separate credential store.

4. **Deny dominance** — Access must flow strictly downward. A user scoped to one City
   must never access a sibling City or a different World. Cross-scope escalation must
   be structurally impossible, not merely discouraged.

5. **Auditability** — Every authorization decision produces an audit event under the
   model defined in ADR-0018. The authorization check must supply enough context
   (actor, role, target resource, scope) for that event to be meaningful.

6. **Simplicity over expressiveness** — v1 must avoid custom policy languages or
   per-resource ACL matrices. Complexity must remain proportional to the actual
   deployment scale.

---

# 3. Considered Options

## Option A — Flat permission list per user

Each user receives a direct list of permitted actions (create_department, run_lemming,
manage_secrets, etc.) with no role abstraction.

**Pros:**

- maximum per-user precision
- no role semantics to understand

**Cons:**

- every new user assignment requires enumerating all applicable actions
- no natural grouping makes auditing whether a user has the right access difficult
- adding new actions to the system requires updating every affected user's permission list
- does not encode scope in a first-class way; scope logic must be added separately

Rejected. The per-action model creates high operational burden and does not naturally
compose with the hierarchy-scoped access pattern this system requires.

---

## Option B — Full RBAC with configurable roles

Roles, their permitted actions, and assignments are all configurable by administrators
at runtime.

**Pros:**

- maximum flexibility for any organizational structure
- roles can be tuned to exact organizational needs

**Cons:**

- configurable RBAC introduces a permission editor as a security-sensitive surface
- misconfigured roles can create privilege escalation paths that are hard to detect
- the implementation complexity is disproportionate to v1 deployment scale
- roles no longer mirror the fixed runtime hierarchy, creating a second mental model
  to maintain alongside it

Rejected. See ADR-0010 rationale. The complexity cost exceeds the value at v1 scale.

---

## Option C — Role + Hierarchical Scope authorization (chosen)

Fixed built-in roles (admin, operator, viewer) combined with hierarchy-scoped
assignments expressed as `(role, scope_type, scope_id)`.

**Pros:**

- authorization is fully deterministic given only role and scope — no policy engine required
- scope assignment directly mirrors the World → City → Department hierarchy
- adding a user is a single assignment, not a permission enumeration
- composable: multiple assignments per user enable cross-scope access when explicitly granted

**Cons:**

- fixed roles cannot express every organizational permission boundary
- no action-level exceptions in v1

Chosen. Sufficient for the target use case and structurally aligned with the existing
hierarchy.

---

# 4. Decision

LemmingsOS implements a **Role + Hierarchical Scope Authorization Model**.

Each user receives one or more assignments defined as:

(role, scope_type, scope_id)

Example:

operator, city, salvador

Authorization decisions are based on two checks:

1. The role must permit the requested action.
2. The user scope must be an ancestor of the target resource scope.

Access flows strictly downward along the system hierarchy.

---

# 5. Authorization Rule

A user may perform an action if both conditions are satisfied.

Condition 1

The assigned role allows the requested action.

Condition 2

The user's assigned scope is an ancestor of the target resource.

Conceptual rule:

ALLOW if

role_allows(role, action)
AND
scope_is_ancestor(user_scope, resource_scope)

Pseudocode:

```
def authorized?(user, action, resource) do
  Enum.any?(user.assignments, fn assignment ->
    role_allows?(assignment.role, action) and
    scope_ancestor?(assignment.scope, resource.scope)
  end)
end
```

---

# 6. Scope Inheritance

Scopes inherit downward along the hierarchy:

World
  → City
    → Department
      → Lemming

A user assigned at a given level may operate on that level and all descendants.

Examples

viewer(world)

→ may inspect the entire world

operator(city=salvador)

→ may operate city salvador
→ may operate departments in salvador
→ may operate lemmings inside those departments

operator(department=support)

→ may operate only that department
→ may operate lemmings inside that department

---

# 7. Role Permissions

Roles define the allowed actions independently from scope.

## Admin

Administrators have full administrative control within their scope.

Capabilities include:

- manage users and assignments
- install or remove tools
- configure platform capabilities
- manage secrets and connections
- operate runtime resources
- inspect logs and audit events

Admins cannot exceed their assigned scope.

## Operator

Operators manage runtime operations but cannot change platform configuration.

Capabilities include:

- create or update Cities (if scoped at World)
- create or update Departments (if scoped at City)
- create, run, pause, or stop Lemmings
- use tools enabled by administrators
- inspect runtime state

Operators cannot:

- manage users
- install tool packages
- configure authentication
- manage secrets

## Viewer

Viewers have read-only access.

Capabilities include:

- inspect runtime state
- view Cities, Departments, and Lemmings
- view logs and audit records

Viewers cannot perform mutating operations.

---

# 8. Resource Types

Authorization checks apply to control-plane resources.

Resource categories include:

- worlds
- cities
- departments
- lemmings
- tools
- secrets
- users

Each resource is associated with a scope that belongs to the hierarchy.

---

# 9. Examples

Example 1

Assignment:

operator(city=salvador)

Allowed actions:

- create department salvador/customer_support
- run lemming salvador/customer_support/bot-1
- pause lemming salvador/customer_support/bot-1

Denied actions:

- modify city rio
- create department rio/finance
- run lemming rio/finance/bot-5

Example 2

Assignment:

viewer(world)

Allowed actions:

- view city salvador
- inspect departments
- read logs

Denied actions:

- create lemming
- modify department

Example 3

Assignment:

admin(city=salvador)

Allowed actions:

- create departments in salvador
- manage secrets for salvador
- enable tools usable in salvador

Denied actions:

- manage secrets in rio
- install tools globally

---

# 10. Security Properties

The model provides several desirable properties.

Deterministic

Authorization decisions depend only on role, scope, and resource scope.

Hierarchy aligned

The authorization structure mirrors the runtime hierarchy.

Minimal complexity

The system avoids complex RBAC matrices and dynamic policy engines.

Safe defaults

Access flows downward only, preventing cross-scope privilege escalation.

---

# 11. Consequences

## Positive

- Authorization is fully deterministic: given a user's assignments and the target
  resource scope, the outcome is computable without a policy engine or runtime
  configuration lookup.
- Scope assignments are self-documenting. An operator assigned to `city=salvador`
  clearly governs that City and its descendants — no policy documentation required.
- The two-condition rule (role_allows AND scope_ancestor) keeps the authorization
  check testable as a pure function, simplifying both implementation and audit.

## Negative / Trade-offs

- Fixed roles cannot model every organizational boundary. Teams where an operator
  needs read access to one City and write access to another must receive two
  assignments, and there is no role that permits exactly that combination of actions.
- No action-level exceptions. Granting a user one elevated permission requires
  assigning them a broader role for the entire scope.
- The model does not support temporary access grants. Access remains until an
  administrator explicitly removes the assignment.

## Mitigations

- Multiple assignments per user accommodate non-standard organizational structures
  by composing existing roles and scopes rather than requiring custom roles.
- The `(role, scope_type, scope_id)` schema is designed to extend toward configurable
  roles in a future ADR without requiring a schema redesign.
- All assignment changes produce audit events (ADR-0018), providing visibility into
  access changes even in the absence of temporary grant semantics.

---

# 12. Non-Goals

The following features are explicitly out of scope for v1.

- dynamic RBAC
- per-action custom policy engines
- user-defined roles
- ACL allow/deny lists
- permission editors in the UI

The v1 goal is a simple and predictable authorization model.

---

# 13. Future Extensions

Potential future work includes:

- full RBAC with configurable roles
- temporary access grants
- per-resource policies
- organization-level roles


---

# 14. Authorization Evaluation Flow

Control-plane requests follow a deterministic evaluation pipeline.

```
request received
      ↓
authenticate user session
      ↓
load user assignments
      ↓
authorization check
      ↓
execute control‑plane action
      ↓
append audit event
```

Explanation of each step:

1. **Request received**

A control-plane request arrives through the UI or API.

2. **Authenticate user session**

The system verifies that the request is associated with a valid authenticated session.

3. **Load user assignments**

The runtime retrieves all `(role, scope_type, scope_id)` assignments associated with the user.

4. **Authorization check**

The authorization rule defined in this ADR is evaluated:

```
role_allows(role, action)
AND
scope_is_ancestor(user_scope, resource_scope)
```

If no assignment satisfies both conditions, the request is rejected.

5. **Execute control-plane action**

If authorization succeeds, the requested control-plane operation is executed.

6. **Append audit event**

The system records the action in the append-only audit log, including:

- actor user
- role used
- target resource
- world / city / department context
- timestamp

This guarantees traceability for all administrative and operational actions.

---

# 15. Rationale

LemmingsOS already organizes all runtime configuration around the World → City →
Department hierarchy. An authorization model that introduces a separate structure would
require operators to maintain two distinct mental models for the same system.

The chosen model keeps authorization aligned with the runtime hierarchy: a user's
scope of access mirrors the scope of the resources they manage. This makes
misconfiguration visible — an operator assigned to the wrong City is immediately
apparent from the assignment record, without needing to trace through a permission
matrix.

Fixed roles accept the trade-off of reduced expressiveness in exchange for predictable
semantics, reduced implementation complexity, and an authorization system that is
auditable by inspection.
