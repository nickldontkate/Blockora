-- BLOCKORA backend — initial schema
-- Migration convention: files are numbered `NNNN_description.sql` and applied
-- in order via `wrangler d1 migrations apply`. Wrangler tracks applied
-- migrations itself in the `d1_migrations` table (auto-created) — do not
-- create a table with that name. Never edit an already-applied migration;
-- add a new numbered file instead.
--
-- Conventions used throughout:
--   * All ids are TEXT (UUID v4 generated with crypto.randomUUID() at the
--     application layer) unless noted otherwise.
--   * Resource-like amounts (coins, food, energy, goods, data, blocks) are
--     always INTEGER. The game never deals in fractional resources — this
--     avoids float drift across millions of production ticks.
--   * Any column suffixed `_json` stores a JSON-encoded TEXT blob. D1/SQLite
--     has no native JSON type; these are validated/parsed in the app layer
--     (see backend/src/lib/validation.ts) and should be treated as opaque
--     by anything that isn't the owning route.
--   * All timestamps are INTEGER unix epoch seconds (UTC), never floats,
--     never client-supplied for anything security/reward relevant.

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- players / sessions
-- ---------------------------------------------------------------------------

CREATE TABLE players (
  id                TEXT PRIMARY KEY,
  auth_subject      TEXT NOT NULL UNIQUE, -- opaque external id (Sign in with Apple `sub`, or device id for guest play)
  auth_provider     TEXT NOT NULL DEFAULT 'apple' CHECK (auth_provider IN ('apple', 'guest')),
  display_name      TEXT NOT NULL,
  created_at        INTEGER NOT NULL,
  last_login_at     INTEGER NOT NULL,
  -- Server-authoritative clock used as the baseline for offline production
  -- simulation. Updated every time production is reconciled (collect,
  -- claim-offline, module place/remove). NEVER trust a client-sent value
  -- to compute elapsed offline time — always diff against this column.
  last_sync_at      INTEGER NOT NULL,
  is_banned         INTEGER NOT NULL DEFAULT 0 CHECK (is_banned IN (0, 1))
);

CREATE UNIQUE INDEX idx_players_auth_subject ON players(auth_subject);

CREATE TABLE sessions (
  id            TEXT PRIMARY KEY, -- sha256 hash of the bearer token, never the raw token
  player_id     TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  created_at    INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL,
  revoked_at    INTEGER,
  user_agent    TEXT
);

CREATE INDEX idx_sessions_player_id ON sessions(player_id);
CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);

-- ---------------------------------------------------------------------------
-- resources
-- ---------------------------------------------------------------------------

CREATE TABLE player_resources (
  player_id     TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  resource_type TEXT NOT NULL CHECK (resource_type IN ('COINS', 'FOOD', 'ENERGY', 'GOODS', 'DATA', 'BLOCKS')),
  amount        INTEGER NOT NULL DEFAULT 0 CHECK (amount >= 0),
  updated_at    INTEGER NOT NULL,
  PRIMARY KEY (player_id, resource_type)
);

-- Every reward/spend touches this table by player_id; the PK already covers
-- point lookups, this covers "all resources for player" scans ordered nicely.
CREATE INDEX idx_player_resources_player_id ON player_resources(player_id);

-- ---------------------------------------------------------------------------
-- city / districts / buildings / modules
-- ---------------------------------------------------------------------------

CREATE TABLE cities (
  id                    TEXT PRIMARY KEY,
  player_id             TEXT NOT NULL UNIQUE REFERENCES players(id) ON DELETE CASCADE,
  name                  TEXT NOT NULL,
  level                 INTEGER NOT NULL DEFAULT 1,
  founded_at            INTEGER NOT NULL,
  -- Baseline for the resource-constrained offline simulation. Distinct from
  -- players.last_sync_at only conceptually (one player -> one city today);
  -- kept on the city so a future multi-city player model doesn't require
  -- a schema change.
  last_offline_sync_at  INTEGER NOT NULL
);

CREATE INDEX idx_cities_player_id ON cities(player_id);

