# ADR-0022 — Deployment and Packaging Model

Status: Accepted (narrowed 2026-03-19)
Date: 2026-03-14
Decision Makers: LemmingsOS maintainers

---

# Decision

LemmingsOS is deployed as a **Mix Release packaged as an OCI-compatible container image**.

Reference deployment stack:

- Elixir Mix Release
- OCI container image (Docker-compatible)
- PostgreSQL database
- Phoenix web interface
- Distributed Erlang clustering

Each **City corresponds to one runtime node**, and each runtime node typically runs inside **one container**.

Multiple Cities form a **World cluster**.

The container includes the compiled OTP release and runtime configuration but relies on **external PostgreSQL storage**.

The release also ships with a default bootstrap file at
`priv/default.world.yaml`. Operators may override that path with
`LEMMINGS_WORLD_BOOTSTRAP_PATH`.

Docker is the **reference container runtime**, but any OCI-compatible runtime (such as **Podman**) is supported.

Running a Mix Release directly on the host system is also technically possible, but container packaging is the **canonical operational model**.

This model provides:

- reproducible builds
- consistent runtime environments
- simple self-hosting
- compatibility with container orchestration platforms

---

# Deployment Architecture

```
           ┌─────────────────────────────┐
           │           World             │
           │        (cluster scope)      │
           └─────────────┬───────────────┘
                         │
       ┌─────────────────┴─────────────────┐
       │                                   │
  ┌────┴─────┐                       ┌─────┴─────┐
  │ City A   │                       │ City B    │
  │ Docker   │                       │ Docker    │
  │ OTP Node │                       │ OTP Node  │
  └────┬─────┘                       └─────┬─────┘
       │                                   │
  Departments                         Departments
       │                                   │
  Lemmings                            Lemmings
```

Key properties:

- **World** is a logical cluster boundary
- **City** is a running OTP node
- Each City executes inside its own container
- Departments and Lemmings run inside the node supervision tree

Cities self-register against the shared PostgreSQL database on startup.
Erlang distribution clustering is not yet enabled (see Clustering Model).

---

# Packaging Model

Packaging is composed of two layers.

## Application Package

The application is built as a standard **Mix project** that produces a compiled OTP release.

Release artifacts are produced with:

```
mix release
```

The compiled release is located at:

```
_build/prod/rel/lemmings_os
```

This release contains:

- compiled BEAM bytecode
- supervision tree configuration
- runtime configuration loader
- Phoenix endpoint


## Container Image

The release is embedded inside a Docker image.

The Docker image contains:

- compiled Mix release
- runtime configuration files
- entrypoint script
- minimal runtime OS environment

The container is the primary distribution artifact used for deployment.

---

# Runtime Components in the Container

Each container runs the full runtime stack for a City node.

Processes running inside the container include:

- Phoenix HTTP server
- runtime supervision tree
- Lemming execution engine
- tool runtime
- telemetry emitters
- bootstrap importer
- world cache

Startup runs a World bootstrap import that syncs persisted `worlds` state from
the bootstrap YAML.

Persistent storage is externalized.

The PostgreSQL database runs **outside the container**.

The DETS idle-snapshot store (ADR-0008) writes to the local filesystem and **must be backed by a persistent volume**. Without a mounted volume, container restarts destroy all idle Lemming snapshots and defeat the rehydration guarantee.

---

# Clustering Model

Prior wording described Cities forming a distributed Erlang cluster. The
shipped implementation does **not** use distributed Erlang clustering.

Each runtime node:

- has a unique BEAM node name (`node_name` in `name@host` form)
- runs with `RELEASE_DISTRIBUTION=none` (no Erlang distribution)
- self-registers against the shared PostgreSQL database on startup
- maintains liveness through local heartbeat writes to `last_seen_at`

There is no inter-node communication, no cluster membership protocol, and no
distributed Lemming execution.

### Deferred clustering capabilities

The following are architecturally intended but explicitly deferred:

- distributed Erlang clustering between Cities (requires a future ADR)
- inter-city communication and routing
- cluster-wide coordination
- secure remote City attachment and secret distribution (requires a
  dedicated ADR and security design)

World isolation guarantees that nodes belonging to different Worlds never
share data. This constraint applies regardless of whether clustering is
eventually enabled.

---

# Installation Modes

The system supports multiple deployment modes.

## Local Development

