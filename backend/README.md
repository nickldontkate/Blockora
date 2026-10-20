# BLOCKORA Backend

Server-authoritative Cloudflare Workers backend for BLOCKORA. The iOS client
(Swift/SwiftUI/SpriteKit, in the sibling directories at the repo root) talks
to this service for anything that touches resources, rewards, or shared
world state — the client never computes or asserts a resource amount that
the server then trusts.

## Stack

- **Cloudflare Workers** (TypeScript) — the API surface.
- **D1** (`DB` binding) — relational store: players, cities, contracts,
  transactions, etc. See `migrations/`.
- **Durable Objects** (`WORLD_PROJECT` binding, class `WorldProjectRoom`) —
  single coordinator for the shared cooperative World Project, so
  concurrent contributions from many players can't race.
- **KV** (`CONFIG` binding) — short-TTL read-through cache for game-balance
  data that would otherwise be re-queried from D1 on every request (right
  now: active world-event modifiers).

## Folder layout

```
backend/
  wrangler.toml            Worker + bindings config
  migrations/               Numbered D1 SQL migrations (schema + seed data)
  src/
    index.ts                Route registration + Worker entrypoint
    types.ts                Shared types, Env interface, ApiError
    lib/                     Generic infrastructure (not game-specific)
      auth.ts                Session bootstrap/verification (bearer tokens)
      router.ts              Minimal hand-rolled router + withAuth() middleware
      idempotency.ts          Replay-safe resource-mutation helper
      resources.ts            Resource ledger reads/writes/validation
      response.ts              JSON response + ApiError helpers
      validation.ts            Request body parsing/assertion helpers
      cityLoader.ts            D1 queries that assemble a player's city graph
      gameConfig.ts            KV-cached active world-event modifiers
      durableClient.ts         Typed client for calling the WorldProjectRoom DO
      time.ts                  now()/uuid()/clamp helpers (server clock only)
    game/                    Game-balance logic (pure functions where possible)
      moduleCatalog.ts         Module stats, structural rules, synergy table
      balance.ts               Synergy + world-event rate computation, offline sim
      productionService.ts     Shared reconciliation core for collect/claim-offline
    routes/                  One file per resource area
      auth.ts, city.ts, modules.ts, production.ts, contracts.ts,
      worldEvents.ts, worldProject.ts, blueprints.ts
    durable/
      WorldProjectRoom.ts      The Durable Object class
  test/                      vitest unit tests for the pure game-balance logic
```

## Running locally

```bash
cd backend
npm install

# Create the D1 database once (only needed the first time, or after wrangler.toml
# is reset) and paste the returned database_id into wrangler.toml:
npx wrangler d1 create blockora-db

# Create the KV namespace the same way, and paste the id/preview_id in:
npx wrangler kv namespace create CONFIG
npx wrangler kv namespace create CONFIG --preview

# Apply migrations to the local (Miniflare) D1 instance:
npm run migrations:apply:local

# Start the dev server:
npm run dev
```

`wrangler dev` runs the Worker, D1 (via Miniflare's local SQLite), Durable
Objects, and KV all locally — no Cloudflare account calls needed for local
iteration once the bindings above exist.

To apply migrations to a real (remote) D1 database instead:

```bash
npm run migrations:apply:remote
```

## Testing

```bash
npm test          # runs vitest once
npm run test:watch
npm run typecheck
```

The test suite covers the pure game-balance logic (`src/game/balance.ts`,
`src/lib/resources.ts`) — structural checks, synergy adjacency, and the
resource-constrained offline production simulation (e.g. a Factory's Goods
output getting throttled once its Energy stock runs dry). Route handlers
that need live D1/Durable Object bindings are exercised via `wrangler dev`
rather than vitest mocks, to avoid maintaining a parallel fake D1 layer.

## Migration convention

Files in `migrations/` are numbered `NNNN_description.sql` and applied in
order by `wrangler d1 migrations apply`, which tracks what's already been
applied in its own bookkeeping table. Never edit a migration that has
already been applied anywhere (including just your own local dev D1) — add
a new numbered file instead.

## Deploying

```bash
npm run deploy
```

Requires `wrangler.toml`'s `database_id` / KV `id` / `preview_id` to point
at real Cloudflare resources (see "Running locally" above for how to create
them) and `wrangler login` to have been run once.
