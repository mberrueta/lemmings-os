# City Management -- Operator Guide

## Overview

City management gives LemmingsOS operators visibility into multi-node deployments. Each running LemmingsOS instance registers itself as a City within a single World, writes periodic heartbeats to the shared database, and reports its liveness through the operator UI.

This document covers:

- The City data model and its relationship to the World
- How cities are created, registered, and tracked at runtime
- How heartbeat-driven liveness works
- How to run the multi-city Docker Compose demo
- How to operate cities through the UI

For Department-specific operator flows, see
[`docs/operator/department-management.md`](department-management.md).

---

## Concepts

### City vs World

LemmingsOS uses a four-level hierarchy: World, City, Department, Lemming. A **World** is the hard isolation boundary -- one per deployment or tenant. A **City** is a running Elixir/OTP node within that World. There is always one World and at least one City in any deployment.

All City rows are scoped to a World. Context APIs require explicit World scope for every query.

### Administrative status vs runtime liveness

These are two separate dimensions:

- **Status** is an operator-set administrative field. Valid values: `active`, `disabled`, `draining`. The system never changes status automatically. An operator sets it through the UI or database.

- **Liveness** is derived at read time from the `last_seen_at` heartbeat timestamp. It is not persisted. Valid values:
  - `alive` -- the city has heartbeated within the freshness threshold
  - `stale` -- the city has not heartbeated within the freshness threshold
  - `unknown` -- no heartbeat has ever been recorded for this city

A city can be `active` (status) and `stale` (liveness) simultaneously. This means the operator considers it enabled, but the runtime has stopped reporting. The two dimensions are independent by design.

### node_name

Every City has a `node_name` field that stores the full BEAM node identity in `name@host` form (for example, `world@world` or `city_a@city_a`). This is the canonical runtime identity used for upsert lookups during startup.

The `node_name` format is validated with the regex `^[^@\s]+@[^@\s]+$`. It must contain exactly one `@` separator with non-empty, non-whitespace parts on each side.

`node_name` is unique per World (enforced by a database unique index on `(world_id, node_name)`).

---

## City Lifecycle

### Bootstrap path: first city creation

On application startup, the following sequence runs (see `LemmingsOs.Application`):

1. The supervisor tree starts, including the Ecto Repo and the Heartbeat GenServer.
2. After the supervisor starts successfully, `maybe_run_world_bootstrap_import/0` runs, importing the default World from `priv/default.world.yaml` if it does not already exist.
3. `maybe_sync_runtime_city/0` runs next, calling `LemmingsOs.Cities.Runtime.sync_runtime_city!/0`.
4. The runtime module resolves the default World, reads City identity from application config (sourced from environment variables), and upserts the City row.

If no persisted default World can be resolved at step 3, the application raises and fails to start.

### How a runtime node upserts its presence

`LemmingsOs.Cities.Runtime.sync_runtime_city!/0` performs these steps:

1. Calls `Worlds.get_default_world/0` to find the persisted World.
2. Builds City attributes from runtime configuration: `node_name`, `slug`, `name`, `host`, `distribution_port`, `epmd_port`, and sets `status` to `"active"`.
3. Calls `Cities.upsert_runtime_city/2`, which looks up an existing City row by `id`, then `node_name`, then `slug` (in that order), and either updates the existing row or inserts a new one.

If `LEMMINGS_CITY_SLUG` and `LEMMINGS_CITY_NAME` are not set, they are derived from `node_name`:
- `slug` is derived by taking the part before `@`, lowercasing it, and replacing non-alphanumeric characters with hyphens.
- `name` is derived by splitting the slug on hyphens and capitalizing each word.

### How additional cities are created

Additional cities can be created in two ways:

1. **Another runtime node starts** with different `LEMMINGS_CITY_*` environment variables, connecting to the same database. It upserts its own City row on startup.
2. **An operator creates a city manually** through the Cities UI. This creates a row in the database, but no runtime node is attached to it until a process starts with a matching `node_name`.

### Heartbeat GenServer startup