CREATE TABLE districts (
  id            TEXT PRIMARY KEY,
  city_id       TEXT NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
  kind          TEXT NOT NULL, -- e.g. 'residential', 'industrial', 'agricultural', 'data'
  grid_x        INTEGER NOT NULL,
  grid_y        INTEGER NOT NULL,
  unlocked_at   INTEGER NOT NULL
);

CREATE INDEX idx_districts_city_id ON districts(city_id);
CREATE UNIQUE INDEX idx_districts_city_grid ON districts(city_id, grid_x, grid_y);

CREATE TABLE buildings (
  id            TEXT PRIMARY KEY,
  district_id   TEXT NOT NULL REFERENCES districts(id) ON DELETE CASCADE,
  plot_x        INTEGER NOT NULL,
  plot_y        INTEGER NOT NULL,
  name          TEXT NOT NULL DEFAULT '',
  rotation      INTEGER NOT NULL DEFAULT 0 CHECK (rotation IN (0, 90, 180, 270)),
  -- Cached max weight the current module layout may draw on (structural
  -- physics ceiling); recomputed server-side on every place/remove so the
  -- client never has to be trusted for support calculations.
  support_capacity INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);

CREATE INDEX idx_buildings_district_id ON buildings(district_id);
CREATE UNIQUE INDEX idx_buildings_district_plot ON buildings(district_id, plot_x, plot_y);

CREATE TABLE building_modules (
  id                TEXT PRIMARY KEY,
  building_id       TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  module_type       TEXT NOT NULL, -- e.g. 'SOLAR', 'SERVER', 'COOLING', 'STORAGE', 'CORE', 'FARM_FIELD', 'GREENHOUSE', 'WATER_TANK'
  grid_x            INTEGER NOT NULL, -- position within the building's module grid
  grid_y            INTEGER NOT NULL,
  rotation          INTEGER NOT NULL DEFAULT 0 CHECK (rotation IN (0, 90, 180, 270)),
  installed_at      INTEGER NOT NULL,
  -- Denormalized snapshot of the last computed per-hour production for this
  -- module (post-synergy, post-world-event modifiers), refreshed whenever
  -- the layout or active modifiers change. Used to make offline simulation
  -- and "collect" cheap without recomputing the whole synergy graph from
  -- scratch on every request. The authoritative recompute path still lives
  -- in backend/src/game/balance.ts.
  effective_rates_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_building_modules_building_id ON building_modules(building_id);
CREATE UNIQUE INDEX idx_building_modules_building_grid ON building_modules(building_id, grid_x, grid_y);

-- Modules a player owns but hasn't placed yet (crafted, bought via contract
-- reward, or granted by a mission). Placing a module decrements this and
-- inserts into building_modules; removing a module does the reverse.
CREATE TABLE module_inventory (
  player_id     TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  module_type   TEXT NOT NULL,
  quantity      INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  updated_at    INTEGER NOT NULL,
  PRIMARY KEY (player_id, module_type)
);

CREATE INDEX idx_module_inventory_player_id ON module_inventory(player_id);

-- Saved building layouts. This is layout-only (module types + grid
-- positions + rotations) — it never grants or checks resources/inventory.
-- The client is responsible for checking module availability against its
-- own inventory view before/while applying a blueprint; the server only
-- validates structural legality at the moment of actual placement.
CREATE TABLE blueprints (
  id            TEXT PRIMARY KEY,
  player_id     TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  building_kind TEXT NOT NULL DEFAULT 'generic',
  layout_json   TEXT NOT NULL, -- JSON: { width, height, modules: [{moduleType, x, y, rotation}] }
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);

CREATE INDEX idx_blueprints_player_id ON blueprints(player_id);