Developers run a single node locally using:

```
mix phx.server
```

This runs:

- Phoenix server
- runtime supervisors
- local PostgreSQL database
- startup World bootstrap import against `priv/default.world.yaml` unless
  `LEMMINGS_WORLD_BOOTSTRAP_PATH` overrides it

This mode prioritizes fast feedback during development.

---

## Single-Node Production

A single container runs the entire runtime.

Components:

- Phoenix
- runtime engine
- one City node

Suitable for:

- small teams
- experimentation
- staging environments

---

## Multi-City Deployment

Multiple containers run the same application image with different identity
env vars.

Example topology (shipped compose demo):

```
World
 ├─ world  (control-plane + City, runs Phoenix UI and migrations)
 ├─ city_a (City node, no web UI by default)
 └─ city_b (City node, no web UI by default)
```

Each container runs a single City node. All containers share the same
PostgreSQL database. City identity is varied through environment variables:

- `LEMMINGS_CITY_NODE_NAME` -- full BEAM identity in `name@host` form
- `LEMMINGS_CITY_SLUG` -- human-readable slug
- `LEMMINGS_CITY_NAME` -- display name
- `LEMMINGS_CITY_HOST` -- host portion of the node identity

The compose demo uses `RELEASE_DISTRIBUTION=none` (no Erlang clustering)
and `network_mode: host`. Stopping a city container causes its heartbeat
to stop, making it stale in the UI after the configured freshness threshold
(default 90 seconds).

This model demonstrates multi-City visibility and stale detection. It does
not demonstrate work dispatch, clustering, or secure remote attachment.

---

# Operational Characteristics

The deployment model prioritizes the following properties:

- **simple self-hosting**
- **container-native deployment**
- **reproducible builds**
- **predictable node topology**
- **horizontal scalability through Cities**

Operators can scale the system by adding or removing City containers.

---

# Security Boundaries

Containerization also provides an important **security boundary** for the runtime.

Running LemmingsOS inside a container restricts the default filesystem and process visibility of the application. The runtime only sees the files and system resources available inside the container image and its configured mounts.

This design reduces the risk of agents or tools accidentally accessing sensitive parts of the host system.

External directories may still be shared intentionally using **container volumes**. For example:

- mounting a project repository for analysis
- exposing a data directory
- sharing artifacts produced by tools

Example conceptually:

```
-v ./project:/workspace/project
```

However, this access is **explicit and operator-controlled**.

This model allows LemmingsOS to run safely on a personal workstation or development machine while maintaining strict boundaries around what agents can access.

This contrasts with systems that allow unrestricted shell access to the host environment, which can create significant security risks when running autonomous agents.

Container isolation therefore provides:

- controlled filesystem exposure
- predictable execution environments
- safer local self-hosting

Conceptual isolation model:

```
Host OS
   │
   ├── Docker / Podman Runtime
   │       │
   │       └── LemmingsOS Container
   │              │
   │              ├── Phoenix Server
   │              ├── Runtime Supervisors
   │              ├── Lemming Execution Engine
   │              └── Tool Runtime
   │
   ├── Mandatory Persistent Volume
   │       └── lemmings_dets_data → /app/data/dets  (idle snapshots)
   │
   └── Optional Mounted Volumes
           ├── /workspace/project
           └── /data/artifacts
```

Only explicitly mounted directories become visible inside the container. The host filesystem remains inaccessible by default.

The DETS volume is mandatory: its absence does not cause a startup error but will silently break idle Lemming rehydration after any container restart.

# Persistent Volume Requirements

Container deployments have one mandatory persistent volume and one optional persistent volume.

## DETS Snapshot Directory (mandatory)

The DETS idle-snapshot store (ADR-0008) must be backed by a persistent volume. The runtime writes idle Lemming snapshots to a configurable path on the local filesystem. OCI containers destroy their ephemeral filesystem layer on restart; without a persistent volume, all idle snapshots are lost on container restart and the rehydration guarantee described in ADR-0008 cannot be fulfilled.

Required volume mount:

```
-v lemmings_dets_data:/app/data/dets
```

The path inside the container is configurable via the `DETS_DATA_DIR` environment variable and defaults to `/app/data/dets`.

This volume must be configured before the first container start. Operators who omit it will experience silent rehydration failures after any container restart; there is no startup error.

## Workspace / Artifact Directories (optional)