The `LemmingsOs.Cities.Heartbeat` GenServer starts as part of the application supervision tree (before the runtime city sync runs). On its first heartbeat tick, if it does not find its City row, it attempts to call `sync_runtime_city/0` to create one. This provides resilience if the initial sync was skipped or if the heartbeat worker starts before the sync callback runs.

---

## Heartbeat and Liveness

### What last_seen_at is

`last_seen_at` is a UTC datetime column on the `cities` table. It records the most recent time the City's heartbeat worker successfully wrote to the database. It is updated via `Cities.heartbeat_city/2`, which truncates the timestamp to second precision.

### Who writes it

Only the local City's own Heartbeat GenServer writes `last_seen_at`. There is no remote health polling. Each City is exclusively responsible for reporting its own presence.

### Heartbeat interval

The heartbeat fires every **30 seconds** by default.

This is configured in `config/config.exs`:

```elixir
config :lemmings_os, :runtime_city_heartbeat,
  interval_ms: 30_000,
  freshness_threshold_seconds: 90
```

The interval can be overridden at runtime via the `LEMMINGS_CITY_HEARTBEAT_INTERVAL_MS` environment variable.

### Freshness threshold and liveness derivation

Liveness is computed by `City.liveness/2` at read time, not persisted:

- **alive**: `last_seen_at` is within the freshness threshold (default **90 seconds**) of the current time
- **stale**: `last_seen_at` is older than the freshness threshold
- **unknown**: `last_seen_at` is `nil` (no heartbeat has ever been recorded)

The threshold can be overridden at runtime via the `LEMMINGS_CITY_STALE_AFTER_SECONDS` environment variable.

With the default 30-second interval and 90-second threshold, a city goes stale after missing approximately 3 consecutive heartbeats.

### What the operator sees when a city is stale

The UI renders liveness separately from administrative status. A stale city is visually distinct from an alive city. The liveness value updates on every page load or LiveView navigation, since it is derived from the current time and the persisted `last_seen_at`.

### Status is never changed by heartbeat

The heartbeat worker only writes `last_seen_at`. It never reads, interprets, or mutates the `status` field. Administrative status changes are operator-only actions.

---

## Environment Variables

### City identity variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `LEMMINGS_CITY_NODE_NAME` | No | `Atom.to_string(node())` | Full BEAM node identity in `name@host` form. Canonical runtime identity for upsert lookups. |
| `LEMMINGS_CITY_SLUG` | No | Derived from `node_name` | URL-safe city identifier. Unique per World. |
| `LEMMINGS_CITY_NAME` | No | Derived from `slug` | Human-readable city display name. |
| `LEMMINGS_CITY_HOST` | No | Derived from `node_name` | Host portion of the node identity. Stored as a connectivity hint. |
| `LEMMINGS_CITY_DISTRIBUTION_PORT` | No | `nil` | Future-facing Erlang distribution port hint. Not used for connectivity in this release. |
| `LEMMINGS_CITY_EPMD_PORT` | No | `nil` | Future-facing EPMD port hint. Not used for connectivity in this release. |

### Heartbeat variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `LEMMINGS_CITY_HEARTBEAT_INTERVAL_MS` | No | `30000` | Milliseconds between heartbeat writes. |
| `LEMMINGS_CITY_STALE_AFTER_SECONDS` | No | `90` | Seconds after which a missing heartbeat marks liveness as `stale`. |

### Application and infrastructure variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `DATABASE_URL` | Yes (prod) | -- | Ecto database URL. Required in production. Example: `ecto://USER:PASS@HOST/DATABASE` |
| `SECRET_KEY_BASE` | Yes (prod) | -- | Phoenix secret for signing cookies and sessions. Generate with `mix phx.gen.secret`. |
| `PHX_HOST` | No | `localhost` (compose), `example.com` (prod) | Hostname for Phoenix URL generation. |
| `PORT` | No | `4000` | HTTP listen port. |
| `PHX_SERVER` | No | not set | Set to `true` to start the Phoenix HTTP server. Only the world node sets this in the compose demo. |
| `RELEASE_DISTRIBUTION` | No | -- | Set to `none` to disable Erlang distribution. All compose demo containers set this. |
| `POOL_SIZE` | No | `10` | Ecto connection pool size. |
| `ECTO_IPV6` | No | not set | Set to `true` or `1` to enable IPv6 socket options for Ecto. |
| `DNS_CLUSTER_QUERY` | No | not set | DNS query for libcluster node discovery. Not used in the compose demo. |