CREATE TABLE workers (
  id                    TEXT PRIMARY KEY,
  city_id               TEXT NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
  name                  TEXT NOT NULL,
  role                  TEXT NOT NULL, -- e.g. 'engineer', 'farmer', 'technician'
  assigned_building_id  TEXT REFERENCES buildings(id) ON DELETE SET NULL,
  production_bonus_bp   INTEGER NOT NULL DEFAULT 0, -- basis points (100 = +1%) applied to the assigned building
  morale                INTEGER NOT NULL DEFAULT 100 CHECK (morale BETWEEN 0 AND 100),
  hired_at              INTEGER NOT NULL
);

CREATE INDEX idx_workers_city_id ON workers(city_id);
CREATE INDEX idx_workers_assigned_building_id ON workers(assigned_building_id);

-- ---------------------------------------------------------------------------
-- contracts
-- ---------------------------------------------------------------------------

-- Contract templates/offers. A row here is a definition; player_contracts
-- tracks a given player's acceptance/progress against it.
CREATE TABLE contracts (
  id                        TEXT PRIMARY KEY,
  code                      TEXT NOT NULL UNIQUE,
  title                     TEXT NOT NULL,
  description               TEXT NOT NULL DEFAULT '',
  required_resources_json   TEXT NOT NULL, -- JSON: { "COINS": 100, "GOODS": 40, ... }
  reward_coins              INTEGER NOT NULL DEFAULT 0,
  reward_blocks             INTEGER NOT NULL DEFAULT 0,
  reward_module_pack_json   TEXT NOT NULL DEFAULT '[]', -- JSON: [{ "moduleType": "SOLAR", "quantity": 2 }]
  duration_seconds          INTEGER NOT NULL, -- delivery window length once accepted
  min_city_level            INTEGER NOT NULL DEFAULT 1,
  available_from            INTEGER NOT NULL,
  available_until           INTEGER, -- NULL = no upper bound
  created_at                INTEGER NOT NULL
);

CREATE INDEX idx_contracts_availability ON contracts(available_from, available_until);

CREATE TABLE player_contracts (
  id                        TEXT PRIMARY KEY,
  player_id                 TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  contract_id               TEXT NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
  status                    TEXT NOT NULL DEFAULT 'accepted' CHECK (status IN ('accepted', 'completed', 'failed', 'expired')),
  accepted_at               INTEGER NOT NULL,
  expires_at                INTEGER NOT NULL, -- accepted_at + contracts.duration_seconds, computed server-side
  delivered_resources_json  TEXT NOT NULL DEFAULT '{}',
  completed_at              INTEGER
);

CREATE INDEX idx_player_contracts_player_id ON player_contracts(player_id);
-- Sweeping/checking expiry (used by the "list active contracts" and the
-- lazy expiry check that runs on every contract read) needs status+expiry.
CREATE INDEX idx_player_contracts_status_expiry ON player_contracts(status, expires_at);
-- A player can only have one active (accepted) instance of a given contract.
CREATE UNIQUE INDEX idx_player_contracts_active_unique
  ON player_contracts(player_id, contract_id)
  WHERE status = 'accepted';

-- ---------------------------------------------------------------------------
-- world events (time-boxed global modifiers)
-- ---------------------------------------------------------------------------

CREATE TABLE world_events (
  id              TEXT PRIMARY KEY,
  code            TEXT NOT NULL,
  title           TEXT NOT NULL,
  description     TEXT NOT NULL DEFAULT '',
  modifiers_json  TEXT NOT NULL, -- JSON: [{ "resource": "DATA", "kind": "demand", "percent": 80 }]
  starts_at       INTEGER NOT NULL,
  ends_at         INTEGER NOT NULL,
  created_at      INTEGER NOT NULL
);

-- Active/upcoming lookups always filter/order by the time window.
CREATE INDEX idx_world_events_window ON world_events(starts_at, ends_at);

-- ---------------------------------------------------------------------------
-- world project (single shared cooperative goal, coordinated by the
-- WorldProjectRoom Durable Object; these tables are the DO's durable
-- backing store, not a second source of truth)
-- ---------------------------------------------------------------------------