External directories may be mounted to give tools access to project files or artifact output:

```
-v ./project:/workspace/project
```

These mounts are operator-controlled and optional.

---

# Configuration

Runtime configuration is provided at startup.

Configuration sources:

- environment variables
- `runtime.exs`

Typical environment variables include:

```
DATABASE_URL
NODE_NAME
WORLD_ID
SECRET_KEY_BASE
DETS_DATA_DIR
```

Configuration resolution occurs during release boot.

---

# Implementation Notes

Deployment requires the following artifacts:

```
Dockerfile
mix release
runtime.exs
```

The project distributes a **reference `docker-compose.yml`** at the repo root
that serves as the canonical local multi-City demo.

Shipped compose stack:

- PostgreSQL database (optional `db` profile; operators may use an external DB)
- One world/control-plane container (runs migrations, Phoenix UI, and acts as
  a City)
- Two city containers (`city_a`, `city_b`) running the same image with
  different identity env vars

The compose file is provided **for local development and demo purposes**.

Operators may instead use:

- externally managed PostgreSQL databases
- existing container orchestration platforms
- manual container deployment

Key runtime modules involved in bootstrapping include:

```
LemmingsOs.Application
LemmingsOs.World.Registry
LemmingsOs.City.Supervisor
```

These modules initialize the runtime hierarchy during application startup.

---

# Considered Options

## Running directly with `mix phx.server` in production

Rejected.

Running the development server in production provides poor operational guarantees and lacks reproducible builds.

---

## Non-container deployment

Rejected.

While technically possible, bare-metal deployments introduce environment drift and reduce reproducibility.

Container packaging provides a stable runtime environment.

---

## Kubernetes-only deployment

Rejected.

Mandating Kubernetes would significantly increase operational complexity and exclude smaller self-hosted installations.

Kubernetes can still be supported later as an optional deployment target.

---

# Consequences

## Positive

- Predictable runtime topology: each City maps to exactly one container, making
  the relationship between architecture and infrastructure unambiguous.
- Reproducible builds: the Mix Release + OCI image pipeline produces identical
  artifacts across environments.
- Simplified self-hosting: a reference `docker-compose.yml` gives operators a
  working stack without infrastructure expertise.
- Container filesystem isolation reduces the blast radius if a tool process
  escapes its sandbox; the host filesystem remains inaccessible by default.

## Negative / Trade-offs

- **Erlang distribution security**: Erlang distribution is unauthenticated by
  default (shared cookie only) and unencrypted. A World cluster exposed on a
  public or shared network is vulnerable to node impersonation and traffic
  interception. Distribution TLS and strict cookie management are required for
  any production deployment outside a trusted private network.
- **External PostgreSQL dependency**: the container does not bundle a database.
  Operators must provision and maintain a PostgreSQL instance independently.
  This is standard for production but adds setup friction for first-time
  self-hosters.
- **Mandatory DETS persistent volume**: idle Lemming snapshots require a
  persistent volume mount (see Persistent Volume Requirements). Omitting it
  causes silent rehydration failures after container restart with no startup
  error.
- **Container image size**: bundling the full OTP release and a minimal OS
  environment produces a non-trivial image. Unmanaged image growth as
  dependencies accumulate can slow CI and increase registry storage costs.
- **Node startup time**: OTP release boot, supervision tree initialization, and
  lazy cache population add startup latency compared to direct `mix phx.server`
  usage. This is most noticeable in development iteration cycles.

## Mitigations

- Distribution TLS should be configured using `:inet_tls_dist` with operator-
  managed certificates, and the Erlang cookie must be treated as a secret
  (injected via `RELEASE_COOKIE` env var, not committed to the repository).
  The reference `docker-compose.yml` will document this as a required step for
  any non-localhost deployment.
- The reference compose file bundles PostgreSQL for convenience. Operators who
  need managed Postgres (RDS, Supabase, etc.) substitute the `DATABASE_URL`
  environment variable without other changes.
- The DETS volume is pre-configured in the reference compose file. Operators
  deploying without compose are warned in the Persistent Volume Requirements
  section above.
- Multi-stage Dockerfiles (builder + runtime image) keep the final image small
  by discarding build tooling. Image size discipline should be enforced in CI.

## Future Extensions

- Kubernetes deployment model and Helm chart.
- Multi-world gateway nodes.
- Autoscaling strategies for City containers.