### Compose-only variables (set in docker-compose.yml or .env)

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `POSTGRES_USER` | No | `postgres` | Username for the managed Postgres container (profile `db` only). |
| `POSTGRES_PASSWORD` | No | `postgres` | Password for the managed Postgres container (profile `db` only). |
| `POSTGRES_DB` | No | `lemmings_os_prod` | Database name for the managed Postgres container (profile `db` only). |
| `PHX_PORT` | No | `4000` | Host port for the world web UI (used in the `PORT` mapping). |

---

## Running the Multi-City Demo

### Prerequisites

- Docker and Docker Compose (v2)
- A terminal
- Ability to generate a Phoenix secret (`mix phx.gen.secret`, or any 64+ byte random string)

### Step-by-step

**1. Create the `.env` file**

```bash
cp .env.example .env
```

Edit `.env` and set `SECRET_KEY_BASE` to a generated secret. You can generate one with:

```bash
mix phx.gen.secret
```

Or use any method to produce a random string of at least 64 bytes.

**2. Choose a Postgres option and start the demo**

Option A -- you already have Postgres running locally:

```bash
# Edit .env: set DATABASE_URL pointing at your Postgres instance
# Example: DATABASE_URL=ecto://postgres:postgres@localhost/lemmings_os_prod
docker compose up --build
```

Option B -- let Docker manage Postgres:

```bash
# No DATABASE_URL needed; the managed db container handles it
docker compose --profile db up --build
```

**3. Wait for startup**

The `world` service runs database creation and migrations before starting the Phoenix server. Docker waits for the world node's `/healthz` endpoint to respond before starting city nodes, so startup is fully ordered and no connection retry logs from city nodes are expected under normal conditions.

**4. Verify system health via `/healthz`**

The world node exposes a `/healthz` endpoint that returns a JSON snapshot of the system state, including the last-known liveness of each registered city:

```bash
curl http://localhost:4060/healthz
```

```json
{
  "status": "ok",
  "node": "world@world",
  "cities": [
    {"node_name": "world@world",   "name": "World Node", "status": "active", "liveness": "alive"},
    {"node_name": "city_a@city_a", "name": "City A",     "status": "active", "liveness": "alive"},
    {"node_name": "city_b@city_b", "name": "City B",     "status": "active", "liveness": "alive"}
  ]
}
```

City liveness is derived from `last_seen_at` freshness — it reflects the last heartbeat the city itself reported, not an active probe. HTTP 200 means the world node is up and can reach the database; city liveness is informational in the body. HTTP 503 means the world node cannot reach the database.

**5. Open the UI**

Navigate to `http://localhost:4000` (or `http://localhost:${PHX_PORT}` if you overrode it).

**6. Verify cities appear**

Navigate to the Cities page. You should see three cities:
- `World Node` (slug: `world`, node: `world@world`)
- `City A` (slug: `city-a`, node: `city_a@city_a`)
- `City B` (slug: `city-b`, node: `city_b@city_b`)

All three should show liveness as `alive`.

### Simulating a stale city

```bash
docker compose stop city_a
```

Wait approximately 90 seconds (the default freshness threshold). Refresh or revisit the Cities page. City A should now show liveness as `stale`.

To recover:

```bash
docker compose start city_a
```

City A's heartbeat worker resumes, writes `last_seen_at`, and liveness returns to `alive` on the next page load.

### How the demo works

All containers run the same Docker image built from the repository root. Identity is controlled entirely by environment variables:

- The `world` service starts Phoenix with `PHX_SERVER=true`, runs migrations, and registers as a city (`world@world`).
- The `city_a` and `city_b` services run the same application without Phoenix HTTP (`PHX_SERVER` is not set). They register their own City rows and run heartbeat workers.
- All containers use `network_mode: host` and connect to the same Postgres instance.
- All containers set `RELEASE_DISTRIBUTION=none` -- there is no Erlang distribution or clustering.

### Stopping and cleaning up

```bash
docker compose down           # stop containers
docker compose down -v        # stop containers and remove the Postgres volume
```

---

## Operator Flows (UI)

### Cities list

The Cities page at `/cities` shows all persisted City rows for the current World. Each city displays its name, slug, node name, administrative status, and derived liveness.

### Viewing city details

Click a city in the list or navigate to `/cities?city=<city_id>` to see the full city detail, including config overrides and heartbeat timestamps.

### Creating a city manually

Click the "New City" button on the Cities page. The form requires:
- **Slug** -- URL-safe identifier, unique within the World
- **Name** -- Human-readable display name
- **Node name** -- Full BEAM identity in `name@host` form
- **Status** -- One of `active`, `disabled`, `draining`

Optional fields: host, distribution port, EPMD port, and config override buckets (limits, runtime, costs, models).

Creating a city through the UI inserts a row, but no runtime node is attached until a process starts with a matching `node_name` and writes a heartbeat.

### Editing a city

Click the edit action on any city. The form allows changing metadata and config overrides. The `world_id` is not editable (it is set by the context, not the form).

### Deleting a city

Click the delete action on any city. The city row is removed. If a running node still references that city, the heartbeat worker will fail to find its row and log errors until the node is stopped or reconfigured.

### Reading liveness from the UI

Liveness badges are computed on every page load from `last_seen_at` and the configured freshness threshold. They are not cached or pushed via PubSub. Refreshing the page or navigating away and back recalculates liveness.

---

## Security Notes

- **No authentication on the operator UI.** The Cities LiveView does not enforce login or per-user authorization. It is designed as an internal operator console. Network-level access control (VPN, reverse proxy auth, private network) is assumed.

- **No distributed Erlang.** All compose demo containers set `RELEASE_DISTRIBUTION=none`. Nodes communicate only through the shared Postgres database. There is no Erlang distribution, no cluster membership, and no inter-node message passing.

- **No Erlang cookie storage.** The Erlang cookie is not stored in the database or shared between nodes. Since distribution is disabled, the cookie is irrelevant.

- **No secrets in source control.** `SECRET_KEY_BASE` is read from the `.env` file, which is gitignored. Database credentials in `docker-compose.yml` use default values suitable only for local development.

- **Secure remote city onboarding is deferred.** The current model trusts any process that can write to the shared database. A future ADR will address secure attachment, encrypted secret distribution, and identity verification for remote City nodes.

---

## Known Limitations

- **No automatic city discovery.** Cities must be registered explicitly through environment-variable-driven startup or manual UI creation.

- **No remote health polling.** Each city writes only its own `last_seen_at`. No city or control plane polls other cities for health. Liveness is inferred from heartbeat staleness, not active probing.

- **No failover or work rescheduling.** When a city goes stale, its workload is not migrated to another city. There is no work dispatch between cities.

- **No distributed Erlang clustering.** Nodes share a database but do not form an Erlang cluster. Cross-node GenServer calls, PubSub, and process monitoring are not available.

- **Secure remote attachment not implemented.** Any process that can connect to the database can register as a city. Trust is database-access-level only.

- **Department runtime orchestration not yet implemented.** Department rows are
  now persisted, but City-hosted Department supervisors, Department managers,
  and Department-backed Lemming execution are still deferred.

- **Liveness is not pushed in real time.** The UI computes liveness on page load. There is no LiveView push or PubSub broadcast when a city goes stale. The operator must refresh or navigate to see updated liveness.

- **City nodes do not serve HTTP.** In the compose demo, only the world node runs the Phoenix HTTP server. City nodes run the application and heartbeat worker but have no web interface.