CREATE TABLE world_projects (
  id                  TEXT PRIMARY KEY,
  code                TEXT NOT NULL UNIQUE, -- e.g. 'orbital_elevator_s1' — DO instance is keyed off this
  title               TEXT NOT NULL,
  description         TEXT NOT NULL DEFAULT '',
  goal_resources_json TEXT NOT NULL, -- JSON: { "GOODS": 500000, "DATA": 120000 }
  progress_json       TEXT NOT NULL DEFAULT '{}', -- JSON snapshot of current totals per resource, mirrors DO state
  status              TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'archived')),
  reward_json         TEXT NOT NULL DEFAULT '{}', -- JSON reward given to all contributors on completion
  started_at          INTEGER NOT NULL,
  completed_at        INTEGER
);

CREATE INDEX idx_world_projects_status ON world_projects(status);

CREATE TABLE world_contributions (
  id                TEXT PRIMARY KEY,
  world_project_id  TEXT NOT NULL REFERENCES world_projects(id) ON DELETE CASCADE,
  player_id         TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  resource_type     TEXT NOT NULL CHECK (resource_type IN ('COINS', 'FOOD', 'ENERGY', 'GOODS', 'DATA', 'BLOCKS')),
  amount            INTEGER NOT NULL CHECK (amount > 0),
  idempotency_key   TEXT NOT NULL,
  contributed_at    INTEGER NOT NULL
);

CREATE INDEX idx_world_contributions_project ON world_contributions(world_project_id);
CREATE INDEX idx_world_contributions_player ON world_contributions(world_project_id, player_id);
CREATE UNIQUE INDEX idx_world_contributions_idempotency ON world_contributions(world_project_id, player_id, idempotency_key);

-- ---------------------------------------------------------------------------
-- missions (lightweight quest/achievement layer)
-- ---------------------------------------------------------------------------

CREATE TABLE missions (
  id                  TEXT PRIMARY KEY,
  code                TEXT NOT NULL UNIQUE,
  title               TEXT NOT NULL,
  description         TEXT NOT NULL DEFAULT '',
  requirements_json   TEXT NOT NULL, -- JSON: { "type": "produce", "resource": "GOODS", "amount": 1000 }
  reward_json         TEXT NOT NULL DEFAULT '{}',
  repeatable          INTEGER NOT NULL DEFAULT 0 CHECK (repeatable IN (0, 1)),
  created_at          INTEGER NOT NULL
);

CREATE TABLE player_missions (
  id              TEXT PRIMARY KEY,
  player_id       TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  mission_id      TEXT NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'claimed')),
  progress_json   TEXT NOT NULL DEFAULT '{}',
  started_at      INTEGER NOT NULL,
  completed_at    INTEGER
);

CREATE INDEX idx_player_missions_player_status ON player_missions(player_id, status);

-- ---------------------------------------------------------------------------
-- transactions (idempotency ledger + audit trail for every resource grant)
-- ---------------------------------------------------------------------------

-- Every endpoint that grants or spends resources writes exactly one row
-- here inside the same D1 batch/transaction as the mutation. The
-- (player_id, idempotency_key) unique index is what makes retried/replayed
-- client requests safe: a repeat with the same key is detected before any
-- resource mutation happens (see backend/src/lib/idempotency.ts).
CREATE TABLE transactions (
  id                  TEXT PRIMARY KEY, -- internal uuid
  player_id           TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  idempotency_key     TEXT NOT NULL,
  kind                TEXT NOT NULL, -- 'collect_production' | 'offline_rewards' | 'contract_accept' | 'contract_complete' | 'module_place' | 'module_remove' | 'world_contribution' | 'mission_claim'
  resource_deltas_json TEXT NOT NULL DEFAULT '{}', -- JSON: { "COINS": 120, "GOODS": -40 }
  payload_json        TEXT NOT NULL DEFAULT '{}', -- request-specific detail, for audit/debugging
  created_at          INTEGER NOT NULL
);

CREATE UNIQUE INDEX idx_transactions_player_idempotency ON transactions(player_id, idempotency_key);
CREATE INDEX idx_transactions_player_created ON transactions(player_id, created_at);
