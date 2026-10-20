import type { RequestContext } from '../types';
import { json } from '../lib/response';
import { parseJsonBody } from '../lib/validation';
import { resolveIdempotencyKey, runIdempotent } from '../lib/idempotency';
import { buildResourceDeltaStatements, getPlayerResources } from '../lib/resources';
import { reconcileProduction } from '../game/productionService';
import { nowSeconds } from '../lib/time';

/**
 * Shared handler body for both `collect` and `claim-offline`. They are the
 * same underlying operation (reconcile elapsed-time production against the
 * server-stored `last_offline_sync_at`, capped at
 * `OFFLINE_PRODUCTION_CAP_SECONDS`) — see game/productionService.ts. Kept
 * as two routes because the client shows very different UI for "you tapped
 * Collect" vs. "welcome back, here's what you missed", and because the
 * offline-claim response includes the extra away-time framing fields.
 *
 * NOTE on concurrency: the elapsed-time read (`cities.last_offline_sync_at`)
 * and the write that advances it happen inside the same `compute()` closure
 * passed to `runIdempotent`, which minimizes — but, given D1's lack of
 * interactive read-then-write transactions, cannot fully eliminate — the
 * race between two *different* idempotency keys for the same player
 * arriving concurrently (e.g. a genuine double-tap). The iOS client should
 * serialize collect/claim calls per player (never fire a second one before
 * the first resolves) to avoid double-crediting a short overlapping window.
 * This is a much smaller/rarer risk surface than the World Project's
 * many-players-one-counter case, which is why only that one needed a
 * Durable Object.
 */
async function reconcileAndRespond(ctx: RequestContext, kind: 'collect_production' | 'offline_rewards'): Promise<Response> {
  const playerId = ctx.auth!.playerId;
  const body = await parseJsonBody(ctx.request);
  const idempotencyKey = resolveIdempotencyKey(ctx.request, body);

  const response = await runIdempotent(ctx.env, playerId, idempotencyKey, kind, async () => {
    const result = await reconcileProduction(ctx.env, playerId);
    const now = nowSeconds();

    const statements = [
      ...buildResourceDeltaStatements(ctx.env, playerId, result.resourceDeltas),
      ctx.env.DB.prepare(`UPDATE cities SET last_offline_sync_at = ? WHERE id = ?`).bind(now, result.city.id),
      ctx.env.DB.prepare(`UPDATE players SET last_sync_at = ? WHERE id = ?`).bind(now, playerId),
    ];

    const resourcesAfter = await getPlayerResources(ctx.env, playerId);
    for (const [resource, delta] of Object.entries(result.resourceDeltas)) {
      resourcesAfter[resource as keyof typeof resourcesAfter] += delta ?? 0;
    }

    return {
      statements,
      resourceDeltas: result.resourceDeltas,
      response: {
        rawElapsedSeconds: result.rawElapsedSeconds,
        simulatedSeconds: result.simulatedSeconds,
        wasCapped: result.wasCapped,
        wasEnergyConstrained: result.wasEnergyConstrained,
        resourcesGained: result.resourceDeltas,
        unconstrainedPerHour: result.unconstrainedPerHour,
        resources: resourcesAfter,
      },
    };
  });

  return json(response);
}

/** POST /api/v1/production/collect — routine foreground collection. */
export async function collectProduction(ctx: RequestContext): Promise<Response> {
  return reconcileAndRespond(ctx, 'collect_production');
}

/** POST /api/v1/production/claim-offline — explicit "welcome back" claim. */
export async function claimOfflineRewards(ctx: RequestContext): Promise<Response> {
  return reconcileAndRespond(ctx, 'offline_rewards');
}
